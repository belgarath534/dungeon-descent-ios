import Foundation

/// SUBCLASS SYSTEM: at level 5 every class picks one of two paths for the
/// rest of the run. Each gives level points' worth of stats and a passive.
public struct Subclass: Sendable, Identifiable {
    public let id, name, icon, desc, passive: String
    public let stats: [(Progression.Stat, Int)]
    /// The web version's apply() log line.
    public let chosenLine: String
}

public enum Subclasses {
    static func s(_ id: String, _ name: String, _ icon: String, _ desc: String, _ passive: String,
                  _ stats: [(Progression.Stat, Int)], _ line: String) -> Subclass {
        Subclass(id: id, name: name, icon: icon, desc: desc, passive: passive, stats: stats, chosenLine: line)
    }

    /// SUBCLASSES. The web version's "spirit" and "vitality" stats don't exist
    /// as level points, so they gave nothing; here they count as Intelligence
    /// and Stamina.
    public static let all: [String: [Subclass]] = [
        "Warrior": [
            s("warlord", "Warlord", "👑", "Every kill gives +2 ATK for the rest of the floor. Commander energy. Built for momentum.",
              "Kill Streak — +2 ATK per kill, resets each floor.", [(.strength, 2), (.stamina, 1)], "👑 Warlord path chosen. Every kill fuels your strength."),
            s("gladiator", "Gladiator", "⚔️", "+20% crit chance. Critical hits deal 2.5x damage instead of 1.8x. Built for the arena.",
              "Arena Fighter — crits hit harder.", [(.strength, 2), (.agility, 1)], "⚔️ Gladiator path chosen. Your crits are devastating."),
        ],
        "Monk": [
            s("iron-fist", "Iron Fist", "👊", "+20% damage when no weapon equipped. Pure discipline and bare knuckle mastery.",
              "Unarmed Mastery — hits harder without weapons.", [(.strength, 2), (.agility, 1)], "👊 Iron Fist path chosen. Your fists are your weapons."),
            s("wind-walker", "Wind Walker", "💨", "Dodge chance +15%. First attack every combat always crits. Speed is your armor.",
              "Swift Step — dodge hits, strike first.", [(.agility, 3)], "💨 Wind Walker path chosen. You move before they see you."),
        ],
        "Assassin": [
            s("shadow", "Shadow", "🌑", "Guaranteed first strike every combat. First hit always crits. Strike before they know you are there.",
              "Ambush — always strike first for a guaranteed crit.", [(.agility, 2), (.strength, 1)], "🌑 Shadow path chosen. They will never see you coming."),
            s("poisoner", "Poisoner", "🐍", "Every attack applies poison for 4 damage per turn for 3 turns. Stacks with each hit.",
              "Venom — every strike poisons.", [(.agility, 1), (.luck, 2)], "🐍 Poisoner path chosen. Your blade carries death."),
        ],
        "Paladin": [
            s("crusader", "Crusader", "✝️", "+4 DEF permanently. Undead enemies take 50% more damage from all your attacks.",
              "Holy Armor — divine protection against undead.", [(.defense, 2), (.stamina, 1)], "✝️ Crusader path chosen. Your faith is your shield."),
            s("avenger", "Avenger", "🔥", "The lower your HP the harder you hit. At 25% HP you deal double damage.",
              "Last Stand — desperation fuels fury.", [(.strength, 2), (.stamina, 1)], "🔥 Avenger path chosen. Pain makes you stronger."),
        ],
        "Naturalist": [
            s("druid", "Druid", "🌿", "Heal 6 HP every room entered. Nature sustains and restores you constantly.",
              "Natural Healing — the dungeon heals you.", [(.stamina, 2), (.defense, 1)], "🌿 Druid path chosen. Nature heals as you walk."),
            s("beast-caller", "Beast Caller", "🐺", "A random beast companion fights with you every floor. Attacks for 8-14 damage per round.",
              "Beast Bond — an ally joins your fight.", [(.strength, 1), (.stamina, 2)], "🐺 Beast Caller path chosen. The wild answers your call."),
        ],
        "Wizard": [
            s("archmage", "Archmage", "🔮", "+15 max SP. All skills cost 2 less SP. Spell damage +20%. Pure arcane mastery.",
              "Arcane Focus — more SP, cheaper skills, stronger magic.", [(.intelligence, 3)], "🔮 Archmage path chosen. Your arcane power is immense."),
            s("spellblade", "Spellblade", "⚡", "Melee attacks deal bonus arcane damage equal to your current SP divided by 10.",
              "Arcane Strike — your weapon channels magic.", [(.strength, 1), (.intelligence, 2)], "⚡ Spellblade path chosen. Steel and sorcery combined."),
        ],
        "Ranger": [
            s("hawkeye", "Hawkeye", "🎯", "Heavy Strike never misses. Precision training eliminates the miss chance entirely.",
              "Perfect Aim — Heavy Strike is now reliable.", [(.agility, 2), (.strength, 1)], "🎯 Hawkeye path chosen. Every shot finds its mark."),
            s("trapper", "Trapper", "🪤", "30% chance to stun any enemy on the first hit every combat for 1 turn.",
              "Set the Trap — first hit may stun.", [(.agility, 2), (.luck, 1)], "🪤 Trapper path chosen. Control the fight from the start."),
        ],
        "Necromancer": [
            s("death-knight-sub", "Death Knight", "💀", "Become undead. Immune to poison. Heal 10 HP per kill. Death feeds your power.",
              "Undead Form — heal from death.", [(.stamina, 2), (.defense, 1)], "💀 Death Knight path chosen. You have become death."),
            s("soul-reaper", "Soul Reaper", "🌀", "Steal 1 random skill from every elite or boss you defeat. Collect their power.",
              "Soul Harvest — take what they have.", [(.intelligence, 2), (.luck, 1)], "🌀 Soul Reaper path chosen. Their power becomes yours."),
        ],
        "Sorcerer": [
            s("wildfire", "Wildfire", "🔥", "Every attack has 25% chance to explode for double damage. Chaos fuels your magic.",
              "Wild Surge — magic has a mind of its own.", [(.strength, 1), (.intelligence, 2)], "🔥 Wildfire path chosen. Your magic is gloriously unpredictable."),
            s("elementalist", "Elementalist", "🌊", "+15% damage to all skills. Enemies weak to your element take an extra 25% damage.",
              "Elemental Mastery — elements obey you.", [(.intelligence, 3)], "🌊 Elementalist path chosen. The elements are yours to command."),
        ],
        "Warlock": [
            s("pact-keeper", "Pact Keeper", "📜", "Your patron strengthens you. +5 ATK and +5 DEF as flat permanent bonuses.",
              "Dark Pact — power at a price already paid.", [(.strength, 2), (.defense, 1)], "📜 Pact Keeper path chosen. Your patron is pleased."),
            s("hex-blade", "Hex Blade", "🖤", "Curse enemies on hit. Cursed enemies take +35% damage from all sources for 3 turns.",
              "Hex — every hit curses.", [(.agility, 1), (.intelligence, 2)], "🖤 Hex Blade path chosen. Your strikes carry a curse."),
        ],
        "Sentinel": [
            s("ironclad", "Ironclad", "🛡️", "Maximum 12 damage per hit no matter what. Nothing breaks through your armor.",
              "Iron Defense — damage is capped.", [(.defense, 3)], "🛡️ Ironclad path chosen. Nothing can break you."),
            s("bulwark", "Bulwark", "⚔️", "Defending reflects 30% of damage back to the attacker. Your shield is a weapon.",
              "Shield Bash — defense is offense.", [(.defense, 2), (.strength, 1)], "⚔️ Bulwark path chosen. Your shield strikes back."),
        ],
        "Dragonborn": [
            s("dragon-ascendant", "Dragon Ascendant", "🐉", "Flame breath triggers on every attack. 20% chance to burn for 8 damage per turn.",
              "Ancient Fire — flames follow every strike.", [(.strength, 2), (.stamina, 1)], "🐉 Dragon Ascendant path chosen. Your blood burns."),
            s("ancient-blood", "Ancient Blood", "🌟", "+25 max HP. Completely immune to fire damage. Your heritage protects you.",
              "Dragon Blood — fire cannot touch you.", [(.stamina, 3)], "🌟 Ancient Blood path chosen. Your heritage awakens."),
        ],
        "Alchemist": [
            s("brewmaster", "Brewmaster", "⚗️", "Potions heal double. You start every dungeon with 2 extra potions. Never run dry.",
              "Master Brewer — potions are your specialty.", [(.stamina, 2), (.luck, 1)], "⚗️ Brewmaster path chosen. Your potions are twice as potent."),
            s("bomb-thrower", "Bomb Thrower", "💣", "Once per floor throw a bomb dealing 60 unblockable damage. Recharges each floor.",
              "Explosive Expert — one bomb per floor.", [(.strength, 1), (.intelligence, 2)], "💣 Bomb Thrower path chosen. Handle with care."),
        ],
        "DeathKnight": [
            s("plague-bearer", "Plague Bearer", "☠️", "Your attacks have 25% chance to spread disease. Diseased enemies take 5 damage per turn.",
              "Pestilence — disease spreads from your touch.", [(.intelligence, 1), (.luck, 2)], "☠️ Plague Bearer path chosen. Disease is your weapon."),
            s("undying", "Undying", "💜", "When you would die, survive at 1 HP once per dungeon. Death refuses you.",
              "Deathless — one free revival per run.", [(.stamina, 2), (.defense, 1)], "💜 Undying path chosen. You cannot be killed easily."),
        ],
        "Bard": [
            s("battle-hymn", "Battle Hymn", "🎵", "Your songs empower your attacks. +5 ATK for 3 turns after every skill use.",
              "War Song — skills fuel combat power.", [(.strength, 2), (.intelligence, 1)], "🎵 Battle Hymn path chosen. Your song is a weapon."),
            s("trickster-bard", "Trickster", "🎭", "25% chance any enemy attack misses due to distraction. You are impossible to pin down.",
              "Distraction — they cannot focus on you.", [(.agility, 2), (.luck, 1)], "🎭 Trickster path chosen. Confusion is your armor."),
        ],
        "Cleric": [
            s("high-priest", "High Priest", "✨", "Divine protection. Take 20% less damage from all sources. Faith shields you.",
              "Divine Shield — faith reduces all damage.", [(.defense, 2), (.stamina, 1)], "✨ High Priest path chosen. Your faith is your armor."),
            s("smiter", "Smiter", "⚡", "Every 3rd attack deals bonus holy damage equal to your level times 3.",
              "Holy Smite — divine power surges every third strike.", [(.strength, 2), (.intelligence, 1)], "⚡ Smiter path chosen. Holy power flows through your strikes."),
        ],
        "BloodKnight": [
            s("vampire-lord", "Vampire Lord", "🩸", "Heal 20% of all damage dealt. The more you hit the more you heal.",
              "Life Drain — combat heals you.", [(.stamina, 2), (.strength, 1)], "🩸 Vampire Lord path chosen. Every strike heals you."),
            s("berserker-sub", "Berserker", "💢", "The more HP you lose the more damage you deal. No cap. Pure rage.",
              "Berserk Rage — pain is power.", [(.strength, 3)], "💢 Berserker path chosen. Pain makes you stronger."),
        ],
        "Elementalist": [
            s("firelord", "Firelord", "🔥", "Fire spells deal +60% damage. Enemies you kill with fire leave burning ground that damages the next enemy.",
              "Flame Mastery — fire spells devastate.", [(.intelligence, 3), (.strength, 1)], "🔥 Firelord path chosen. Everything burns."),
            s("stormcaller", "Stormcaller", "⚡", "Lightning spells chain to nearby enemies for 40% damage. Ice spells freeze enemies for 1 extra turn.",
              "Storm Command — spells chain and freeze.", [(.intelligence, 2), (.agility, 2)], "⚡ Stormcaller path chosen. You command the storm."),
        ],
        "VoidWalker": [
            s("void-born", "Void Born", "🌑", "Start each run with 3 Void spell scrolls. Void spells deal +50% damage to spirit enemies.",
              "Born of Nothing — void is your home.", [(.intelligence, 3), (.agility, 1)], "🌑 Void Born path chosen. You came from nothing."),
            s("shadow-step", "Phase Walker", "👁️", "20% chance to phase through any attack completely. Void spells have no cooldown on floors 8-10.",
              "Phase Step — reality bends for you.", [(.agility, 2), (.intelligence, 2)], "👁️ Phase Walker path chosen. You exist between moments."),
        ],
        "ShadowMage": [
            s("dark-arts", "Dark Arts", "🖤", "Shadow spells apply a stacking curse. Each curse reduces enemy ATK by 5. Max 5 stacks.",
              "Cursed Touch — shadows weaken all they touch.", [(.intelligence, 2), (.agility, 2)], "🖤 Dark Arts path chosen. Shadows obey you."),
            s("night-shroud", "Night Shroud", "🌒", "During Night Mode all your attacks deal +35% damage. Shadow spells cost 0 turns to cooldown at night.",
              "Child of Night — darkness is your power.", [(.agility, 3), (.intelligence, 1)], "🌒 Night Shroud path chosen. You thrive in darkness."),
        ],
        "TimeMage": [
            s("time-lord", "Time Lord", "⏰", "Time Stop and Time Fracture always succeed — no percentage roll. You have mastered time completely.",
              "Temporal Mastery — time obeys you.", [(.intelligence, 3), (.stamina, 1)], "⏰ Time Lord path chosen. Time bends to your will."),
            s("paradox", "Paradox", "🔄", "When you die you rewind 1 turn. Once per combat. The paradox saves you from death itself.",
              "Temporal Paradox — death is not the end.", [(.intelligence, 2), (.stamina, 2)], "🔄 Paradox path chosen. Death is merely a suggestion."),
        ],
        "Shaman": [
            s("earthbound", "Earthbound", "🌍", "Earthshake deals +80% damage and always buffs you. Stone enemies take double damage from all your attacks.",
              "Earth Mastery — the ground answers your call.", [(.strength, 2), (.defense, 2)], "🌍 Earthbound path chosen. The earth is your weapon."),
            s("spirit-caller", "Spirit Caller", "🌀", "Summon a spirit companion at the start of each dungeon. It heals you for 8 HP per turn passively.",
              "Spirit Bond — a healer walks beside you.", [(.intelligence, 2), (.stamina, 2)], "🌀 Spirit Caller path chosen. Spirits answer your call."),
        ],
        "Arcanist": [
            s("pure-magic", "Pure Magic", "✨", "All spells cast at 150% effectiveness. No class penalty ever. The purest magic user alive.",
              "Arcane Perfection — magic flows through you perfectly.", [(.intelligence, 4)], "✨ Pure Magic path chosen. You are magic incarnate."),
            s("spell-weaver", "Spell Weaver", "🔮", "Can cast 2 spells before cooldown triggers instead of 1. Spell scrolls never fail to learn.",
              "Weave the Arcane — two spells, one breath.", [(.intelligence, 3), (.agility, 1)], "🔮 Spell Weaver path chosen. Two spells flow as one."),
        ],
    ]

    /// Passives that work through spells (Arcane Shop scrolls), which the
    /// Swift version doesn't have yet. Their stat bonuses still apply.
    public static let waitingOnSpells: Set<String> = ["firelord", "stormcaller", "void-born", "dark-arts", "time-lord", "pure-magic", "spell-weaver"]

    static let beasts = [("🐺", "wolf"), ("🐻", "bear"), ("🦅", "hawk"), ("🐗", "boar"), ("🐆", "panther")]

    public static func options(for cls: String) -> [Subclass] { all[cls] ?? [] }

    public static func current(_ run: Run) -> Subclass? {
        guard let id = run.subclass else { return nil }
        return options(for: run.cls).first { $0.id == id }
    }

    /// The level 5 choice is waiting.
    public static func pending(_ run: Run) -> Bool {
        run.level >= 5 && run.subclass == nil && !options(for: run.cls).isEmpty
    }

    static func has(_ run: Run, _ id: String) -> Bool { run.subclass == id }

    /// chooseSubclass: stat points, then the path's own bonus.
    public static func choose(_ run: inout Run, _ id: String) -> [String] {
        guard run.subclass == nil, let sub = options(for: run.cls).first(where: { $0.id == id }) else { return [] }
        run.subclass = sub.id
        for (stat, pts) in sub.stats {
            for _ in 0..<pts {
                run.levelPoints += 1
                Progression.spend(&run, on: stat)
            }
        }
        switch sub.id {
        case "gladiator": run.critBonus += 0.20
        case "wind-walker": run.critBonus += 0.10
        case "crusader": run.defBonus += 4
        case "archmage": run.maxSp += 15; run.sp = min(run.maxSp, run.sp + 15)
        case "pact-keeper": run.atkBonus += 5; run.defBonus += 5
        case "ancient-blood": run.maxHp += 25; run.hp = min(run.maxHp, run.hp + 25)
        case "brewmaster":
            run.potionMult *= 2
            for _ in 0..<2 { run.inventory.append(Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "Restores 40 HP.", heal: 40)) }
        case "bomb-thrower": run.bombReady = true
        case "beast-caller": run.beast = 0
        default: break
        }
        var log = [sub.chosenLine]
        if waitingOnSpells.contains(sub.id) { log.append("Spells aren't in the Swift version yet, so this passive waits for them. Coming soon.") }
        log.append("\(sub.icon) Subclass chosen: \(sub.name). \(sub.passive)")
        return log
    }

    // MARK: Combat hooks

    /// Subclass passives on your attack roll (doFight).
    static func attackBonus(_ run: inout Run, _ base: Int, dice: inout some Dice, log: inout [String]) -> Int {
        guard run.subclass != nil else { return base }
        var a = base
        if has(run, "iron-fist") && run.equippedWeapon == nil { a = jsRound(Double(a) * 1.20) }
        if has(run, "avenger") && Double(run.hp) <= Double(run.maxHp) * 0.25 { a = jsRound(Double(a) * 2.0) }
        if has(run, "wildfire") && dice.chance(0.25) { a = jsRound(Double(a) * 2.0); log.append("🔥 Wild Surge! Double damage!") }
        if has(run, "berserker-sub") { a += (run.maxHp - run.hp) / 10 }
        if has(run, "spellblade") { a += run.sp / 10 }
        if has(run, "battle-hymn") && run.battleHymnTurns > 0 { a += 5; run.battleHymnTurns -= 1 }
        if has(run, "night-shroud") && CoinShop.isNightNow() { a = jsRound(Double(a) * 1.35) }
        if has(run, "warlord") { a += run.warlordAtk }
        return a
    }

    /// Wind Walker and Shadow: the first attack of every fight is a crit.
    static func firstStrikeCrit(_ run: inout Run) -> Bool {
        guard has(run, "wind-walker") || has(run, "shadow"), !run.fight.subFirstStrike else { return false }
        run.fight.subFirstStrike = true
        return true
    }

    static func critMultiplier(_ run: Run) -> Double { has(run, "gladiator") ? 2.5 : 1.8 }

    /// Damage added after the hit is rolled: Smiter's every-third-attack
    /// smite and Crusader's +50% against the undead.
    static func afterRoll(_ run: inout Run, _ dmg: Int, log: inout [String]) -> Int {
        var d = dmg
        if has(run, "smiter") {
            run.smiterCount += 1
            if run.smiterCount >= 3 {
                run.smiterCount = 0
                d += run.level * 3
                log.append("⚡ Holy Smite! +\(run.level * 3) holy damage!")
            }
        }
        if has(run, "crusader"), let e = run.enemy, Bestiary.undeadNames.contains(e.name) { d = jsRound(Double(d) * 1.5) }
        return d
    }

    /// On-hit passives once your attack lands.
    static func onHit(_ run: inout Run, _ dmg: Int, dice: inout some Dice, log: inout [String]) {
        guard dmg > 0, run.subclass != nil, var e = run.enemy, !e.isDead else { return }
        func dot(_ d: Int, stack: Bool) {
            e.dotDamage = stack && e.dotTurns > 0 ? min(20, e.dotDamage + d) : max(d, e.dotTurns > 0 ? e.dotDamage : 0)
            e.dotTurns = 3
        }
        switch run.subclass {
        case "poisoner": dot(4, stack: true); log.append("🐍 \(e.name) is poisoned!")
        case "dragon-ascendant" where dice.chance(0.20): dot(8, stack: false); log.append("🐉 Flame breath! \(e.name) is burning!")
        case "plague-bearer" where dice.chance(0.25): dot(5, stack: false); log.append("☠️ \(e.name) is diseased!")
        case "hex-blade":
            run.fight.vulnerable = max(run.fight.vulnerable, 0.35)
            run.fight.vulnerableTurns = 3
        case "trapper" where !run.fight.subFirstStrike:
            run.fight.subFirstStrike = true
            if dice.chance(0.30) { e.stunTurns = max(e.stunTurns, 1); log.append("🪤 Trap sprung! \(e.name) is stunned!") }
        case "vampire-lord":
            let heal = max(1, dmg / 5)
            run.hp = min(run.maxHp, run.hp + heal)
        default: break
        }
        run.enemy = e
    }

    /// Beast Caller's beast joins every round.
    static func companionAttack(_ run: inout Run, dice: inout some Dice, log: inout [String]) {
        guard has(run, "beast-caller"), var e = run.enemy, !e.isDead else { return }
        let b = beasts[run.beast % beasts.count]
        let dmg = dice.roll(8...14)
        e.hp = max(0, e.hp - dmg)
        run.enemy = e
        log.append("\(b.0) Your \(b.1) attacks for \(dmg) damage!")
    }

    /// Damage you take: High Priest, Ironclad, Trickster, Wind Walker and
    /// Phase Walker dodges, and Bulwark's reflection while defending.
    static func incoming(_ run: inout Run, _ taken: Int, dice: inout some Dice, log: inout [String]) -> Int {
        guard taken > 0, run.subclass != nil else { return taken }
        var t = taken
        if has(run, "high-priest") { t = jsRound(Double(t) * 0.80) }
        if has(run, "ironclad") { t = min(t, 12) }
        if has(run, "trickster-bard") && dice.chance(0.25) { log.append("🎭 Distracted! Enemy misses!"); return 0 }
        if has(run, "wind-walker") && dice.chance(0.15) { log.append("💨 You dodge the attack!"); return 0 }
        if has(run, "shadow-step") && dice.chance(0.20) { log.append("👁️ You phase through the attack!"); return 0 }
        if has(run, "bulwark") && run.defending, var e = run.enemy {
            let back = jsRound(Double(t) * 0.30)
            if back > 0 {
                e.hp = max(0, e.hp - back)
                run.enemy = e
                log.append("⚔️ Bulwark reflects \(back) damage!")
            }
        }
        return t
    }

    /// Kills: Warlord's streak, Soul Reaper's stolen skill, Death Knight's heal.
    static func onKill(_ run: inout Run, _ enemy: Enemy, log: inout [String]) {
        switch run.subclass {
        case "warlord":
            run.warlordAtk += 2
            log.append("👑 Warlord: +2 ATK from kill streak!")
        case "soul-reaper" where enemy.isElite || enemy.isBoss:
            if let i = run.skillPool.firstIndex(where: { !run.unlockedSkills.contains($0) }) {
                let stolen = run.skillPool.remove(at: i)
                run.unlockedSkills.append(stolen)
                log.append("🌀 Soul Reaper: Stole \(Skills.skill(stolen, cls: run.cls)?.name ?? stolen)!")
            }
        case "death-knight-sub":
            run.hp = min(run.maxHp, run.hp + 10)
            log.append("💀 Death feeds you — +10 HP.")
        default: break
        }
    }

    /// Undying (once per run) and Paradox (once per fight, back to the HP you
    /// had before the blow).
    static func cheatDeath(_ run: inout Run, hpBefore: Int, log: inout [String]) -> Bool {
        if has(run, "undying") && !run.undyingUsed {
            run.undyingUsed = true
            run.hp = 1
            log.append("💜 Undying! Death refused you — you survive at 1 HP!")
            return true
        }
        if has(run, "paradox") && !run.fight.paradoxUsed {
            run.fight.paradoxUsed = true
            run.hp = max(1, hpBefore)
            log.append("🔄 Paradox! Time rewinds one turn — death never happened.")
            return true
        }
        return false
    }

    /// Spirit Caller's spirit heals 8 HP each turn of a fight.
    static func turnHeal(_ run: inout Run, log: inout [String]) {
        guard has(run, "spirit-caller"), run.inCombat, run.hp > 0, run.hp < run.maxHp else { return }
        run.hp = min(run.maxHp, run.hp + 8)
        log.append("🌀 Your spirit heals you for 8 HP.")
    }

    /// enterRoom: the Druid heals 6 HP.
    public static func onRoom(_ run: inout Run) -> String? {
        guard has(run, "druid"), run.hp < run.maxHp else { return nil }
        run.hp = min(run.maxHp, run.hp + 6)
        return "🌿 Nature heals you for 6 HP."
    }

    /// A new floor: the Warlord's streak resets, the bomb recharges and a new
    /// beast answers the call.
    public static func onFloor(_ run: inout Run, dice: inout some Dice) -> String? {
        switch run.subclass {
        case "warlord": run.warlordAtk = 0
        case "bomb-thrower": run.bombReady = true; return "💣 Your bomb is ready."
        case "beast-caller":
            run.beast = dice.roll(0...(beasts.count - 1))
            let b = beasts[run.beast]
            return "\(b.0) A \(b.1) answers your call and joins you on this floor."
        default: break
        }
        return nil
    }

    /// Skill hooks: Archmage skills cost 2 less; Archmage +20% and
    /// Elementalist +15% skill damage.
    static func skillCostCut(_ run: Run) -> Int { has(run, "archmage") ? 2 : 0 }

    static func skillDamageBonus(_ run: Run) -> Double {
        has(run, "archmage") ? 0.20 : has(run, "elementalist") ? 0.15 : 0
    }

    public static func canBomb(_ run: Run) -> Bool {
        run.subclass == "bomb-thrower" && run.bombReady && run.inCombat && run.enemy != nil
    }
}
