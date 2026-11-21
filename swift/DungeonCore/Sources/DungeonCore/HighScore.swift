import Foundation

/// The lifetime score ("dd_score": {total, breakdown}) and its ranks
/// (HIGH SCORE SYSTEM).
public struct HighScore: Sendable {
    public struct Rank: Sendable {
        public let min: Int
        public let label: String
        public let color: UInt32
    }

    public static let ranks: [Rank] = [
        Rank(min: 0, label: "INITIATE", color: 0x888888),
        Rank(min: 500, label: "ADVENTURER", color: 0xa0b0c0),
        Rank(min: 2000, label: "VETERAN", color: 0x70a0d0),
        Rank(min: 5000, label: "CHAMPION", color: 0xc0a030),
        Rank(min: 10000, label: "LEGEND", color: 0xc9a227),
        Rank(min: 25000, label: "DUNGEON MASTER", color: 0xe0c060),
        Rank(min: 50000, label: "THE UNKILLABLE", color: 0xf0d080),
        Rank(min: 100000, label: "DDDI CERTIFIED", color: 0xfff8dc),
    ]

    public struct Category: Sendable {
        public let key: String
        public let label: String
        public let icon: String
        init(_ key: String, _ label: String, _ icon: String) { self.key = key; self.label = label; self.icon = icon }
    }

    /// The categories in the order the screen lists them.
    public static let categories: [Category] = [
        Category("enemy_kills", "Enemy Kills", "⚔️"),
        Category("boss_kills", "Boss Kills", "👑"),
        Category("elite_kills", "Elite Kills", "★"),
        Category("dungeon_clears", "Dungeon Completions", "🏰"),
        Category("achievements", "Achievements Earned", "✨"),
        Category("daily_quests", "Daily Quests Completed", "☀️"),
        Category("gold_earned", "Gold Collected", "🪙"),
        Category("floors_reached", "Floors Explored", "🗺️"),
        Category("boss_rush", "Boss Rush Clears", "⚡"),
    ]

    public var total = 0
    public var breakdown: [String: Int] = [:]

    public static func load(_ store: GameStore) -> HighScore {
        var s = HighScore()
        guard let raw = store.getItem("dd_score"), let d = raw.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) else { return s }
        if case .number(let n)? = v["total"] { s.total = Int(n) }
        if case .object(let o)? = v["breakdown"] {
            for (k, val) in o { if case .number(let n) = val { s.breakdown[k] = Int(n) } }
        }
        return s
    }

    /// addScore
    public static func add(_ category: String, _ points: Int, store: GameStore) {
        var s = load(store)
        s.total += points
        s.breakdown[category, default: 0] += points
        let obj: [String: JSONValue] = [
            "total": .number(Double(s.total)),
            "breakdown": .object(s.breakdown.mapValues { .number(Double($0)) }),
        ]
        if let d = try? JSONEncoder().encode(obj), let str = String(data: d, encoding: .utf8) {
            store.setItem("dd_score", str)
        }
    }

    /// getScoreRank
    public static func rank(for total: Int) -> Rank {
        ranks.last { total >= $0.min } ?? ranks[0]
    }
}
