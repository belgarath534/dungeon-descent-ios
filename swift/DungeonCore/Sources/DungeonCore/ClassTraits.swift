import Foundation

/// Class traits (CLASS_TRAITS, applyClassTraits, applyTraitPerFloor,
/// applyTraitOnKill, and the class checks in initDungeon, doFight,
/// enemyTurn, enemyDead and handleDeath), on while Settings → Gameplay →
/// Class Traits is on.
///
/// The web version had two layers, the trait announced at the start of a run
/// and older class bonuses scattered through the fight code, and both apply
/// here. Where the announced trait and the code disagree, Swift does what the
/// announcement says. (Paladin's damage cut and Weeping Child, DeathKnight's
/// and Sentinel's damage cuts are in Combat and HollowEvents already.)
public enum ClassTraits {
    public struct Trait: Equatable, Sendable {
        public let name: String
        public let desc: String
    }

    public static let all: [String: Trait] = [
        "Warrior": Trait(name: "Battle Hardened", desc: "+1 attack every 3 floors. Hits harder the deeper you go."),
        "Monk": Trait(name: "Iron Body", desc: "Defense doubles when HP drops below 30%. 10% chance to dodge an attack."),
        "Assassin": Trait(name: "First Blood", desc: "First hit every combat is always a critical strike. 15% chance to kill a non-boss outright."),
        "Paladin": Trait(name: "Divine Presence", desc: "Weeping Child always auto-soothed. Holy skills 20% stronger. Take 15% less damage."),
        "Naturalist": Trait(name: "One With The Wild", desc: "Hollow weather bonuses doubled. +3 defense."),
        "Sorcerer": Trait(name: "Glass Cannon", desc: "Skills cost 3 less SP. Attacks deal 20% more. Max HP capped at 80%."),
        "Necromancer": Trait(name: "Death Follows", desc: "15% chance a killed enemy fights for you next room. Heal 5 HP per kill."),
        "Berserker": Trait(name: "No Retreat", desc: "Cannot flee. +3 attack, -1 defense. Damage increases as HP drops."),
        "Bard": Trait(name: "Silver Tongue", desc: "Enemies have a 10% chance to leave without fighting, and a 15% chance to be charmed out of an attack."),
        "Alchemist": Trait(name: "Master Brewer", desc: "Potions heal double. Starts with 2 extra potions."),
        "BloodKnight": Trait(name: "Blood Harvest", desc: "Gains 5 HP from every kill and 8% of your max HP from a boss. Loses 2 HP each floor."),
        "Druid": Trait(name: "Nature's Bond", desc: "+3 HP per room in The Hollow. Heal 3% of your max HP every floor."),
        "Warlock": Trait(name: "Soul Drain", desc: "Drains 5 HP from every kill to heal yourself. 25% chance an attack deals double."),
        "DeathKnight": Trait(name: "Undying Resolve", desc: "Survive one killing blow per run at 1 HP. Take 20% less damage."),
        "Ranger": Trait(name: "Opening Shot", desc: "First hit every combat deals 75% bonus damage. +15% flee chance."),
        "Sentinel": Trait(name: "Iron Bulwark", desc: "Take 25% less damage from all sources. Deal 20% less damage. Built to outlast."),
        "Cleric": Trait(name: "Sacred Healer", desc: "Potions heal triple. Every 5th floor restores 5% of your max HP."),
        "Wizard": Trait(name: "Arcane Study", desc: "Reveals enemy HP and attack range at combat start. Starts each run with a Spell Scroll. 20% chance an attack deals triple. 20% less max HP."),
        "Elementalist": Trait(name: "Elemental Mastery", desc: "Fire, ice and storm spells deal 40% more damage. Starts with one elemental scroll. 15% less max HP."),
        "VoidWalker": Trait(name: "Void Touched", desc: "Void spells never miss. 15% chance to phase through enemy attacks completely. 20% less max HP."),
        "ShadowMage": Trait(name: "Shadow Affinity", desc: "Shadow spells cost 0 cooldown turns. Attacks at night (8pm to 6am) deal +25% damage. 15% less max HP."),
        "TimeMage": Trait(name: "Time Mastery", desc: "Time spells have a 1 turn cooldown instead of 3 (3 instead of 6 for Time Stop). 18% less max HP."),
        "Shaman": Trait(name: "Earth Bond", desc: "Earthshake always stuns. Dungeon condition bonuses doubled. +4 DEF in the Ashbound Wastes, Frosthold and the Whispering Forest. 10% less max HP."),
        "Arcanist": Trait(name: "Pure Arcane", desc: "All spells cast at full power regardless of class. Learns any scroll at 95% success rate. 22% less max HP."),
        "Dragonborn": Trait(name: "Dragon's Fury", desc: "+15% damage on every attack, growing 5% a floor from floor 4."),
    ]

    public static func trait(_ cls: String) -> Trait? { all[cls] }

    static func on(_ run: Run, _ cls: String) -> Bool { run.classTraits && run.cls == cls }

    static let outdoors: Set<String> = ["The Ashbound Wastes", "Frosthold Abyss", "The Whispering Forest"]
    static let elemental: Set<String> = ["soulfire", "agony", "fireball", "frost-lance", "the-tornado", "earthshake"]
    static let time: Set<String> = ["time-stop", "time-echo", "time-fracture"]

    /// Turns the class trait on for a new run. Returns the announcement.
    public static func start(_ run: inout Run, classTraits: Bool) -> String? {
        guard classTraits, let t = trait(run.cls) else { return nil }
        run.classTraits = true
        func hp(_ m: Double) {
            run.maxHp = max(1, jsRound(Double(run.maxHp) * m))
            run.hp = min(run.hp, run.maxHp)
        }
        func potion() { run.inventory.append(Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "Restores 40 HP.", heal: 40)) }
        switch run.cls {
        case "Sorcerer": hp(0.80)
        case "Wizard":
            hp(0.80)
            run.inventory.append(Item(name: "Spell Scroll", icon: "📜", type: "sp-potion", desc: "Arcane scroll. Restores 40 SP.", sp: 40))
        case "Elementalist":
            hp(0.85)
            if let s = Spells.entry("soulfire") { run.inventory.append(Spells.scrollItem(s)) }
        case "VoidWalker": hp(0.80)
        case "ShadowMage": hp(0.85)
        case "TimeMage": hp(0.82)
        case "Shaman":
            hp(0.90)
            if outdoors.contains(run.dungeon) { run.defBonus += 4 }
        case "Arcanist": hp(0.78)
        case "Alchemist": run.potionMult *= 2; potion(); potion()
        case "Cleric": run.potionMult *= 3
        case "Berserker": run.atkBonus += 3; run.defBonus = max(0, run.defBonus - 1)
        case "Ranger": run.fleeBonus += 0.15
        case "Naturalist": run.defBonus += 3
        case "DeathKnight": run.undyingResolve = true
        default: break
        }
        return "✦ Class Trait: \(t.name) — \(t.desc)"
    }

    /// Shaman everywhere and the Naturalist in The Hollow get double the good
    /// side of tonight's conditions.
    public static func shapeWeather(_ run: inout Run) {
        guard var w = run.weather, on(run, "Shaman") || (on(run, "Naturalist") && run.dungeon == "The Hollow") else { return }
        func up(_ m: Double) -> Double { m > 1 ? 1 + (m - 1) * 2 : m }
        func down(_ m: Double) -> Double { m < 1 ? max(0, 1 - (1 - m) * 2) : m }
        let before = w
        w.playerAtkMult = up(w.playerAtkMult)
        w.goldMult = up(w.goldMult)
        w.enemyAtkMult = down(w.enemyAtkMult)
        w.damageTaken = down(w.damageTaken)
        w.potionBoost *= 2
        w.spDiscount *= 2
        w.hpPerKill *= 2
        let extraHp = w.hpBonus, extraSp = w.spBonus
        w.hpBonus *= 2
        w.spBonus *= 2
        guard w != before else { return }
        run.maxHp += extraHp; run.hp = min(run.maxHp, run.hp + extraHp)
        run.maxSp += extraSp; run.sp = min(run.maxSp, run.sp + extraSp)
        w.effect += " (Doubled by your class trait.)"
        run.weather = w
    }

    /// A new fight: the Ranger's opening shot and the Assassin's first blood are
    /// ready, the Wizard reads the enemy, and a risen enemy joins you.
    static func combatStart(_ run: inout Run, log: inout [String]) {
        guard run.classTraits, let e = run.enemy else { return }
        if run.cls == "Ranger" { run.fight.openingShot = true }
        if run.cls == "Assassin" { run.fight.firstBlood = true }
        if run.cls == "Wizard" {
            log.append("🔮 Arcane Study: \(e.name) has \(e.hp) HP and hits for \(e.atk.lowerBound) to \(e.atk.upperBound).")
        }
        if let ally = run.raised {
            run.raised = nil
            run.fight.ally = ally
            log.append("💀 Death Follows — the risen \(ally.name) fights beside you.")
        }
    }

    /// Bard: 10% of ordinary enemies leave without fighting.
    public static func talksDown(_ run: Run, _ e: Enemy, dice: inout some Dice) -> String? {
        guard on(run, "Bard"), !e.isBoss, !e.isElite, dice.chance(0.10) else { return nil }
        return "🎵 Silver Tongue — you talk your way past. The \(e.name) leaves without a fight."
    }

    /// The first-strike crit: the Assassin's First Blood.
    static func firstBloodCrit(_ run: inout Run) -> Bool {
        guard run.fight.firstBlood else { return false }
        run.fight.firstBlood = false
        return true
    }

    /// Your hit after the class's own bonuses (doFight's class checks).
    static func attack(_ run: inout Run, _ dmg: Int, dice: inout some Dice, log: inout [String]) -> Int {
        guard run.classTraits, dmg > 0, let e = run.enemy else { return dmg }
        var d = dmg
        if run.cls == "Berserker" && run.hp < run.maxHp / 2 {
            d = jsRound(Double(d) * (1 + (1 - Double(run.hp) / Double(run.maxHp)) * 0.5))
        }
        if run.cls == "Dragonborn" { d = jsRound(Double(d) * dragonbornMult(run)) }
        if run.fight.openingShot {
            run.fight.openingShot = false
            d = jsRound(Double(d) * 1.75)
            log.append("🏹 Ranger's Opening Shot — +75% first hit damage!")
        }
        switch run.cls {
        case "Sentinel": d = jsRound(Double(d) * 0.80)
        case "Assassin" where !e.isBoss && dice.chance(0.15):
            d = max(d, e.hp)
            log.append("💀 Assassin's Mark — instant kill!")
        case "Warlock" where dice.chance(0.25):
            d *= 2
            log.append("🔥 Dark Pact — double damage!")
        case "Sorcerer": d = jsRound(Double(d) * 1.20)
        case "Wizard" where dice.chance(0.20):
            d *= 3
            log.append("⚡ Arcane Surge — triple damage!")
        case "ShadowMage" where CoinShop.isNightNow(): d = jsRound(Double(d) * 1.25)
        default: break
        }
        return d
    }

    /// +15%, then 5% more a floor from floor 4 (1 + floor × 5%).
    static func dragonbornMult(_ run: Run) -> Double { max(1.15, 1 + Double(run.floor) * 0.05) }

    /// Iron Body: below 30% HP your defense counts twice.
    static func defense(_ run: Run) -> Int {
        on(run, "Monk") && Double(run.hp) < Double(run.maxHp) * 0.30 ? run.totalDef : 0
    }

    /// Bard charms (15%), Monks dodge (10%), Void Walkers phase (15%).
    static func avoids(_ run: Run, _ e: Enemy, dice: inout some Dice, log: inout [String]) -> Bool {
        guard run.classTraits else { return false }
        switch run.cls {
        case "Bard" where dice.chance(0.15):
            log.append("🎵 Bard's Charm — \(e.name) is enchanted and skips their attack!")
        case "Monk" where dice.chance(0.10):
            log.append("🥷 Monk dodges the attack completely!")
        case "VoidWalker" where dice.chance(0.15):
            log.append("🌀 Void Touched — you phase through \(e.name)'s attack!")
        default: return false
        }
        return true
    }

    /// A risen enemy strikes beside you.
    static func allyAttack(_ run: inout Run, dice: inout some Dice, log: inout [String]) {
        guard let ally = run.fight.ally, var e = run.enemy, !e.isDead else { return }
        let d = dice.roll(ally.atk)
        e.hp = max(0, e.hp - d)
        run.enemy = e
        log.append("💀 The risen \(ally.name) strikes \(e.name) for \(d).")
    }

    /// Kill heals, and the Necromancer's dead rising. Returns notes for the kill message.
    static func onKill(_ run: inout Run, _ e: Enemy, dice: inout some Dice) -> String {
        guard run.classTraits, run.hp > 0 else { return "" }
        var notes = ""
        func heal(_ n: Int, _ text: String) {
            let h = min(n, run.maxHp - run.hp)
            guard h > 0 else { return }
            run.hp += h
            notes += " \(text) +\(h) HP."
        }
        switch run.cls {
        case "Necromancer":
            heal(5, "💀 Necromancer feeds:")
            if !e.isBoss && dice.chance(0.15) {
                var risen = e
                risen.hp = risen.maxHp
                run.raised = risen
                notes += " 💀 Death Follows — \(e.name) will rise to serve you next fight."
            }
        case "Warlock": heal(5, "Soul Drain:")
        case "BloodKnight":
            heal(5, "Blood Harvest:")
            if e.isBoss { heal(jsRound(Double(run.maxHp) * 0.08), "🩸 BloodKnight absorbs the boss power:") }
        default: break
        }
        return notes
    }

    /// A new floor (applyTraitPerFloor and advanceFloor's class heals).
    public static func onFloor(_ run: inout Run) -> [String] {
        guard run.classTraits else { return [] }
        var lines: [String] = []
        switch run.cls {
        case "Warrior" where run.floor % 3 == 0:
            run.atkBonus += 1
            lines.append("⚔ Battle Hardened — +1 attack.")
        case "BloodKnight":
            run.hp = max(1, run.hp - 2)
            lines.append("🩸 Blood Harvest — minus 2 HP this floor.")
        case "Druid":
            let h = jsRound(Double(run.maxHp) * 0.03)
            run.hp = min(run.maxHp, run.hp + h)
            lines.append("🌿 Nature's Bond — +\(h) HP.")
        case "Cleric" where run.floor > 1 && run.floor % 5 == 0:
            let h = jsRound(Double(run.maxHp) * 0.05)
            run.hp = min(run.maxHp, run.hp + h)
            lines.append("🙏 Cleric's Prayer — +\(h) HP restored.")
        default: break
        }
        return lines
    }

    /// A new room: Druids heal 3 HP in The Hollow. (The web version did this
    /// once a floor, not every room as the trait says.)
    public static func onRoom(_ run: inout Run) -> String? {
        guard on(run, "Druid"), run.dungeon == "The Hollow", run.hp < run.maxHp else { return nil }
        run.hp = min(run.maxHp, run.hp + 3)
        return "🌿 Nature's Bond — +3 HP."
    }

    /// Berserkers cannot flee.
    public static func canFlee(_ run: Run) -> Bool { !on(run, "Berserker") }

    /// Undying Resolve: once a run, the blow that would end it leaves you at 1 HP.
    static func undying(_ run: inout Run, log: inout [String]) -> Bool {
        guard run.classTraits, run.undyingResolve, run.hp <= 0, run.hardcore || run.lives <= 1 else { return false }
        run.undyingResolve = false
        run.hp = 1
        log.append("💀 Undying Resolve — death refused. You stand at 1 HP. This will not happen again.")
        return true
    }

    /// Sorcerers' skills cost 3 SP less.
    static func skillCostCut(_ run: Run) -> Int { on(run, "Sorcerer") ? 3 : 0 }
    /// Paladin's holy skills hit 20% harder.
    static func skillDamageBonus(_ run: Run) -> Double { on(run, "Paladin") ? 0.20 : 0 }

    /// Spells: the Elementalist's +40% on elemental spells.
    static func spellPower(_ run: Run, _ id: String) -> Double {
        on(run, "Elementalist") && elemental.contains(id) ? 1.4 : 1
    }

    /// Shadow Mages' shadow spells and Time Mages' time spells come back sooner.
    static func cooldown(_ run: Run, _ id: String, _ normal: Int) -> Int {
        if on(run, "ShadowMage") && Spells.shadow.contains(id) { return 0 }
        if on(run, "TimeMage") && time.contains(id) { return normal == Spells.cooldownPowerful ? 3 : 1 }
        return normal
    }

    /// Void Walkers' void spells never fail.
    static func voidSure(_ run: Run, _ id: String) -> Bool { on(run, "VoidWalker") && Spells.void.contains(id) }
}
