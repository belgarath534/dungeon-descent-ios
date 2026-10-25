import SwiftUI
import UIKit
import DungeonCore

/// App-wide state: the save file, the wallet and the character list.
@MainActor
final class GameModel: ObservableObject {
    let store: GameStore
    let wallet: Wallet
    private let roster: CharacterRoster

    @Published private(set) var characters: [PlayerCharacter] = []
    @Published private(set) var gold = 0
    @Published private(set) var diamonds = 0

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = FileStore(url: dir.appendingPathComponent("dd_store.json"))
        wallet = Wallet(store: store)
        roster = CharacterRoster(store: store)
        wallet.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        characters = roster.characters
        gold = wallet.gold
        diamonds = wallet.diamonds
    }

    var isRosterFull: Bool { roster.isFull }

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
}

/// Spoken feedback and haptics.
@MainActor
enum Feedback {
    /// Queues a VoiceOver announcement so it doesn't cut off the button's own sound.
    static func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
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
    static var haptics: Bool { UserDefaults.standard.object(forKey: "swift_haptics") as? Bool ?? true }
    static var classTraits: Bool { UserDefaults.standard.object(forKey: "swift_class_traits") as? Bool ?? true }
}
