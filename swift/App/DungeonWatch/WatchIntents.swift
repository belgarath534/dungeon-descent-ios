import AppIntents

/// 12.0: Siri on the Apple Watch. "How's my run in Dungeon Descent", "Use a
/// potion in Dungeon Descent", "Strike the World Boss in Dungeon Descent",
/// "Claim my daily reward in Dungeon Descent". Each asks the iPhone, which
/// keeps the save, and says the answer.
@available(watchOS 9.0, *)
struct WatchRunStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "How's My Run"
    static var description = IntentDescription("Tells you the floor, HP and level of your Endless Descent run.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = WatchStore.shared
        _ = await store.ask(.status)
        guard let r = store.run, r.running else { return .result(dialog: "No Endless Descent run is going.") }
        return .result(dialog: "\(r.charName) is on floor \(r.floor) with \(r.hp) of \(r.maxHp) HP. Level \(r.level), \(r.points) points, \(r.potions) potions left.")
    }
}

@available(watchOS 9.0, *)
struct WatchPotionIntent: AppIntent {
    static var title: LocalizedStringResource = "Use a Potion"
    static var description = IntentDescription("Drinks a potion in your Endless Descent run.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await WatchStore.shared.ask(.potion)
        return .result(dialog: "\(answer.isEmpty ? "Done." : answer)")
    }
}

@available(watchOS 9.0, *)
struct WatchStrikeIntent: AppIntent {
    static var title: LocalizedStringResource = "Strike the World Boss"
    static var description = IntentDescription("Strikes today's World Boss with your first character.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = WatchStore.shared
        _ = await store.ask(.status)
        guard let c = store.characters.first else { return .result(dialog: "Create a character on your iPhone first.") }
        let answer = await store.ask(.strike, index: c.index)
        return .result(dialog: "\(answer.isEmpty ? "Done." : answer)")
    }
}

@available(watchOS 9.0, *)
struct WatchDailyIntent: AppIntent {
    static var title: LocalizedStringResource = "Claim Daily Reward"
    static var description = IntentDescription("Claims today's daily reward and keeps your streak.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await WatchStore.shared.ask(.claimDaily)
        return .result(dialog: "\(answer.isEmpty ? "Done." : answer)")
    }
}

@available(watchOS 9.0, *)
struct WatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WatchRunStatusIntent(), phrases: [
            "How's my run in \(.applicationName)",
            "Check my run in \(.applicationName)",
        ])
        AppShortcut(intent: WatchPotionIntent(), phrases: [
            "Use a potion in \(.applicationName)",
            "Drink a potion in \(.applicationName)",
        ])
        AppShortcut(intent: WatchStrikeIntent(), phrases: [
            "Strike the World Boss in \(.applicationName)",
            "Hit the boss in \(.applicationName)",
        ])
        AppShortcut(intent: WatchDailyIntent(), phrases: [
            "Claim my daily reward in \(.applicationName)",
            "Claim daily in \(.applicationName)",
        ])
    }
}
