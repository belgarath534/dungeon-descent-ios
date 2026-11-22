import Foundation

/// PRESTIGE (12.0): a character at their level cap (10, or 25 in Legacy)
/// can start over at level 1 for a permanent star, up to 10. Each star is
/// +5% max HP, +5% attack and +10% gold in every run, and prestiging pays
/// 1,000 gold a star and a Mystery Coin. Stored on the character as
/// "prestige", so the web version reads the same stars.
public enum Prestige {
    public static let maxStars = 10
    public static let hpPerStar = 0.05
    public static let atkPerStar = 0.05
    public static let goldPerStar = 0.10

    public static func stars(_ ch: PlayerCharacter) -> Int {
        if case .number(let n)? = ch.extra["prestige"] { return min(maxStars, max(0, Int(n))) }
        return 0
    }

    /// "Kai ★3", or just the name.
    public static func label(_ ch: PlayerCharacter) -> String {
        let s = stars(ch)
        return s > 0 ? "\(ch.name) ★\(s)" : ch.name
    }

    /// The level a prestige needs: 10, or 25 in Legacy. It stayed 25 when
    /// Legacy's cap went up to 50 in 12.0.2.
    public static func requiredLevel(_ ch: PlayerCharacter) -> Int { min(ch.levelCap, 25) }

    /// The reason a character can't prestige yet, or nil when they can.
    public static func blocker(_ ch: PlayerCharacter) -> String? {
        if stars(ch) >= maxStars { return "\(ch.name) already has every star there is." }
        let level = ch.persistLevel ?? 1
        if level < requiredLevel(ch) {
            return "Reach level \(requiredLevel(ch)) to prestige. \(ch.name) is level \(level)."
        }
        return nil
    }

    public struct Result: Equatable, Sendable {
        public let stars: Int
        public let gold: Int
        public let coins: Int
        public let spoken: String
    }

    /// Back to level 1 (level, XP, skills and the Legacy tier) for a star.
    public static func prestige(_ ch: inout PlayerCharacter, wallet: Wallet, store: GameStore) -> Result? {
        guard blocker(ch) == nil else { return nil }
        let s = stars(ch) + 1
        ch.extra["prestige"] = .number(Double(s))
        ch.persistLevel = 1
        ch.extra["persistXp"] = .number(0)
        ch.extra["persistSkills"] = .array([])
        if ch.dungeonTier != nil { ch.dungeonTier = 1 }
        let gold = 1000 * s
        wallet.addGold(gold)
        Spire.addCoins(1, store: store)
        let pct = { (x: Double) in Int((x * Double(s) * 100).rounded()) }
        return Result(stars: s, gold: gold, coins: 1,
                      spoken: "\(ch.name) is reborn with \(s) star\(s == 1 ? "" : "s"). Back to level 1, now with \(pct(hpPerStar))% more health, \(pct(atkPerStar))% more attack and \(pct(goldPerStar))% more gold in every run. You earn \(gold) gold and a Mystery Coin.")
    }

    /// initDungeon: the stars' bonuses for this run.
    public static func start(_ r: inout Run, _ ch: PlayerCharacter) -> [String] {
        let s = stars(ch)
        guard s > 0 else { return [] }
        r.prestige = s
        let hp = 1 + hpPerStar * Double(s), atk = 1 + atkPerStar * Double(s)
        r.maxHp = jsRound(Double(r.maxHp) * hp)
        r.hp = r.maxHp
        let lo = jsRound(Double(r.atk.lowerBound) * atk), hi = jsRound(Double(r.atk.upperBound) * atk)
        r.atk = lo...max(lo, hi)
        return ["⭐ Prestige \(s) — +\(Int((hpPerStar * Double(s) * 100).rounded()))% health, +\(Int((atkPerStar * Double(s) * 100).rounded()))% attack, +\(Int((goldPerStar * Double(s) * 100).rounded()))% gold."]
    }

    /// The gold an enemy drops, with the stars.
    static func shape(_ e: inout Enemy, _ run: Run) {
        guard let s = run.prestige, s > 0 else { return }
        let g = 1 + goldPerStar * Double(s)
        let lo = jsRound(Double(e.gold.lowerBound) * g), hi = jsRound(Double(e.gold.upperBound) * g)
        e.gold = lo...max(lo, hi)
    }
}
