import Foundation

public enum PlayerAction: String, Sendable {
    case attack, heavy, defend
}

/// What happened in one combat turn. `log` lines are worded like the web
/// version's combat log; `announcement` is the short line for VoiceOver.
public struct TurnResult: Equatable, Sendable {
    public var playerDamage = 0
    public var crit = false
    public var missed = false
    /// nil when the enemy didn't get to attack (it died first).
    public var enemyDamage: Int? = nil
    public var enemyDied = false
    public var playerDied = false
    public var log: [String] = []
    public var announcement: String? = nil
}

/// The basic fight loop from doFight(): attack, heavy strike and defend, then
/// the enemy's counter-attack. Skills, potions, weapon effects, spirits and
/// the special enemies are not ported yet.
public enum Combat {
    public struct Options: Sendable {
        /// Accessibility setting "class traits" (on by default in the web version).
        public var classTraits = true
        public init(classTraits: Bool = true) { self.classTraits = classTraits }
    }

    public static func begin(_ run: inout Run, against enemy: Enemy) {
        run.enemy = enemy
        run.inCombat = true
        run.defending = false
    }

    /// Picks and scales the next normal enemy for the current floor.
    public static func nextEnemy(for run: Run, dice: inout some Dice) -> Enemy {
        let pool = Bestiary.enemies(for: run.dungeon).pool(forFloor: run.floor)
        let t = pool[dice.roll(0...(pool.count - 1))]
        return Enemy.spawn(t, floor: run.floor, playerLevel: run.level,
                           ngPlusCount: ngCount(run), endless: run.difficulty == .endless)
    }

    /// Picks and scales the boss for the run's dungeon.
    public static func nextBoss(for run: Run, dice: inout some Dice) -> Enemy {
        let pool = Bestiary.enemies(for: run.dungeon).bosses
        let t = pool[dice.roll(0...(pool.count - 1))]
        return Enemy.spawnBoss(t, playerLevel: run.level, playerMaxAtk: run.atk.upperBound, ngPlusCount: ngCount(run))
    }

    /// One full turn: the player's action, then the enemy's counter if it survived.
    public static func takeTurn(_ run: inout Run, _ action: PlayerAction, dice: inout some Dice,
                                options: Options = Options()) -> TurnResult {
        guard run.inCombat, var e = run.enemy else { return TurnResult() }
        var r = TurnResult()

        let baseAtk = dice.roll(run.atk) + run.atkBonus
        run.defending = false

        switch action {
        case .attack:
            // Rolled first, like `Math.random() < p || markedKill` in the web version.
            let rolledCrit = dice.chance(0.10 + run.critBonus)
            r.crit = rolledCrit || run.markedKill
            if run.markedKill {
                run.markedKill = false
                r.log.append("Marked Kill activates — guaranteed critical!")
            }
            r.playerDamage = r.crit ? jsRound(Double(baseAtk) * 1.8) : baseAtk
            r.log.append(r.crit ? "CRITICAL HIT! You strike for \(r.playerDamage) damage!"
                                : "You attack for \(r.playerDamage) damage.")
        case .heavy:
            if dice.chance(0.30) {
                r.missed = true
                r.log.append("Your heavy strike misses! The enemy sidesteps.")
            } else {
                r.playerDamage = jsRound(Double(baseAtk) * 1.7)
                r.log.append("Heavy strike lands for \(r.playerDamage) damage!")
            }
        case .defend:
            run.defending = true
            r.playerDamage = jsRound(Double(baseAtk) * 0.5)
            r.log.append("You defend, dealing \(r.playerDamage) and bracing for the counter.")
        }

        e.hp = max(0, e.hp - r.playerDamage)
        run.enemy = e

        if e.isDead {
            r.enemyDied = true
            run.inCombat = false
            run.kills += 1
            r.announcement = "\(e.name) defeated."
            return r
        }

        let taken = enemyAttack(&run, e, dice: &dice, options: options, log: &r.log)
        r.enemyDamage = taken
        r.announcement = "\(e.name) dealt \(taken) damage. Your HP: \(run.hp) of \(run.maxHp)."
        if run.isDead {
            r.playerDied = true
            run.inCombat = false
        }
        return r
    }

    /// The enemy's counter-attack. Defense blocks at most 60% of a hit, and
    /// every hit does at least 1 damage.
    static func enemyAttack(_ run: inout Run, _ e: Enemy, dice: inout some Dice,
                            options: Options, log: inout [String]) -> Int {
        var raw = dice.roll(e.atk)
        raw = jsRound(Double(raw) * run.difficulty.enemyDamageMultiplier)
        if run.undeadRes && Bestiary.undeadNames.contains(e.name) {
            raw = jsRound(Double(raw) * 0.65)
        }
        let maxBlock = Int((Double(raw) * 0.60).rounded(.down))
        let defVal = run.def + run.defBonus + (run.defending ? 4 : 0)
        let blocked = min(defVal, maxBlock)
        var taken = max(1, raw - blocked)
        if options.classTraits {
            switch run.cls {
            case "Paladin": taken = max(1, jsRound(Double(taken) * 0.85))
            case "DeathKnight": taken = max(1, jsRound(Double(taken) * 0.80))
            case "Sentinel": taken = max(1, jsRound(Double(taken) * 0.75))
            default: break
            }
        }
        if blocked > 0 {
            log.append("\(e.name) strikes for \(raw) — you absorb \(blocked). You take \(taken) damage.")
        } else {
            log.append("\(e.name) attacks for \(taken) damage.")
        }
        run.hp = max(0, run.hp - taken)
        return taken
    }

    /// New Game+ count as the web version reads it (`ngPlusCount || 1`), or nil outside NG+.
    private static func ngCount(_ run: Run) -> Int? {
        guard run.ngPlus else { return nil }
        let n = run.ngPlusCount ?? 1
        return n == 0 ? 1 : n
    }
}
