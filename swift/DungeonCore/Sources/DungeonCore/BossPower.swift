import Foundation

/// 12.2: bosses that stand up to strong characters. A player could kill a
/// dungeon's boss in a few hits, so its timer and phases never mattered.
/// When a boss appears it measures you: its HP is at least 15 to 40 of your
/// average hits (hitsToKill: more for prestige and an upgraded weapon), and
/// each of its hits takes at least a tenth of your max HP. Bosses already that strong, against weaker characters, are
/// left as they are. Its phases keep their places on its health bar.
public enum BossPower {
    /// How many of your average hits a boss takes at least: 15 for everyone,
    /// 1.5 more for each prestige star and 1 more for each weapon level past
    /// 10, up to 40. A new character's boss gets a bit harder; a character
    /// hitting for thousands gets a real fight.
    public static func hitsToKill(_ run: Run) -> Double {
        let stars = Double(run.prestige ?? 0)
        let weapon = Double(max(0, (run.equippedWeapon?.level ?? 1) - WeaponGrowth.freeLevels))
        return min(40, 15 + 1.5 * stars + weapon)
    }
    public static let hitShare = 0.10

    /// Your average hit right now.
    static func averageHit(_ run: Run) -> Int {
        let base = Double(run.atk.lowerBound + run.atk.upperBound) / 2 + Double(run.totalAtkBonus)
        return Prestige.hit(run, max(1, jsRound(base)))
    }

    public static func scaled(_ e: Enemy, for run: Run) -> Enemy {
        guard e.isBoss, e.mechanics["bossPower"] == nil else { return e }
        var b = e
        b.mechanics["bossPower"] = .bool(true)
        let wantHp = jsRound(Double(averageHit(run)) * hitsToKill(run))
        if wantHp > b.maxHp {
            let f = Double(wantHp) / Double(max(1, b.maxHp))
            b.hp = jsRound(Double(b.hp) * f)
            b.maxHp = wantHp
            b.phase1Hp = jsRound(Double(b.phase1Hp) * f)
            b.phase2Hp = jsRound(Double(b.phase2Hp) * f)
        }
        let wantHit = jsRound(Double(run.maxHp) * hitShare)
        let mid = (b.atk.lowerBound + b.atk.upperBound) / 2
        if wantHit > mid {
            let lo = jsRound(Double(wantHit) * 0.8), hi = jsRound(Double(wantHit) * 1.4)
            b.atk = lo...max(lo, hi)
        }
        return b
    }
}
