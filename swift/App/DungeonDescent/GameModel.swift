import SwiftUI
import UIKit
import DungeonCore

/// App-wide state: the save file, the wallet and the character list.
@MainActor
final class GameModel: ObservableObject {
    /// One for the app's lifetime, so the Apple Watch can reach it even when
    /// it wakes the app in the background with no screen showing.
    static let shared = GameModel()
    /// Endless Descent, kept for the app's lifetime so a run outlives its screen.
    lazy var afk = AFKModel(game: self)
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
        achievements.onUnlock = { [store] list in
            HighScore.add("achievements", 250 * list.count, store: store)
            GameModel.announce(list)
        }
        // The Battle Pass hears everything the achievements do.
        achievements.onEvent = { [weak self] e in
            switch e {
            case .enemyKilled(let enemy, _): self?.pass(.kill(elite: enemy.isElite, boss: enemy.isBoss))
            case .floorReached: self?.pass(.floor)
            case .runWon: self?.pass(.dungeonCleared)
            case .dailyQuestCompleted: self?.pass(.dailyQuest)
            default: break
            }
        }
        achievements.payOutstandingRewards()
        refresh()
    }

    /// THE BATTLE PASS (BattlePass.swift): Pass XP for something that
    /// happened, with its chime and words for a finished quest or new tier.
    func pass(_ e: BattlePass.Event, times: Int = 1) {
        var out = BattlePass.Outcome()
        for _ in 0..<max(0, min(times, 500)) {
            let o = BattlePass.record(e, store: store)
            out.lines += o.lines
            out.newTier = out.newTier || o.newTier
        }
        guard !out.lines.isEmpty else { return }
        Sound.sfx(out.newTier ? "sfx-pass-tier" : "sfx-pass-quest")
        Feedback.success()
        Feedback.announce(out.lines.joined(separator: " "), after: 0.6)
        if out.newTier { refresh() }
    }

    /// Only what changed is set again: every set redraws every screen.
    func refresh() {
        let c = roster.characters
        if characters != c { characters = c }
        if gold != wallet.gold { gold = wallet.gold }
        if diamonds != wallet.diamonds { diamonds = wallet.diamonds }
    }

    var isRosterFull: Bool { roster.isFull }

    /// Writes the save to disk right away (when the app leaves the foreground).
    func saveNow() { fileStore.flushNow() }
    /// The whole save, for the iCloud backup.
    func snapshot() -> [String: String] { fileStore.snapshot() }

    /// Achievement unlocked: a sound by tier, a spoken line and Game Center.
    static func announce(_ list: [Achievement]) {
        // Same tiers as the web version's playAchievementUnlockSound: a few special
        // achievements, then by gold reward.
        let special: Set<String> = ["ach-void-reaper", "ach-witness", "ach-dddi-boss", "ach-bossrush",
                                    "ach-ngplus3", "ach-all-stories", "ach-trilogy", "ach-kills-1000", "ach-abyssal-boss"]
        func rank(_ a: Achievement) -> Int { special.contains(a.id) ? 3 : a.gold >= 300 ? 2 : a.gold >= 200 ? 1 : 0 }
        guard let best = list.max(by: { rank($0) < rank($1) }) else { return }
        Sound.sfx([AchievementSound.current, "sfx-ach-silver", "sfx-ach-gold", "sfx-ach-special"][rank(best)])
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
    var familiarBadge: String { Familiar.load(store).menuBadge }

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
    func importWebSave(_ data: [String: String], keepSwiftRuns: Bool = false) {
        store.setItems(data.filter { $0.key.hasPrefix("dd_") && (keepSwiftRuns || !$0.key.hasPrefix("dd_swift_")) })
        roster = CharacterRoster(store: store)
        UserDefaults.standard.set(true, forKey: "swift_web_import_done")
        achievements.reload()
        achievements.payOutstandingRewards()
        GameCenter.sync(achievements.unlockedIDs)
        refresh()
    }

    /// confirmResetGame: every dd_ key and every setting, gone. (The web save
    /// isn't offered again, so it can't bring the old progress back.)
    func resetEverything() {
        for key in fileStore.snapshot().keys where key.hasPrefix("dd_") { store.removeItem(key) }
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("swift_") && key != "swift_web_import_done" {
            defaults.removeObject(forKey: key)
        }
        roster = CharacterRoster(store: store)
        achievements.reload()
        refresh()
        saveNow()
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
        postDeath(DeathNotice(name: run.name, cls: run.cls, dungeon: run.dungeon, killedBy: killedBy,
                              floor: run.floor, kills: run.kills, gold: run.gold))
    }

    func addToGraveyard(_ entry: JSONValue) { roster.addToGraveyard(entry) }

    /// A death for the worldwide Obituary (postDeathToObituary).
    struct DeathNotice {
        let name, cls, dungeon, killedBy: String
        let floor, kills, gold: Int
    }

    /// Set by the cloud account, which posts each death to the Obituary.
    var onDeath: ((DeathNotice) -> Void)?

    func postDeath(_ d: DeathNotice) { onDeath?(d) }

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
    /// `latest`: for modes that play themselves (Spire Auto Mode), lines not
    /// yet read are dropped so VoiceOver reads what is happening now.
    static func announce(_ english: String, after delay: Double = 0, latest: Bool = false) {
        // The Lewis Voice Pack: Lewis reads it instead of VoiceOver's voice.
        if VoicePack.shared.speaking, !english.trimmingCharacters(in: .whitespaces).isEmpty {
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { LiveVoice.shared.speak(english, latest: latest) }
            } else {
                LiveVoice.shared.speak(english, latest: latest)
            }
            return
        }
        guard UIAccessibility.isVoiceOverRunning, !english.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let text = Language.t(english)
        guard delay > 0 else {
            Announcer.shared.say(text, latest: latest)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Announcer.shared.say(text, latest: latest) }
    }

    static func hit(heavy: Bool = false) {
        guard AppSettings.haptics else { return }
        #if !os(visionOS)
        UIImpactFeedbackGenerator(style: heavy ? .heavy : .medium).impactOccurred()
        #endif
    }

    static func tap() {
        guard AppSettings.haptics else { return }
        #if !os(visionOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        guard AppSettings.haptics else { return }
        #if !os(visionOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        guard AppSettings.haptics else { return }
        #if !os(visionOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
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
    static var shakeAttack: Bool { flag("swift_shake", false) }
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
    /// Combat read as "Hit 12. Took 5. HP 40 of 90. Skeleton 22." instead of sentences.
    static var briefCombat: Bool { flag("swift_brief_combat", false) }
    /// Short sounds for low HP and an elite appearing, heard before VoiceOver speaks.
    static var earcons: Bool { flag("swift_earcons") }
}

/// Says VoiceOver lines one at a time and makes sure each is heard. iOS drops
/// the rest of an announcement when VoiceOver starts reading something else
/// (the new room's buttons after a move, say), and never tries again, so a
/// line that was cut off is said again once VoiceOver is free.
@MainActor
final class Announcer {
    static let shared = Announcer()
    private var queue: [String] = []
    private var current: String?
    private var tries = 0
    private var watchdog: DispatchWorkItem?

    private init() {
        NotificationCenter.default.addObserver(forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main) { note in
            let text = note.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String
            let ok = (note.userInfo?[UIAccessibility.announcementWasSuccessfulUserInfoKey] as? NSNumber)?.boolValue ?? true
            Task { @MainActor in Announcer.shared.finished(text, ok: ok) }
        }
    }

    /// Lines waiting their turn, at most. Anything older is dropped, so
    /// VoiceOver can never fall far behind the game.
    static let maxWaiting = 4

    func say(_ text: String, latest: Bool = false) {
        // The same line twice in a row would only repeat itself.
        if text == current || queue.last == text { return }
        if latest { queue.removeAll() }
        queue.append(text)
        if queue.count > Self.maxWaiting { queue.removeFirst(queue.count - Self.maxWaiting) }
        if current == nil { next() }
    }

    private func next() {
        watchdog?.cancel()
        guard !queue.isEmpty, UIAccessibility.isVoiceOverRunning else { current = nil; queue.removeAll(); return }
        let text = queue.removeFirst()
        current = text
        tries = 0
        post(text)
    }

    private func post(_ text: String) {
        UIAccessibility.post(notification: .announcement,
                             argument: NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: true]))
        // If iOS never reports back, move on after about as long as it takes to say.
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.current == text else { return }
            self.next()
        }
        watchdog = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3 + Double(text.count) / 12, execute: w)
    }

    private func finished(_ text: String?, ok: Bool) {
        guard let cur = current, text == nil || text == cur else { return }
        if !ok && tries < 2 {
            // Cut off: say it again once VoiceOver has finished the other thing.
            tries += 1
            watchdog?.cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.current == cur else { return }
                self.post(cur)
            }
            return
        }
        next()
    }
}
