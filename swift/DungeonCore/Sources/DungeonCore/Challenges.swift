import Foundation

/// CHALLENGES: The Gauntlet (six dungeons back to back on one life, HP
/// carried over) and the Daily Dungeon (one dungeon a day with two
/// modifiers, the same for every player).
public enum Challenges {
    /// GAUNTLET_DUNGEONS. (The web version named the last one "Whispering
    /// Forest", which isn't a dungeon, so the Gauntlet broke at the end.)
    public static let gauntlet = ["Crypt of Malachar", "The Ashbound Wastes", "Frosthold Abyss",
                                  "The Sunken Archives", "The Hollow", "The Whispering Forest"]

    public struct Modifier: Sendable, Equatable {
        public let id, name, desc: String
    }

    /// DAILY_MODIFIERS_POOL
    public static let modifiers: [Modifier] = [
        Modifier(id: "double-hp", name: "Iron Flesh", desc: "All enemies have double HP."),
        Modifier(id: "triple-gold", name: "Gold Rush", desc: "Enemies drop triple gold."),
        Modifier(id: "no-potions", name: "Dry Run", desc: "Potions cannot be used."),
        Modifier(id: "fast-enemies", name: "Frenzied", desc: "Enemies deal 25% more damage."),
        Modifier(id: "early-boss", name: "Boss Summoned", desc: "The boss appears on floor 7 instead of 10."),
        Modifier(id: "double-xp", name: "Seasoned Ground", desc: "Double XP from all kills."),
        Modifier(id: "no-shop", name: "Stripped", desc: "The shop does not appear."),
        Modifier(id: "lucky", name: "Fortune Favors", desc: "All gold drops increased by 50%."),
    ]

    public static func modifier(_ id: String) -> Modifier? { modifiers.first { $0.id == id } }

    /// _getDailyDungeonSeed: YYYYMMDD in local time.
    public static func seed(_ date: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 2026) * 10000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    /// _seededRandom: the same sine trick as the web version, so Swift and web
    /// players get the same Daily Dungeon.
    static func seeded(_ s: Int) -> Double {
        let x = sin(Double(s)) * 10000
        return x - x.rounded(.down)
    }

    public struct Daily: Sendable, Equatable {
        public let dungeon: String
        public let mods: [Modifier]
        public let key: String
    }

    /// _getDailySetup
    public static func daily(_ date: Date = Date()) -> Daily {
        let s = seed(date)
        let d = Int(seeded(s) * Double(gauntlet.count))
        let m1 = Int(seeded(s + 1) * Double(modifiers.count))
        var m2 = Int(seeded(s + 2) * Double(modifiers.count))
        if m2 == m1 { m2 = (m2 + 1) % modifiers.count }
        return Daily(dungeon: gauntlet[min(d, gauntlet.count - 1)], mods: [modifiers[m1], modifiers[m2]], key: "dd_daily_\(s)")
    }

    /// Today's best time, once cleared.
    public static func todaysBest(_ store: GameStore, date: Date = Date()) -> String? { store.getItem(daily(date).key) }

    // MARK: In a run

    public static func has(_ run: Run, _ id: String) -> Bool { run.dailyMods.contains(id) }

    /// The boss floor: 7 under Boss Summoned, otherwise 10.
    public static func bossFloor(_ run: Run) -> Int { has(run, "early-boss") ? 7 : 10 }

    /// Iron Flesh and Frenzied on a freshly spawned enemy.
    static func shape(_ e: inout Enemy, _ run: Run) {
        if has(run, "double-hp") {
            e.hp *= 2
            e.maxHp *= 2
            e.phase1Hp *= 2
            e.phase2Hp *= 2
        }
        if has(run, "fast-enemies") {
            let lo = jsRound(Double(e.atk.lowerBound) * 1.25), hi = jsRound(Double(e.atk.upperBound) * 1.25)
            e.atk = lo...max(lo, hi)
        }
    }

    /// Gold Rush and Fortune Favors on a kill's gold.
    public static func gold(_ g: Int, _ run: Run) -> Int {
        var n = g
        if has(run, "triple-gold") { n *= 3 }
        if has(run, "lucky") { n = jsRound(Double(n) * 1.5) }
        return n
    }

    /// The time shown for a cleared Daily Dungeon ("4m 07s").
    public static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return "\(s / 60)m \(String(format: "%02d", s % 60))s"
    }
}
