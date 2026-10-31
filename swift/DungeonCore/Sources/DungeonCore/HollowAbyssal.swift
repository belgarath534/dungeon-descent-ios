import Foundation

/// The Hollow's one-off enemy mechanics (applyEnemyMechanicsOnTurn's HOLLOW
/// MECHANICS, the hollowZombie revive, the Twin and the Uninvited Guest) and the
/// Abyssal Deep's (applyAbyssalEnemyMechanics, applyAbyssalPlayerMechanics,
/// applyAbyssalSilence). Their counters live on the enemy, so they end with the fight.
enum HollowAbyssal {
    static func count(_ e: Enemy, _ key: String) -> Int { Int(e.number(key) ?? 0) }
    static func set(_ e: inout Enemy, _ key: String, _ n: Int) { e.mechanics[key] = .number(Double(n)) }

    // MARK: Combat start

    /// spawnTwin and the entrance lines. The Twin takes your HP and your attack.
    static func prepare(_ enemy: Enemy, for run: Run) -> Enemy {
        var e = enemy
        if e.flag("isTwin") {
            e.hp = run.maxHp
            e.maxHp = run.maxHp
            e.atk = (run.atkBonus + 5)...(run.atkBonus + 12)
        }
        return e
    }

    static func combatStart(_ run: inout Run, log: inout [String]) {
        guard let e = run.enemy else { return }
        if e.flag("isUninvited") {
            log.append("You search the room. Nothing. You turn around. It is behind you. It was not there before. It is there now. It has always been there.")
        }
        if e.flag("isTwin") {
            log.append("👤 \(e.name) has your face, your strength, your \(e.maxHp) HP. It knows exactly what you will do next.")
        }
        if e.flag("hollowZombie") {
            log.append("🧟 Something dead stands up. It should not be able to do that. Warning — it will rise once when killed.")
        }
        if e.flag("preventFlee") {
            log.append("⚠ \(e.name) blocks every exit. You cannot flee this fight.")
        }
    }

    // MARK: Your turn

    /// Flee attempts fail while it lives (the web version only warned).
    static func blocksFlee(_ run: Run) -> String? {
        guard let e = run.enemy, e.flag("preventFlee") else { return nil }
        return "You try to flee — but \(e.name) blocks every exit. There is no escape."
    }

    /// Your turn begins: the silence wears off.
    static func playerTurnStart(_ run: inout Run) {
        guard var e = run.enemy else { return }
        let s = count(e, "silenced")
        if s > 0 { set(&e, "silenced", s - 1); run.enemy = e }
    }

    static func silenced(_ run: Run) -> Bool {
        guard let e = run.enemy else { return false }
        return count(e, "silenced") > 0
    }

    /// applyAbyssalPlayerMechanics and the Abyssal Eel's shock. Nil when your
    /// attack is lost (blinded, or the Siren turns it on you).
    static func attackRoll(_ run: inout Run, _ base: Int, dice: inout some Dice, log: inout [String]) -> Int? {
        guard var e = run.enemy else { return base }
        defer { run.enemy = e }
        var atk = base
        let shock = count(e, "shock")
        if shock > 0 {
            set(&e, "shock", shock - 1)
            atk = max(1, atk - 2)
        }
        if count(e, "blinded") > 0 {
            set(&e, "blinded", 0)
            if dice.chance(0.40) {
                log.append("😵 You are blinded — your attack misses!")
                return nil
            }
        }
        if e.flag("charmed") {
            e.mechanics["charmed"] = .bool(false)
            if dice.chance(0.30) {
                run.hp = max(1, run.hp - atk)
                log.append("🧜 Siren charm — you strike yourself for \(atk) damage!")
                return nil
            }
        }
        if count(e, "shellArmor") > 0 {
            atk = jsRound(Double(atk) * 0.70)
            log.append("🦀 Shell armor absorbs some damage!")
        }
        return atk
    }

    // MARK: The enemy's turn

    struct Move { var skip = false; var multiplier = 1.0; var maxRoll = false; var ignoreDefense = false }

    static func beforeAttack(_ run: inout Run, dice: inout some Dice, log: inout [String]) -> Move {
        guard var e = run.enemy else { return Move() }
        var m = Move()
        defer { run.enemy = e }
        let turn = e.turnsTaken

        // ── The Hollow ──
        if e.flag("hollowWatch") {
            let stacks = count(e, "watchStacks") + 2
            set(&e, "watchStacks", stacks)
            e.atk = (e.atk.lowerBound + 2)...(e.atk.upperBound + 2)
            if stacks <= 6 { log.append("🖼️ The Portrait watches. Its gaze sharpens. +2 ATK (\(stacks) stacks).") }
        }
        // The bell rings on its second turn: your next turn is lost.
        if e.flag("hollowBell") && turn == 2 {
            run.frozen = true
            log.append("🔔 THE BELL RINGS. Your next turn is skipped!")
        }
        if e.flag("hollowCrawl") {
            let n = count(e, "crawlTurn") + 1
            set(&e, "crawlTurn", n)
            if n % 2 == 0 {
                m.multiplier *= 1.5
                m.ignoreDefense = true
                log.append("🧱 The Wall Crawler attacks from above — defense bypassed! +50% damage.")
            }
        }
        if e.flag("hollowGround") && e.hp > 0 && e.hp < e.maxHp {
            e.hp = min(e.maxHp, e.hp + 5)
            log.append("⚰️ The Groundskeeper tends to its wounds. +5 HP.")
        }
        if e.flag("hollowMatron") && run.dungeon == "The Hollow" { m.multiplier *= 1.1 }

        // ── The Abyssal Deep ──
        if e.flag("tidePhase") && run.defending {
            run.defending = false
            log.append("🌊 \(e.name) phases through your defense!")
        }
        if let every = e.number("silenceTimer"), every > 0 {
            let n = count(e, "silenceCount") + 1
            if n >= Int(every) {
                set(&e, "silenceCount", 0)
                set(&e, "silenced", 2)
                log.append("⚓ \(e.name) screams — your skills are silenced!")
            } else {
                set(&e, "silenceCount", n)
            }
        }
        if let p = e.number("blindChance"), dice.chance(p) {
            set(&e, "blinded", 1)
            log.append("🐙 \(e.name) sprays ink — you are blinded! Next attack may miss.")
        }
        // +10% for each turn it stays alive (the web version compounded it every turn).
        if e.flag("pressureStacks") {
            let n = count(e, "pressure") + 1
            set(&e, "pressure", n)
            m.multiplier *= 1 + 0.10 * Double(n)
            log.append("🌊 The pressure builds. \(e.name) hits \(n * 10)% harder.")
        }
        let shell = count(e, "shellArmor")
        if shell > 0 { set(&e, "shellArmor", shell - 1) }
        if let p = e.number("sirenCharm"), dice.chance(p) {
            e.mechanics["charmed"] = .bool(true)
            log.append("🧜 \(e.name) sings. Your next attack may turn on you.")
        }
        // Deep Stalker: studies you, then hits double.
        if e.flag("stalkerStudy") {
            if turn == 1 {
                log.append("👁️ \(e.name) circles you, studying every move. It does not attack — yet.")
                m.skip = true
            } else if turn == 2 {
                m.multiplier *= 2
                log.append("👁️ \(e.name) has learned you. It strikes for double damage!")
            }
        }
        if e.flag("anglerFirst") && turn == 1 {
            m.maxRoll = true
            log.append("🎣 The light was a lure. \(e.name) strikes at full force!")
        }
        return m
    }

    /// The Abyssal Eel's shock: −2 attack for your next two turns.
    static func afterAttack(_ run: inout Run, taken: Int, log: inout [String]) {
        guard taken > 0, var e = run.enemy, e.flag("shockATK") else { return }
        set(&e, "shock", 2)
        run.enemy = e
        log.append("⚡ \(e.name) shocks you — your attack drops by 2 for 2 turns.")
    }

    // MARK: Death

    /// hollowZombie: The Risen rises once at 20% HP.
    static func rises(_ run: inout Run) -> String? {
        guard var e = run.enemy, e.isDead, e.flag("hollowZombie"), !e.flag("zombieRevived") else { return nil }
        e.mechanics["zombieRevived"] = .bool(true)
        e.hp = max(1, jsRound(Double(e.maxHp) * 0.20))
        run.enemy = e
        return "🧟 \(e.name) falls — then rises again at 20 percent HP. It will not stay down."
    }
}
