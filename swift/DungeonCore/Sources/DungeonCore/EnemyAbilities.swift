import Foundation

/// A named enemy's chance-based special move (the web version's ENEMY_SPECIALS).
public struct EnemySpecial: Decodable, Sendable {
    public let name: String
    public let chance: Double
    public let msg: String
    public let effect: String
}

/// Enemy abilities: the ENEMY_SPECIALS moves (by enemy name) and the ability
/// flags in the enemy tables (applyEnemyMechanicsOnHit / OnTurn). Flags the web
/// version described but never applied (burn, dodgeEvery) follow their descriptions.
enum EnemyAbilities {
    /// Adjusts your damage as it lands on the enemy. `basic` is false for skills.
    static func onPlayerHit(_ run: inout Run, _ dmg: Int, basic: Bool, dice: inout some Dice, log: inout [String]) -> Int {
        guard dmg > 0, var e = run.enemy else { return dmg }
        var d = dmg
        defer { run.enemy = e }
        e.hitsTaken += 1

        if e.vanished {
            e.vanished = false
            log.append("\(e.name) isn't there to hit!")
            return 0
        }
        if e.flag("immuneFirstHit") && e.hitsTaken == 1 {
            log.append("\(e.name) absorbs the first blow! Immune to the opening strike.")
            return 0
        }
        if let every = e.number("dodgeEvery"), every > 0, e.hitsTaken % Int(every) == 0 {
            log.append("\(e.name) phases out of reality — your attack passes through!")
            return 0
        }
        if let p = e.number("dodgeChance"), dice.chance(p) {
            log.append("\(e.name) dodges the attack!")
            return 0
        }
        if e.flag("hollowGhost") && dice.chance(0.30) {
            log.append("👻 \(e.name) phases through your attack. It is not entirely here.")
            return 0
        }
        Chimera.reflect(&run, d, log: &log)
        if basic, let resist = e.number("physResist") {
            d = jsRound(Double(d) * (1 - resist))
        }
        if e.flag("grows") {
            e.atk = jsRound(Double(e.atk.lowerBound) * 1.05)...jsRound(Double(e.atk.upperBound) * 1.05)
        }
        if e.flag("hollowVampire") {
            e.hp = min(e.maxHp, e.hp + 8)
            log.append("🧛 \(e.name) drinks deep. +8 HP restored.")
        }
        return d
    }

    /// Cowards run when you look strong. Returns the gold they drop, or nil if they stay.
    static func cowardFlees(_ run: inout Run, dice: inout some Dice, log: inout [String]) -> Int? {
        guard let e = run.enemy, e.flag("coward") else { return nil }
        guard Double(run.hp) >= Double(run.maxHp) * 0.80 else { return nil }
        let g = dice.roll(e.gold)
        log.append("💨 \(e.name) takes one look at you and runs! It drops \(g) gold in its panic.")
        return g
    }

    struct Move {
        var multiplier = 1.0
        var extra = 0
        var ignoreDefense = false
        var skipAttack = false
    }

    /// Before the enemy attacks: first-turn buffs and its special move, if it rolls one.
    static func beforeAttack(_ run: inout Run, dice: inout some Dice, log: inout [String]) -> Move {
        guard var e = run.enemy else { return Move() }
        var m = Move()
        e.turnsTaken += 1
        if e.flag("buffsOnTurn1") && e.turnsTaken == 1 {
            e.atk = jsRound(Double(e.atk.lowerBound) * 1.5)...jsRound(Double(e.atk.upperBound) * 1.5)
            log.append("\(e.name) gathers itself. Its attacks grow stronger!")
        }
        run.enemy = e
        Chimera.beforeAttack(&run, log: &log)
        // The Music Box plays instead of attacking.
        if HollowEvents.melody(&run, dice: &dice, log: &log) {
            m.skipAttack = true
            return m
        }
        // Medusa's gaze comes instead of her attack.
        if Medusa.gaze(&run, dice: &dice, log: &log) {
            m.skipAttack = true
            return m
        }
        if WhisperingForest.shadeTriple(&run, dice: &dice, log: &log) {
            m.multiplier = 2
            return m
        }
        guard let s = GameContent.shared.enemySpecials[e.name], dice.chance(s.chance) else { return m }
        log.append("⚡ " + s.msg)
        switch s.effect {
        case "ignore-def": m.ignoreDefense = true
        case "double-dmg": m.multiplier = 2
        case "spawn": m.extra = 5; log.append("A tiny spider joins the fight! +5 extra damage this turn.")
        case "vanish":
            m.skipAttack = true
            e.vanished = true
            run.enemy = e
        case "sp-drain": run.sp = max(0, run.sp - 6)
        case "weaken":
            run.fight.atk -= 2
            log.append("Your attack is weakened by 2 for this fight.")
        case "freeze-player":
            if !run.debuffImmune && run.armorEffect != "juggernaut" { run.frozen = true; log.append("You are frozen! Your next action will fail.") }
        case "reduce-maxhp":
            run.maxHp = max(20, run.maxHp - 15)
            run.hp = min(run.hp, run.maxHp)
        default: break
        }
        return m
    }

    /// After the enemy's hit lands.
    static func afterAttack(_ run: inout Run, taken: Int, dice: inout some Dice, log: inout [String]) {
        SpecialEncounters.steal(&run, dice: &dice, log: &log)
        guard var e = run.enemy else { return }
        defer { run.enemy = e }
        if let p = e.number("lifesteal"), taken > 0 {
            let heal = jsRound(Double(taken) * p)
            e.hp = min(e.maxHp, e.hp + heal)
            if heal > 0 { log.append("\(e.name) drains \(heal) HP from you.") }
        }
        if let sp = e.number("drainsSP") ?? e.number("spDrain") {
            run.sp = max(0, run.sp - Int(sp))
            log.append("\(e.name) drains \(Int(sp)) SP.")
        }
        if let n = e.number("drainHpSp") {
            let d = Int(n)
            run.hp = max(1, run.hp - d)
            run.sp = max(0, run.sp - d)
            e.hp = min(e.maxHp, e.hp + d)
            log.append("\(e.name) drains \(d) HP and SP.")
        }
        if let burn = e.number("burn"), taken > 0, !run.debuffImmune {
            run.poisonDamage = Int(burn)
            run.poisonTurns = max(run.poisonTurns, Int(e.number("burnTurns") ?? 2))
            log.append("🔥 You are burning: \(Int(burn)) damage per turn.")
        }
        if let p = e.number("poisonChance"), taken > 0, !run.debuffImmune, dice.chance(p) {
            run.poisonDamage = max(run.poisonDamage, 6)
            run.poisonTurns = max(run.poisonTurns, 3)
            log.append("☠️ You are poisoned.")
        }
        if let p = e.number("stunChance"), taken > 0, !run.debuffImmune, run.armorEffect != "juggernaut", dice.chance(p) {
            run.frozen = true
            log.append("You are stunned! Your next action will fail.")
        }
        if e.flag("slowAtk") && e.turnsTaken % 2 == 0 {
            e.atk = max(1, e.atk.lowerBound - 1)...max(1, e.atk.upperBound - 1)
        }
        if case .object(let h)? = e.mechanics["healPerTurns"], case .number(let amount)? = h["amount"] {
            let every = Int(e.number("every") ?? 3)
            if every > 0 && e.turnsTaken % every == 0 {
                e.hp = min(e.maxHp, e.hp + Int(amount))
                log.append("\(e.name) recovers \(Int(amount)) HP.")
            }
        }
    }

    /// Doubles the hit for enemies that strike twice.
    static func secondStrike(_ e: Enemy, dice: inout some Dice, log: inout [String]) -> Int {
        guard e.flag("doubleStrike") else { return 0 }
        let bonus = dice.roll(e.currentAtk)
        log.append("\(e.name) strikes TWICE! Extra \(bonus) damage!")
        return bonus
    }
}
