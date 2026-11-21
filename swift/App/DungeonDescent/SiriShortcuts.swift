import AppIntents
import Foundation
import DungeonCore

// Siri and the Shortcuts app: "Hey Siri, start Endless Descent in Dungeon
// Descent", "How's my run in Dungeon Descent", "Use a potion in Dungeon
// Descent". They show up in Shortcuts on their own, no setup needed.

/// Opens the game on Endless Descent.
struct StartEndlessDescentIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Endless Descent"
    static var description = IntentDescription("Opens Dungeon Descent on Endless Descent, where your run keeps going on its own.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .openEndlessDescent, object: nil)
        return .result()
    }
}

/// Reads out how the Endless Descent run is going, without opening the game.
struct RunStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "How's My Run"
    static var description = IntentDescription("Tells you the floor, HP, level and points of your Endless Descent run.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let afk = GameModel.shared.afk
        afk.catchUp()
        guard let r = afk.run, r.running else {
            return .result(dialog: "No Endless Descent run is going. Say: start Endless Descent in Dungeon Descent.")
        }
        return .result(dialog: "\(r.charName) is on floor \(r.floor) with \(r.hp) of \(r.maxHp) HP. Level \(r.level), \(r.points) points, \(r.potions) potion\(r.potions == 1 ? "" : "s") left.")
    }
}

/// Drinks a potion in the Endless Descent run.
struct UsePotionIntent: AppIntent {
    static var title: LocalizedStringResource = "Use a Potion"
    static var description = IntentDescription("Drinks a potion in your Endless Descent run.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let afk = GameModel.shared.afk
        afk.catchUp()
        guard afk.run?.running == true else { return .result(dialog: "No Endless Descent run is going.") }
        let msg = afk.usePotion()
        return .result(dialog: "\(msg)")
    }
}

struct DungeonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartEndlessDescentIntent(), phrases: [
            "Start Endless Descent in \(.applicationName)",
            "Start an AFK run in \(.applicationName)",
        ], shortTitle: "Start Endless Descent", systemImageName: "arrow.down.circle")
        AppShortcut(intent: RunStatusIntent(), phrases: [
            "How's my run in \(.applicationName)",
            "How is my \(.applicationName) run",
            "Check my run in \(.applicationName)",
        ], shortTitle: "How's My Run", systemImageName: "heart.text.square")
        AppShortcut(intent: UsePotionIntent(), phrases: [
            "Use a potion in \(.applicationName)",
            "Drink a potion in \(.applicationName)",
        ], shortTitle: "Use a Potion", systemImageName: "cross.vial")
    }
}

extension Notification.Name {
    static let openEndlessDescent = Notification.Name("DDOpenEndlessDescent")
}
