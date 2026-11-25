import Foundation

/// 12.2 GUILDS: up to 20 players under one name, with their own chat and a
/// Guild Boss each week. The guild, its members and its chat live online
/// (GuildStore in the app); this is the part that doesn't need a network:
/// names, the week, the boss, your strikes and the reward.
///
/// The Guild Boss: one boss a week (a UTC week starting Monday, the same for
/// every guild), its HP grows with the guild (10,000 plus 6,000 a member).
/// Every member gets 5 strikes a day; the guild's damage is everyone's
/// strikes added up. If it falls before the week ends, everyone who struck it
/// collects 1,500 gold and 5 Soul Fragments, that week or the next.
public enum Guilds {
    public static let maxMembers = 20
    public static let strikesPerDay = 5
    public static let goldReward = 1_500
    public static let fragmentReward = 5

    // MARK: Names

    /// Letters, numbers, spaces, apostrophes and hyphens; 3 to 24 characters.
    /// Nil when it's fine, otherwise what to read out.
    public static func nameProblem(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        if name.count < 3 { return "A guild name needs at least 3 characters." }
        if name.count > 24 { return "A guild name can be at most 24 characters." }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 '-")
        if name.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Use only letters, numbers, spaces, apostrophes and hyphens in a guild name."
        }
        if name.contains("  ") { return "Use only one space between words." }
        if CommunityEnemies.hasBadWord(name) { return "That guild name is not allowed. Please choose another." }
        return nil
    }

    public static func descProblem(_ raw: String) -> String? {
        if raw.count > 120 { return "The description can be at most 120 characters." }
        if CommunityEnemies.hasBadWord(raw) { return "The description contains inappropriate content." }
        return nil
    }

    /// The name everyone's checked against, so "Iron Wolves" and "iron wolves" are the same guild.
    public static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }

    // MARK: The week

    public struct Boss: Equatable, Sendable {
        public let name: String
        public let intro: String
        public let taunts: [String]
    }

    public static let bosses: [Boss] = [
        Boss(name: "The Siege Engine", intro: "A war machine with no crew rolls out of the dark. It was built to break guilds.",
             taunts: ["Its gears shriek.", "A plank tears loose and it keeps coming.", "Chains rattle somewhere inside it."]),
        Boss(name: "The Twin Wardens", intro: "Two guards who never sleep, sharing one shield and one grudge.",
             taunts: ["One guards while the other swings.", "They trade places. You barely see it.", "The shield rings like a bell."]),
        Boss(name: "The Swarm Queen", intro: "The walls hum. Every crack in the stone is a door for her children.",
             taunts: ["The humming gets louder.", "Wings, everywhere.", "Something crawls up your sleeve."]),
        Boss(name: "The Iron Abbot", intro: "A monk in rusted armour, praying to something that answers.",
             taunts: ["He mutters a prayer. The room goes cold.", "His censer swings, trailing black smoke.", "Iron creaks as he kneels and rises."]),
        Boss(name: "The Tide Beneath", intro: "The floor is wet. Then it is water. Then it is looking at you.",
             taunts: ["A wave crashes over your feet.", "The water pulls back, gathering.", "Salt stings your eyes."]),
        Boss(name: "The Ember Choir", intro: "A hundred burning voices, singing one note that never ends.",
             taunts: ["The note gets higher.", "Sparks fall like snow.", "One voice drops out. Two more join."]),
    ]

    public struct Week: Equatable, Sendable {
        /// "2026-W48": the year and the week (Monday to Sunday, UTC).
        public let key: String
        public let boss: Boss
        var strikesKeyPrefix: String { "dd_guild_strikes_" }
        var damageKey: String { "dd_guild_dmg_" + key }
        var claimedKey: String { "dd_guild_claimed_" + key }
    }

    static var utc: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    public static func week(_ date: Date = Date()) -> Week {
        let c = utc.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let y = c.yearForWeekOfYear ?? 2026, w = c.weekOfYear ?? 1
        let n = Int(floor(date.timeIntervalSince1970 / 86400 + 3) / 7) // whole weeks since a Monday
        return Week(key: String(format: "%04d-W%02d", y, w), boss: bosses[((n % bosses.count) + bosses.count) % bosses.count])
    }

    public static func lastWeek(_ date: Date = Date()) -> Week { week(date.addingTimeInterval(-7 * 86400)) }

    /// Days until the next boss (Monday, midnight UTC), rounded up.
    public static func daysLeft(_ date: Date = Date()) -> Int {
        let into = (date.timeIntervalSince1970 / 86400 + 3).truncatingRemainder(dividingBy: 7)
        return max(1, Int((7 - into).rounded(.up)))
    }

    /// The boss's HP for a guild this size.
    public static func hp(members: Int) -> Int { 10_000 + 6_000 * min(maxMembers, max(1, members)) }

    public static func remaining(totalDamage: Int, members: Int) -> Int { max(0, hp(members: members) - totalDamage) }

    // MARK: Your strikes

    static func today(_ date: Date) -> String { WorldBoss.dateString(date) }

    public static func myDamage(_ week: Week, store: GameStore) -> Int { Int(store.getItem(week.damageKey) ?? "") ?? 0 }

    public static func strikesUsed(store: GameStore, date: Date = Date()) -> Int {
        Int(store.getItem("dd_guild_strikes_" + today(date)) ?? "") ?? 0
    }

    public static func strikesLeft(store: GameStore, date: Date = Date()) -> Int {
        max(0, strikesPerDay - strikesUsed(store: store, date: date))
    }

    public struct Strike: Equatable, Sendable {
        public let damage: Int
        public let crit: Bool
        public let taunt: String
        /// Your damage this week, after this strike.
        public let myTotal: Int
    }

    /// One strike: 100 plus 15 a level, give or take a fifth, and a 15%
    /// chance of a critical for double. Never more than 5,000 (the online
    /// rules refuse bigger steps). Nil when today's strikes are spent.
    public static func strike<D: Dice>(_ week: Week, level: Int, store: GameStore, date: Date = Date(), dice: inout D) -> Strike? {
        let used = strikesUsed(store: store, date: date)
        guard used < strikesPerDay else { return nil }
        let base = 100 + 15 * max(1, level)
        var dmg = dice.roll((base * 4 / 5)...(base * 6 / 5))
        let crit = dice.chance(0.15)
        if crit { dmg *= 2 }
        dmg = min(5_000, dmg)
        let total = myDamage(week, store: store) + dmg
        store.setItem(week.damageKey, String(total))
        store.setItem("dd_guild_strikes_" + today(date), String(used + 1))
        let taunt = week.boss.taunts[dice.roll(0...(week.boss.taunts.count - 1))]
        return Strike(damage: dmg, crit: crit, taunt: taunt, myTotal: total)
    }

    /// The reward for a Guild Boss that fell, once, if you struck it.
    public static func claim(_ week: Week, totalDamage: Int, members: Int, store: GameStore, wallet: Wallet) -> (gold: Int, fragments: Int)? {
        guard totalDamage >= hp(members: members), myDamage(week, store: store) > 0,
              store.getItem(week.claimedKey) == nil else { return nil }
        store.setItem(week.claimedKey, "1")
        wallet.addGold(goldReward)
        store.setItem("dd_soul_fragments", String(CustomSpirits.fragments(store) + fragmentReward))
        return (goldReward, fragmentReward)
    }

    /// "The Siege Engine: 40,000 of 70,000 HP left. 3 days until the next boss."
    public static func status(_ week: Week, totalDamage: Int?, members: Int, now: Date = Date()) -> String {
        let d = daysLeft(now)
        let time = "\(d) day\(d == 1 ? "" : "s") until the next boss."
        guard let totalDamage else { return "\(week.boss.name). The guild's damage can't be reached right now. \(time)" }
        let left = remaining(totalDamage: totalDamage, members: members)
        if left == 0 { return "\(week.boss.name) has fallen this week. \(time)" }
        return "\(week.boss.name): \(left.formatted()) of \(hp(members: members).formatted()) HP left. \(time)"
    }
}
