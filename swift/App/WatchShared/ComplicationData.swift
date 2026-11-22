import Foundation

/// 12.0: what the watch app saves for its complications in the App Group
/// (the complications can't talk to the iPhone themselves): the Endless
/// Descent run, the daily streak and the Battle Pass tier.
struct ComplicationData: Codable, Equatable {
    static let group = "group.com.dungeon.descent"
    static let key = "dd_complication"

    var charName: String?
    var running = false
    var floor = 0
    var hp = 0
    var maxHp = 0
    var bestFloor = 0
    var streak = 0
    /// The local day ("2026-11-19") today's reward was claimed, if it was.
    var claimedDay: String?
    var passTier: Int?
    var passTiers = 50
    var savedAt: Double = 0

    static func today(_ now: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }

    /// Whether today's reward is still waiting.
    func dailyReady(_ now: Date = Date()) -> Bool { claimedDay != Self.today(now) }

    static func load() -> ComplicationData? {
        guard let d = UserDefaults(suiteName: group)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ComplicationData.self, from: d)
    }

    func save() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(d, forKey: Self.key)
    }
}
