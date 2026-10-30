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
