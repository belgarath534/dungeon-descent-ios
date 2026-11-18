import Foundation

/// THE DAILY WORLD BOSS: one boss a day (a UTC day, so it's the same boss for
/// everyone everywhere) with 30,000 HP shared by every player. Each player
/// gets 10 strikes a day; their damage for the day is their entry in the
/// online ladder for that day, and the boss's damage taken is everyone's
/// entries added up. If it falls, everyone who struck it collects 750 gold
/// and 2 Soul Fragments, that day or the next.
public enum WorldBoss {
    public static let hp = 30_000
    public static let strikesPerDay = 10
    public static let goldReward = 750
    public static let fragmentReward = 2

    public struct Boss: Equatable, Sendable {
        public let name: String
        public let intro: String
        /// What it says back after each of your strikes.
        public let taunts: [String]
    }

    public static let bosses: [Boss] = [
        Boss(name: "The Bone Colossus", intro: "A mountain of bones rises, older than the dungeon itself.",
             taunts: ["Its ribs grind together.", "Dust pours from its skull.", "It shrugs off a rib and grows another."]),
        Boss(name: "The Drowned King", intro: "Water floods the hall. A crowned corpse stands in it.",
             taunts: ["The water rises to your knees.", "It gurgles a forgotten order.", "Its crown flickers green."]),
        Boss(name: "Mother of Spiders", intro: "The ceiling moves. It is all legs.",
             taunts: ["A thousand eyes turn toward you.", "Webs snap around your feet.", "Something skitters behind you."]),
        Boss(name: "The Ash Wyrm", intro: "The air turns to cinders. A dragon of ash uncoils.",
             taunts: ["Embers rain from its wings.", "It breathes smoke, not fire. Yet.", "Its scales crack and glow."]),
        Boss(name: "The Hollow Bell", intro: "A bell the size of a house rings with no one pulling it.",
             taunts: ["The toll shakes your teeth.", "It rings again. Closer.", "Silence, then one more toll."]),
        Boss(name: "The Weeping Statue", intro: "A stone giant cries real tears. They burn.",
             taunts: ["Stone grinds as it turns.", "A tear hisses on the floor.", "It sobs, and the walls crack."]),
        Boss(name: "The Hunger", intro: "No body, only a mouth in the dark, and it is never full.",
             taunts: ["It swallows the light.", "Teeth, everywhere.", "It chews on nothing, loudly."]),
    ]

    public struct Day: Equatable, Sendable {
        /// "2026-11-18" (UTC).
        public let date: String
        public let boss: Boss
        /// The online ladder this day's damage goes into.
        public var season: String { "worldboss-" + date }
        var damageKey: String { "dd_wb_dmg_" + date }
        var strikesKey: String { "dd_wb_strikes_" + date }
        var claimedKey: String { "dd_wb_claimed_" + date }
    }

    static func dateString(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    public static func day(_ date: Date = Date()) -> Day {
        let n = Int(date.timeIntervalSince1970 / 86400)
        return Day(date: dateString(date), boss: bosses[((n % bosses.count) + bosses.count) % bosses.count])
    }

    public static func yesterday(_ date: Date = Date()) -> Day { day(date.addingTimeInterval(-86400)) }

    /// Hours until the next boss (midnight UTC), rounded up.
    public static func hoursLeft(_ date: Date = Date()) -> Int {
        let into = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400)
        return max(1, Int(((86400 - into) / 3600).rounded(.up)))
    }

    // MARK: Your strikes

    public static func myDamage(_ day: Day, store: GameStore) -> Int { Int(store.getItem(day.damageKey) ?? "") ?? 0 }
    public static func strikesUsed(_ day: Day, store: GameStore) -> Int { Int(store.getItem(day.strikesKey) ?? "") ?? 0 }
    public static func strikesLeft(_ day: Day, store: GameStore) -> Int { max(0, strikesPerDay - strikesUsed(day, store: store)) }

    public struct Strike: Equatable, Sendable {
        public let damage: Int
        public let crit: Bool
        public let taunt: String
        /// Your damage today, after this strike.
        public let myTotal: Int
    }

    /// One strike: 80 plus 12 a level, give or take a fifth, and a 15%
    /// chance of a critical for double. Nil when today's strikes are spent.
    public static func strike<D: Dice>(_ day: Day, level: Int, store: GameStore, dice: inout D) -> Strike? {
        let used = strikesUsed(day, store: store)
        guard used < strikesPerDay else { return nil }
        let base = 80 + 12 * max(1, level)
        var dmg = dice.roll((base * 4 / 5)...(base * 6 / 5))
        let crit = dice.chance(0.15)
        if crit { dmg *= 2 }
        let total = myDamage(day, store: store) + dmg
        store.setItem(day.damageKey, String(total))
        store.setItem(day.strikesKey, String(used + 1))
        let taunt = day.boss.taunts[dice.roll(0...(day.boss.taunts.count - 1))]
        return Strike(damage: dmg, crit: crit, taunt: taunt, myTotal: total)
    }

    // MARK: The shared HP and the reward

    /// What's left of the boss after everyone's damage.
    public static func remaining(totalDamage: Int) -> Int { max(0, hp - totalDamage) }

    /// The reward for a boss that fell, once, if you struck it. Pays the gold
    /// and the fragments; nil when there's nothing to collect.
    public static func claim(_ day: Day, totalDamage: Int, store: GameStore, wallet: Wallet) -> (gold: Int, fragments: Int)? {
        guard totalDamage >= hp, myDamage(day, store: store) > 0, store.getItem(day.claimedKey) == nil else { return nil }
        store.setItem(day.claimedKey, "1")
        wallet.addGold(goldReward)
        store.setItem("dd_soul_fragments", String(CustomSpirits.fragments(store) + fragmentReward))
        return (goldReward, fragmentReward)
    }

    /// "The Hunger: 12,400 of 30,000 HP left, 8 hours until the next boss."
    public static func status(_ day: Day, totalDamage: Int?, now: Date = Date()) -> String {
        let h = hoursLeft(now)
        let time = "\(h) hour\(h == 1 ? "" : "s") until the next boss."
        guard let totalDamage else { return "\(day.boss.name). The shared HP can't be reached right now. \(time)" }
        let left = remaining(totalDamage: totalDamage)
        if left == 0 { return "\(day.boss.name) has fallen today. \(time)" }
        return "\(day.boss.name): \(left.formatted()) of \(hp.formatted()) HP left. \(time)"
    }
}
