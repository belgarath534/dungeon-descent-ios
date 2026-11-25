import Foundation

/// 12.2: weapons upgrade without end at the Blacksmith (each level past 10
/// costs 40% more), and the dungeon answers: for every level past 10, the
/// enemies you fight have 4% more HP and hit 3% harder. A weapon level still
/// adds more than it costs you (2.5 attack a level), so upgrading always
/// helps, but the dungeon keeps up.
public enum WeaponGrowth {
    public static let freeLevels = 10
    public static let hpPerLevel = 0.04
    public static let atkPerLevel = 0.03

    static func levelsPast(_ run: Run) -> Int { max(0, (run.equippedWeapon?.level ?? 1) - freeLevels) }

    /// How much tougher enemies are at this weapon level, in percent (for the Blacksmith's message).
    public static func percent(level: Int) -> Int { Int((Double(max(0, level - freeLevels)) * hpPerLevel * 100).rounded()) }

    /// An enemy grown to meet your weapon (once; marked so it never grows twice).
    public static func scaled(_ e: Enemy, for run: Run) -> Enemy {
        let n = levelsPast(run)
        guard n > 0, e.mechanics["weaponGrown"] == nil else { return e }
        var g = e
        let hp = 1 + Double(n) * hpPerLevel, atk = 1 + Double(n) * atkPerLevel
        g.maxHp = jsRound(Double(e.maxHp) * hp)
        g.hp = jsRound(Double(e.hp) * hp)
        g.atk = jsRound(Double(e.atk.lowerBound) * atk)...max(jsRound(Double(e.atk.lowerBound) * atk), jsRound(Double(e.atk.upperBound) * atk))
        g.mechanics["weaponGrown"] = .bool(true)
        return g
    }
}
