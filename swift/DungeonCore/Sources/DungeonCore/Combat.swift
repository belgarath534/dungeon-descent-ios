import Foundation

public enum PlayerAction: String, Sendable {
    case attack, heavy, defend, flee
}

/// What happened in one combat turn. `log` lines are worded like the web
/// version's combat log; `announcement` is the short line for VoiceOver.
public struct TurnResult: Equatable, Sendable {
    public var playerDamage = 0
    public var crit = false
    public var missed = false
    public var fled = false
    /// nil when the enemy didn't get to attack.
    public var enemyDamage: Int? = nil
    public var enemyDied = false
    public var playerDied = false
    /// Set when a boss moved to a new phase this turn (it skips its counter).
    public var bossPhaseMessage: String? = nil
    public var log: [String] = []
    public var announcement: String? = nil
}

/// The fight loop from doFight(): attack, heavy strike, defend or flee, then
/// the enemy's counter-attack. Skills, weapon rarity effects, spirits and the
/// special enemies are not ported yet.
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
        if enemy.isBoss { run.bossPhase = 1 }
    }

    /// Picks and scales the next normal enemy for the current floor.
    public static func nextEnemy(for run: Run, dice: inout some Dice) -> Enemy {
        let pool = Bestiary.enemies(for: run.dungeon, difficulty: run.difficulty).pool(forFloor: run.floor)
        let t = pool[dice.roll(0...(pool.count - 1))]
        return Enemy.spawn(t, floor: run.floor, playerLevel: run.level,
                           ngPlusCount: ngCount(run), endless: run.difficulty == .endless)
    }

    /// Picks and scales the boss for the run's dungeon.
    public static func nextBoss(for run: Run, dice: inout some Dice) -> Enemy {
        let pool = Bestiary.enemies(for: run.dungeon, difficulty: run.difficulty).bosses
        let t = pool[dice.roll(0...(pool.count - 1))]
        return Enemy.spawnBoss(t, playerLevel: run.level, playerMaxAtk: run.atk.upperBound, ngPlusCount: ngCount(run))
    }

    /// One full turn: the player's action, then the enemy's counter if it survived.
    public static func takeTurn(_ run: inout Run, _ action: PlayerAction, dice: inout some Dice,
                                options: Options = Options()) -> TurnResult {
        guard run.inCombat, var e = run.enemy else { return TurnResult() }
        var r = TurnResult()

        let baseAtk = dice.roll(run.atk) + run.totalAtkBonus
        run.defending = false

        if run.frozen {
            run.frozen = false
            r.log.append("You are frozen and cannot act this turn!")
        } else {
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
            case .flee:
                let guaranteed = run.swiftTurns > 0 || run.runeSpeed
                if run.swiftTurns > 0 { run.swiftTurns -= 1 }
                let chance = guaranteed ? 1.0 : (run.hasFleeRing ? 0.75 : 0.45) + run.fleeBonus
                if dice.chance(chance) {
                    r.fled = true
                    run.inCombat = false
                    run.enemy = nil
                    let msg = guaranteed ? "💨 Swift as a ghost — you vanish before they can react."
                                         : "You slip into the shadows. The enemy's howl fades behind you."
                    r.log.append(msg)
                    r.announcement = "You successfully fled!"
                    return r
                }
                r.log.append("You attempt to flee — but there is nowhere to go.")
            }
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

        if let msg = checkBossPhase(&run) {
            r.bossPhaseMessage = msg
            r.log.append(msg)
            r.announcement = msg
            return r
        }

        let taken = enemyAttack(&run, dice: &dice, options: options, log: &r.log)
        r.enemyDamage = taken
        tickEffects(&run, log: &r.log)
        r.announcement = "\(e.name) dealt \(taken) damage. Your HP: \(run.hp) of \(run.maxHp)."
        if run.isDead {
            r.playerDied = true
            run.inCombat = false
        }
        return r
    }

    /// Standard three-phase bosses: phase 2 at 66% HP hits 25% harder, the
    /// final phase at 33% hits 35% harder. The boss skips its counter on the
    /// turn it changes phase (checkBossPhase).
    static func checkBossPhase(_ run: inout Run) -> String? {
        guard var e = run.enemy, e.isBoss, !e.isDead else { return nil }
        func scale(_ m: Double) {
            let lo = jsRound(Double(e.atk.lowerBound) * m), hi = jsRound(Double(e.atk.upperBound) * m)
            e.atk = lo...max(lo, hi)
        }
        var msg: String?
        if run.bossPhase == 1 && e.hp <= e.phase1Hp {
            run.bossPhase = 2
            scale(1.25)
            msg = "⚡ PHASE TRANSITION — " + (e.phaseMsg2 ?? "The boss enters phase 2 — it grows more powerful!")
        } else if run.bossPhase == 2 && e.hp <= e.phase2Hp {
            run.bossPhase = 3
            scale(1.35)
            msg = "⚡ FINAL PHASE — " + (e.phaseMsg3 ?? "Final phase — the boss unleashes everything!")
        }
        run.enemy = e
        return msg
    }

    /// The enemy's counter-attack. Defense blocks at most 60% of a hit, and
    /// every hit does at least 1 damage.
    static func enemyAttack(_ run: inout Run, dice: inout some Dice,
                            options: Options, log: inout [String]) -> Int {
        guard var e = run.enemy else { return 0 }
        var raw = dice.roll(e.currentAtk)
        raw = jsRound(Double(raw) * run.difficulty.enemyDamageMultiplier)
        if run.undeadRes && Bestiary.undeadNames.contains(e.name) {
            raw = jsRound(Double(raw) * 0.65)
        }
        let maxBlock = Int((Double(raw) * 0.60).rounded(.down))
        let defVal = run.totalDef + (run.defending ? 4 : 0)
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
        if e.cursedTurns > 0 {
            e.cursedTurns -= 1
            if e.cursedTurns == 0 { log.append("The curse on \(e.name) fades.") }
            run.enemy = e
        }
        return taken
    }

    /// Counts down potion buffs and applies poison once per turn.
    public static func tickEffects(_ run: inout Run, log: inout [String]) {
        if run.tempAtkTurns > 0 {
            run.tempAtkTurns -= 1
            if run.tempAtkTurns == 0 { run.tempAtk = 0; log.append("Your attack boost fades.") }
        }
        if run.tempDefTurns > 0 {
            run.tempDefTurns -= 1
            if run.tempDefTurns == 0 { run.tempDef = 0; log.append("Your defense boost fades.") }
        }
        if run.poisonTurns > 0 && run.hp > 0 {
            run.poisonTurns -= 1
            run.hp = max(0, run.hp - run.poisonDamage)
            log.append("Poison deals \(run.poisonDamage) damage. (\(run.poisonTurns) turns left)")
        }
    }

    /// New Game+ count as the web version reads it (`ngPlusCount || 1`), or nil outside NG+.
    private static func ngCount(_ run: Run) -> Int? {
        guard run.ngPlus else { return nil }
        let n = run.ngPlusCount ?? 1
        return n == 0 ? 1 : n
    }
}
