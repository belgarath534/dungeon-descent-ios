import Foundation

/// The boss timer (startBossTimer, checkBossTimerThreshold, bossTimerEnrage):
/// when a dungeon's boss appears you have 5 minutes (3 in The Hollow, one
/// less in Insane) to bring it below half its HP. Make it and the timer stops;
/// run out and the boss's attack grows 25% and a minion joins the fight. (The
/// web version announced the minion but never added it.)
public enum BossTimer {
    public static func seconds(for run: Run) -> Int {
        var minutes = run.dungeon == "The Hollow" ? 3 : 5
        if run.difficulty == .insane { minutes = max(2, minutes - 1) }
        return minutes * 60
    }

    /// Below half its HP: you beat the clock.
    public static func beaten(_ run: Run) -> Bool {
        guard let e = run.enemy, e.isBoss else { return false }
        return e.hp <= jsRound(Double(e.maxHp) * 0.5)
    }

    static func minionName(_ dungeon: String) -> String {
        switch dungeon {
        case "The Hollow": return "Hollow Shade"
        case "The Ashbound Wastes": return "Ash Wraith"
        case "Frosthold Abyss": return "Frost Revenant"
        case "The Sunken Archives": return "Drowned Scholar"
        default: return "Crypt Stalker"
        }
    }

    /// Time's up. Returns the line to log.
    public static func enrage(_ run: inout Run, dice: inout some Dice) -> String? {
        guard run.inCombat, var e = run.enemy, e.isBoss, !e.isDead else { return nil }
        let lo = jsRound(Double(e.atk.lowerBound) * 1.25), hi = jsRound(Double(e.atk.upperBound) * 1.25)
        e.atk = lo...max(lo, hi)
        run.enemy = e
        // The minion: one of the dungeon's own first-tier enemies at this floor's strength.
        let pool = Bestiary.enemies(for: run.dungeon, difficulty: run.difficulty).t1
        let name = minionName(run.dungeon)
        if !pool.isEmpty {
            var m = Enemy.spawn(pool[dice.roll(0...(pool.count - 1))], floor: run.floor, playerLevel: run.level)
            m.name = name
            // It falls with its boss, so killing the boss still wins the dungeon.
            m.mechanics["bossMinion"] = .bool(true)
            run.foes.append(m)
        }
        return "⚠ TIME'S UP — \(e.name) grows impatient. Attack +25%. \(name) joins the fight!"
    }
}

/// The pre-boss gauntlet (startPreBossGauntlet, spawnGauntletWave): after the
/// floor 10 Elite Guardian, one or two waves of the dungeon's tier 2 enemies
/// stand between you and the boss.
public enum PreBossGauntlet {
    public static func waves(dice: inout some Dice) -> Int { dice.chance(0.5) ? 1 : 2 }

    public static func minion(for run: Run, wave: Int, of total: Int, dice: inout some Dice) -> Enemy? {
        let pool = Bestiary.enemies(for: run.dungeon, difficulty: run.difficulty).t2
        guard !pool.isEmpty else { return nil }
        let t = pool[dice.roll(0...(pool.count - 1))]
        let diff: Double = run.difficulty == .nightmare ? 1.4 : run.difficulty == .forsaken ? 1.2 : run.difficulty == .condemned ? 1.1 : 1
        let ng = run.ngPlus ? 1.15 : 1
        let hp = jsRound(Double(t.hp) * 1.2 * diff * ng)
        let lo = jsRound(Double(t.atk.lowerBound) * 1.1 * ng), hi = jsRound(Double(t.atk.upperBound) * 1.1 * ng)
        var e = Enemy(name: t.name, icon: t.icon, hp: hp, maxHp: hp, atk: lo...max(lo, hi), gold: t.gold)
        e.mechanics = t.mechanics
        e.mechanics["preBossWave"] = .number(Double(wave))
        e.mechanics["isElite"] = nil
        e.desc = t.desc
        return e
    }
}
