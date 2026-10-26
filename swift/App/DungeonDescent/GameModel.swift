import SwiftUI
import UIKit
import DungeonCore

/// App-wide state: the save file, the wallet and the character list.
@MainActor
final class GameModel: ObservableObject {
    let store: GameStore
    private let fileStore: FileStore
    let wallet: Wallet
    let achievements: AchievementBook
    let dailyQuests: DailyQuests
    private var roster: CharacterRoster

    @Published private(set) var characters: [PlayerCharacter] = []
    @Published private(set) var gold = 0
    @Published private(set) var diamonds = 0

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = FileStore(url: dir.appendingPathComponent("dd_store.json"))
        fileStore = file
        store = file
        wallet = Wallet(store: store)
        roster = CharacterRoster(store: store)
        achievements = AchievementBook(store: store, wallet: wallet)
        dailyQuests = DailyQuests(store: store)
        wallet.onChange = { [weak self] in self?.refresh() }
        achievements.onUnlock = { list in GameModel.announce(list) }
        achievements.payOutstandingRewards()
        refresh()
    }

    func refresh() {
        characters = roster.characters
        gold = wallet.gold
        diamonds = wallet.diamonds
    }

    var isRosterFull: Bool { roster.isFull }

    /// Writes the save to disk right away (when the app leaves the foreground).
    func saveNow() { fileStore.flushNow() }

    /// Achievement unlocked: a sound by tier, a spoken line and Game Center.
    static func announce(_ list: [Achievement]) {
        // Same tiers as the web version's playAchievementUnlockSound: a few special
        // achievements, then by gold reward.
        let special: Set<String> = ["ach-void-reaper", "ach-witness", "ach-dddi-boss", "ach-bossrush",
                                    "ach-ngplus3", "ach-all-stories", "ach-trilogy", "ach-kills-1000", "ach-abyssal-boss"]
        func rank(_ a: Achievement) -> Int { special.contains(a.id) ? 3 : a.gold >= 300 ? 2 : a.gold >= 200 ? 1 : 0 }
        guard let best = list.max(by: { rank($0) < rank($1) }) else { return }
        Sound.sfx(["sfx-unlock", "sfx-ach-silver", "sfx-ach-gold", "sfx-ach-special"][rank(best)])
        Feedback.success()
        for a in list {
            Feedback.announce("Achievement unlocked: \(a.name). \(a.desc) Plus \(a.gold) gold and \(a.trophies) troph\(a.trophies == 1 ? "y" : "ies").")
        }
        GameCenter.report(list)
    }

    func unlockedDungeons() -> [String] { roster.unlockedDungeons() }

    @discardableResult
    func create(_ ch: PlayerCharacter) -> Bool {
        let ok = roster.add(ch) != nil
        refresh()
        return ok
    }

    func delete(at index: Int) {
        roster.remove(at: index)
        refresh()
    }

    func updateCharacter(_ index: Int, _ change: (inout PlayerCharacter) -> Void) {
        roster.update(index, change)
        refresh()
    }

    var globalInventory: GlobalInventory { GlobalInventory(store: store) }

    /// The menu's familiar badge, "🐦‍⬛ Lv.3", from "dd_familiar" (updateFamiliarBadge).
    /// A player without one gets a random species, as in getFamiliar().
    var familiarBadge: String {
        let species = ["raven": "🐦‍⬛", "wisp": "✨", "imp": "👺", "cat": "🐈‍⬛"]
        var f: [String: JSONValue] = [:]
        if let s = store.getItem("dd_familiar"), let d = s.data(using: .utf8),
           let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) { f = v }
        var speciesId: String? { if case .string(let s)? = f["speciesId"] { return s } else { return nil } }
        if speciesId == nil {
            let id = species.keys.randomElement() ?? "raven"
            f = ["speciesId": .string(id), "startingSpeciesId": .string(id), "bond": .number(0), "name": .string("")]
            if let d = try? JSONEncoder().encode(f), let s = String(data: d, encoding: .utf8) { store.setItem("dd_familiar", s) }
        }
        let icon = species[speciesId ?? ""] ?? "🐦‍⬛"
        var bond = 0.0
        if case .number(let n)? = f["bond"] { bond = n }
        let level = Int(bond / 30) + 1
        let badge = level >= 20 ? "★" : level >= 10 ? "✧" : level >= 5 ? "✦" : ""
        return icon + (badge.isEmpty ? "" : " " + badge) + " Lv.\(level)"
    }

    // MARK: Importing the web version's save

    /// What a web save contains, for the confirmation message.
    struct WebSaveSummary {
        let characters: [PlayerCharacter]
        let gold: Int
        let diamonds: Int
        let keys: Int
    }

    static func summarize(_ data: [String: String]) -> WebSaveSummary {
        let probe = MemoryStore(data)
        return WebSaveSummary(characters: CharacterRoster(store: probe).characters,
                              gold: Wallet(store: probe).gold,
                              diamonds: Wallet(store: probe).diamonds,
                              keys: data.count)
    }

    /// Replaces this app's save with the web version's. Swift's own runs in
    /// progress are dropped, since they belong to the characters being replaced.
    func importWebSave(_ data: [String: String]) {
        store.setItems(data.filter { $0.key.hasPrefix("dd_") && !$0.key.hasPrefix("dd_swift_") })
        roster = CharacterRoster(store: store)
        UserDefaults.standard.set(true, forKey: "swift_web_import_done")
        achievements.reload()
        achievements.payOutstandingRewards()
        GameCenter.sync(achievements.unlockedIDs)
        refresh()
    }

    /// True until the player has imported or skipped the web save once.
    var shouldOfferWebImport: Bool {
        !UserDefaults.standard.bool(forKey: "swift_web_import_done")
    }

    func skipWebImport() {
        UserDefaults.standard.set(true, forKey: "swift_web_import_done")
    }

    // MARK: Saved runs
    // A run in progress is saved after every action, so it survives iOS closing
    // the app. Each character's run is kept under its creation time.

    private func runKey(_ index: Int) -> String? {
        guard characters.indices.contains(index) else { return nil }
        return "dd_swift_run_\(Int(characters[index].created))"
    }

    func savedRun(for index: Int) -> Run? {
        guard let key = runKey(index), let s = store.getItem(key), let d = s.data(using: .utf8) else { return nil }
        return Run.decodeSaved(d)
    }

    func saveRun(_ run: Run, for index: Int) {
        guard let key = runKey(index), let d = try? JSONEncoder().encode(run),
              let s = String(data: d, encoding: .utf8) else { return }
        store.setItem(key, s)
    }

    func clearRun(for index: Int) {
        guard let key = runKey(index) else { return }
        store.removeItem(key)
    }

    func deleteCharacter(at index: Int) {
        clearRun(for: index)
        delete(at: index)
    }

    /// A run lost with all lives gone (showDefeat): The Graveyard gets an
    /// entry and the run's gear and special items are kept.
    func recordDeath(_ run: Run, killedBy: String) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let ch = characters.first { $0.name == run.name }
        var journal = ""
        if case .array(let a)? = ch?.extra["journal"], case .object(let o)? = a.first, case .string(let t)? = o["text"] { journal = t }
        roster.addToGraveyard(.object([
            "name": .string(run.name), "cls": .string(run.cls), "race": .string(run.race),
            "level": .number(Double(ch?.persistLevel ?? run.level)),
            "dungeon": .string(run.dungeon), "difficulty": .string(run.difficulty.rawValue),
            "killedBy": .string(killedBy), "topFloor": .number(Double(run.floor)),
            "journal": .string(journal),
            "date": .string("\(c.month ?? 1)/\(c.day ?? 1)/\(c.year ?? 2026)"),
        ]))
        globalInventory.keepOnDeath(from: run)
        checkLegends(run)
    }

    func addToGraveyard(_ entry: JSONValue) { roster.addToGraveyard(entry) }

    /// The player deleted the character: it goes to The Graveyard.
    func buryCharacter(at index: Int) {
        clearRun(for: index)
        roster.bury(at: index)
        refresh()
    }
}

/// Spoken feedback and haptics.
@MainActor
enum Feedback {
    /// Queues a VoiceOver announcement so it doesn't cut off the button's own sound.
    static func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let s = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: s)
    }

    static func hit(heavy: Bool = false) {
        guard AppSettings.haptics else { return }
        UIImpactFeedbackGenerator(style: heavy ? .heavy : .medium).impactOccurred()
    }

    static func success() {
        guard AppSettings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard AppSettings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

/// Player settings kept in UserDefaults.
enum AppSettings {
    private static func flag(_ key: String, _ fallback: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }
    private static func level(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }
    static var haptics: Bool { flag("swift_haptics") }
    static var classTraits: Bool { flag("swift_class_traits") }
    // Same defaults as the web version's audio settings.
    static var musicOn: Bool { flag("swift_music_on") }
    static var effectsOn: Bool { flag("swift_sfx_on") }
    static var ambientOn: Bool { flag("swift_ambient_on") }
    static var musicVolume: Double { level("swift_music_volume", 0.7) }
    static var effectsVolume: Double { level("swift_sfx_volume", 0.8) }
    static var ambientVolume: Double { level("swift_ambient_volume", 0.35) }
    // Accessibility panel
    static var verboseRooms: Bool { flag("swift_verbose_rooms") }
    static var combatAnnouncements: Bool { flag("swift_combat_announcements") }
}
