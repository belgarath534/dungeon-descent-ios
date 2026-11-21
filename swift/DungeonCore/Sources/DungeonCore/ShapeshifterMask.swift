import Foundation

/// The Shapeshifter's Mask (Shadow World loot, shadowItem "shapeshifterMask"):
/// once a run, in a fight, it copies the enemy's ability for the rest of that
/// fight. Twelve abilities, or 30 HP when the enemy has none. The web version
/// kept the copied ability past the fight and never wove the Void Web; Swift
/// keeps each one to the fight it was copied in, as the Mask says.
public enum ShapeshifterMask {
    public static func isMask(_ item: Item) -> Bool { item.extra["shadowItem"] == .string("shapeshifterMask") }

    /// (key on the enemy, ability, what it does)
    static let abilities: [(String, String, String)] = [
        ("immuneFirstHit", "immunity to first hit", "You are now immune to the next hit this combat."),
        ("corruptOnHit", "corruption on hit", "Your next attack will add corruption to the enemy."),
        ("fearHowl", "fear howl", "The enemy is filled with fear — their damage is reduced 20% for 3 turns."),
        ("twiceDead", "second life", "You will return at 50% HP if you die this combat. Once."),
        ("grows", "growing power", "You gain +4 ATK every turn for the rest of this combat."),
        ("dodgeEvery", "phase dodge", "You will dodge every other hit this combat."),
        ("corruptWeb", "void web", "You weave a shadow web — the enemy takes 8 damage every turn until combat ends."),
        ("reflection", "reflection", "The enemy's next attack will be reflected back at them for full damage."),
        ("lurkerHide", "lurker strike", "Your next attack is a guaranteed critical hit dealing 2.5x damage."),
        ("mimicSurprise", "mimic surprise", "Your next attack deals double damage — the enemy never saw it coming."),
        ("shadowCommand", "shadow command", "You command the shadows — your ATK is increased by 15% for the rest of this combat."),
        ("spiritOnly", "spirit form", "You enter spirit form — you take half damage from all physical attacks this combat."),
    ]

    static func use(_ run: inout Run, at index: Int) -> Inventory.Outcome {
        guard run.inCombat, let e = run.enemy, !e.isDead else {
            return Inventory.Outcome(message: "The Mask can only be used in combat — face an enemy first.", used: false)
        }
        guard !run.maskUsed else { return Inventory.Outcome(message: "The Mask has already been used this run. Its power is spent.", used: false) }
        let ability: String, what: String
        if let a = abilities.first(where: { e.flag($0.0) }) {
            ability = a.1
            what = a.2
            run.fight.mask = a.0
            if a.0 == "fearHowl" { run.fight.maskFear = 3 }
            if a.0 == "corruptOnHit" { run.fight.maskCorrupt = max(1, Int(e.number("corruptOnHit") ?? 1)) }
        } else {
            ability = "shadow essence"
            what = "The Mask absorbs the enemy's shadow essence — you heal 30 HP."
            run.hp = min(run.maxHp, run.hp + 30)
        }
        run.maskUsed = true
        run.inventory.remove(at: index)
        return Inventory.Outcome(message: "🎭 The Mask melts into your face. You copy: \(ability)! \(what)")
    }

    /// doFight: growing power, lurker strike, mimic surprise, shadow command, corruption.
    static func attackRoll(_ run: inout Run, _ base: Int, log: inout [String]) -> Int {
        var a = base
        switch run.fight.mask {
        case "grows":
            run.fight.maskGrow += 4
            a += run.fight.maskGrow
            log.append("🎭 Mask: Growing Power — +\(run.fight.maskGrow) ATK this turn.")
        case "lurkerHide":
            run.fight.mask = ""
            a = jsRound(Double(a) * 2.5)
            log.append("🎭 Mask: Lurker Strike — guaranteed 2.5x critical hit!")
        case "mimicSurprise":
            run.fight.mask = ""
            a *= 2
            log.append("🎭 Mask: Mimic Surprise — double damage!")
        case "shadowCommand":
            a = jsRound(Double(a) * 1.15)
        case "corruptOnHit":
            run.fight.mask = ""
            let extra = run.fight.maskCorrupt * 10
            a += extra
            log.append("🎭 Mask: Corruption spreads to the enemy — +\(extra) damage.")
        default: break
        }
        return a
    }

    /// The Void Web, before the enemy acts.
    static func enemyTurn(_ run: inout Run, log: inout [String]) {
        guard run.fight.mask == "corruptWeb", var e = run.enemy, !e.isDead else { return }
        e.hp = max(0, e.hp - 8)
        run.enemy = e
        log.append("🕸️ Your void web tightens on \(e.name) for 8 damage.")
    }

    /// enemyAttack: immunity, phase dodge, reflection, spirit form, second life, fear.
    static func incoming(_ run: inout Run, _ taken: Int, log: inout [String]) -> Int {
        guard taken > 0 else { return taken }
        var t = taken
        switch run.fight.mask {
        case "immuneFirstHit":
            run.fight.mask = ""
            log.append("🎭 Mask absorbs the hit — immunity triggered!")
            return 0
        case "dodgeEvery":
            run.fight.maskToggle.toggle()
            if run.fight.maskToggle { log.append("🎭 Mask: Phase Dodge — you slip through the attack!"); return 0 }
        case "reflection":
            run.fight.mask = ""
            if var e = run.enemy {
                e.hp = max(0, e.hp - t)
                run.enemy = e
            }
            log.append("🎭 Mask: Reflection — \(t) damage reflected back at the enemy!")
            return 0
        case "spiritOnly":
            t = max(1, jsRound(Double(t) * 0.5))
            log.append("🎭 Mask: Spirit Form — physical damage halved!")
        default: break
        }
        if run.fight.maskFear > 0 {
            t = max(1, jsRound(Double(t) * 0.8))
            run.fight.maskFear -= 1
            log.append("😨 Enemy is afraid — damage reduced 20%. \(run.fight.maskFear) turn\(run.fight.maskFear != 1 ? "s" : "") left.")
        }
        if run.fight.mask == "twiceDead" && run.hp - t <= 0 {
            run.fight.mask = ""
            run.hp = jsRound(Double(run.maxHp) * 0.5)
            log.append("🎭 Mask: Second Life — you refuse to die! Revived at 50% HP!")
            return 0
        }
        return t
    }
}
