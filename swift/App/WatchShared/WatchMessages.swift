import Foundation

/// What the iPhone and the Apple Watch say to each other. The phone keeps the
/// save and runs Endless Descent; the watch asks it for the state and sends
/// commands. Everything goes over WatchConnectivity as JSON under "payload".
enum WatchLink {
    static let commandKey = "cmd"
    static let indexKey = "index"
    static let payloadKey = "payload"
    /// A tap on your wrist from the phone: danger in a run, or your co-op turn.
    static let alertKey = "alert"
    static let alertTextKey = "alertText"

    enum Command: String {
        case status, start, potion, end
        /// 12.0: a World Boss strike with the character at `index`.
        case strike
        /// 12.0: claim today's daily reward.
        case claimDaily
    }

    /// What kind of tap an alert is.
    enum Alert: String {
        case lowHp, elite, hunter, coopTurn, reward
    }

    /// Today's World Boss.
    struct Boss: Codable, Equatable {
        var name: String
        var strikesLeft: Int
        var strikesPerDay: Int
        var myDamage: Int
        /// Shared HP left, when the phone could check.
        var hpLeft: Int?
        var maxHp: Int
        var hoursLeft: Int
    }

    struct Quest: Codable, Equatable {
        var text: String
        var have: Int
        var target: Int
        var done: Bool
    }

    /// The Battle Pass season and this week's quests.
    struct Pass: Codable, Equatable {
        var season: Int
        var tier: Int
        var tiers: Int
        var xpIntoTier: Int
        var xpPerTier: Int
        var daysLeft: Int
        var next: String
        var quests: [Quest]
    }

    /// The daily reward.
    struct Daily: Codable, Equatable {
        var claimed: Bool
        var streak: Int
        var next: String
    }

    struct Character: Codable, Identifiable, Equatable {
        var index: Int
        var name: String
        var cls: String
        var level: Int
        var dungeon: String
        var id: Int { index }
    }

    struct Run: Codable, Equatable {
        var charName: String
        var cls: String
        var floor: Int
        var hp: Int
        var maxHp: Int
        var level: Int
        var points: Int
        var potions: Int
        var enemiesDefeated: Int
        var bossesDefeated: Int
        var running: Bool
        /// When the next fight happens (seconds since 1970).
        var nextFightAt: Double
        var startedAt: Double
        /// The newest log lines, newest first.
        var log: [String]
    }

    struct Snapshot: Codable, Equatable {
        var characters: [Character]
        /// The run going now, or the one that just ended (running == false).
        var run: Run?
        var totalPoints: Int
        var bestFloor: Int
        /// The answer to the last command ("Potion used …", "Pick your skills on your iPhone …").
        var message: String?
        var sentAt: Double
        // 12.0 (missing from an older phone app: nil)
        var boss: Boss?
        var pass: Pass?
        var daily: Daily?
    }

    static func encode(_ s: Snapshot) -> [String: Any] {
        guard let d = try? JSONEncoder().encode(s) else { return [:] }
        return [payloadKey: d]
    }

    static func decode(_ dict: [String: Any]) -> Snapshot? {
        guard let d = dict[payloadKey] as? Data else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: d)
    }
}
