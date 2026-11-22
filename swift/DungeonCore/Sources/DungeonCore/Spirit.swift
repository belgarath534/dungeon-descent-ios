import Foundation

/// SPIRIT COMPANION SYSTEM: the spirit you pick when you create a character
/// (or switch to from the pause menu) fights, guards or loots beside you.
public struct Spirit: Sendable, Identifiable {
    public let id, name, icon, rarity, desc, ability, passive: String
    /// The level it wakes at: 5 for rare spirits, 7 for the Void Herald.
    public let minLevel: Int
    /// Share of your attack roll it strikes for after your attack (0 = none).
    public let strike: Double
    /// A spirit you forged: its ability (CustomSpirits.abilities).
    public var customAbility: String? = nil
}

public enum Spirits {
    static func s(_ id: String, _ name: String, _ icon: String, _ rarity: String, _ desc: String, _ ability: String,
                  _ passive: String, minLevel: Int = 0, strike: Double = 0) -> Spirit {
        Spirit(id: id, name: name, icon: icon, rarity: rarity, desc: desc, ability: ability, passive: passive,
               minLevel: minLevel > 0 ? minLevel : (rarity == "rare" ? 5 : 1), strike: strike)
    }

    /// STARTER_SPIRITS, RARE_SPIRITS and ELITE_SPIRITS.
    public static let all: [Spirit] = [
        s("ember-fox", "Ember Fox", "🦊", "starter", "A fox wreathed in embers. Attacks with you every turn.",
          "Attacks each turn for 15% of your base attack as fire damage.", "Fire Strike", strike: 0.15),
        s("bone-hound", "Bone Hound", "🦴", "starter", "An undead hound bound to your will. Stronger against undead.",
          "Attacks for 20% base damage. +10% bonus vs undead enemies.", "Undead Hunter", strike: 0.20),
        s("frost-sprite", "Frost Sprite", "❄️", "starter", "A tiny ice spirit. Slows enemies and detects traps.",
          "At combat start reduces enemy attack 10% for 3 turns. Detects traps.", "Frost Aura"),
        s("shadow-crow", "Shadow Crow", "🐦", "starter", "A shadowy crow that steals gold from fallen enemies.",
          "Each kill grants +3 bonus gold stolen by the crow.", "Gold Thief"),
        s("stone-turtle", "Stone Turtle", "🐢", "starter", "Ancient and unbreakable. Absorbs the first hit of every combat.",
          "At combat start creates a shell absorbing up to 15 damage.", "Shell Guard"),
        s("thunder-moth", "Thunder Moth", "🦋", "starter", "A moth charged with static. Has a chance to stun on attack.",
          "Each attack has a 20% chance to stun the enemy for 1 turn.", "Static Shock", strike: 0.12),
        s("market-sprite", "Market Sprite", "🪙", "starter", "A spirit bound to commerce. Negotiates on your behalf at every shop.",
          "All shop items cost 20% less this run. Costs 50 gold to reactivate next run.", "Merchant Aura"),
        s("bone-hound-prime", "Bone Hound Prime", "💀", "rare", "The alpha undead hound. Drains SP from fallen enemies.",
          "Attacks for 25% damage each turn. On kill steals 5 SP.", "Soul Drain", strike: 0.25),
        s("inferno-hawk", "Inferno Hawk", "🦅", "rare", "A hawk born from Vel Ashara's eternal fire.",
          "Attacks every turn for 30% fire damage. Burns enemy on combat start.", "Eternal Flame", strike: 0.30),
        s("glacial-wolf", "Glacial Wolf", "🐺", "rare", "A wolf of ancient ice. Freezes enemies and grants defense.",
          "At combat start grants +4 defense. Attacks for 20% damage, may freeze.", "Arctic Guard", strike: 0.20),
        s("void-wraith", "Void Wraith", "👁️", "rare", "A wraith from beyond reality. Drains life to heal you.",
          "Attacks for 35% damage each turn. Steals 8 HP from enemy on each hit.", "Life Drain Aura", strike: 0.35),
        s("crystal-serpent", "Crystal Serpent", "🐍", "rare", "A serpent of living ice. Poisons enemies with frost venom.",
          "At combat start applies 4-turn frost poison. Attacks for 18% damage.", "Frost Venom", strike: 0.18),
        s("ash-phoenix", "Ash Phoenix", "🔥", "rare", "Reborn from Vel Ashara's fire. Restores HP when you kill.",
          "Each kill restores 12 HP. Attacks for 22% fire damage.", "Phoenix Fire", strike: 0.22),
        s("shadow-stalker", "Shadow Stalker", "🕷️", "rare", "A spider of pure shadow. Weakens enemies on combat start.",
          "At combat start reduces enemy attack by 20%. Attacks for 15% damage.", "Web of Weakness", strike: 0.15),
        s("grave-hound", "Grave Hound", "🐕", "rare", "A spirit hound from the Hollow. Guards you and strikes hard.",
          "Attacks for 25% damage. At combat start reduces enemy attack by 15%.", "Guardian Growl", strike: 0.25),
        s("the-lantern", "The Lantern", "🏮", "starter", "A warm light that guides and protects. Reveals traps and rewards exploration.",
          "Detects traps like Frost Sprite. Each kill grants +5 gold.", "Guiding Light"),
        s("medusa-spirit", "Medusa", "🐍", "elite", "Found at last. She guards those who showed her mercy.",
          "Serpent Guard — absorbs one enemy attack per combat.", "Serpent Guard"),
        s("easter-bunny", "Easter Bunny", "🐰", "starter", "A spirit companion found only during Easter. Hops alongside you and finds hidden treats.",
          "Each kill has a 20% chance to find an Easter Egg that restores 10 HP.", "Egg Hunt"),
        s("void-moth", "Void Moth", "🦋", "rare", "A moth of pure void. Attacks relentlessly and sometimes negates damage.",
          "Attacks for 35% damage. 15% chance to negate incoming damage each hit.", "Void Wings", strike: 0.35),
        s("death-knight-spirit", "Knight Shade", "⚔️", "elite", "The spirit of a fallen Death Knight. Powerful and relentless.",
          "Attacks for 30% damage every turn. On kill restores 5 HP.", "Undying Fury", strike: 0.30),
        s("ash-titan-spirit", "Titan Ember", "🔥", "elite", "The essence of an Ash Titan. Burns with eternal fury.",
          "At combat start applies 3-turn burn. Attacks for 25% fire damage.", "Titan Flame", strike: 0.25),
        s("frost-sovereign-spirit", "Frost Crown", "❄️", "elite", "A crown of living ice from the Frost Sovereign.",
          "Grants +5 defense at combat start. Attacks for 20% ice damage.", "Ice Dominion", strike: 0.20),
        s("archivist-spirit", "Archive Phantom", "📜", "elite", "The ghost of a drowned archivist. Knows every weakness.",
          "Attacks for 28% damage. Each hit reduces enemy defense by 1.", "Exposed Knowledge", strike: 0.28),
        s("void-champion-spirit", "Void Herald", "🌑", "elite", "A fragment of the Void Champion. Terrifyingly powerful.",
          "Attacks for 40% damage every turn. Requires level 7.", "Void Strike", minLevel: 7, strike: 0.40),
    ]

    public static let eliteIds = ["death-knight-spirit", "ash-titan-spirit", "frost-sovereign-spirit", "archivist-spirit", "void-champion-spirit"]

    public static func spirit(_ id: String?) -> Spirit? { id.flatMap { i in all.first { $0.id == i } ?? CustomSpirits.loaded.first { $0.id == i } } }

    public static func current(_ run: Run) -> Spirit? { spirit(run.spirit) }

    /// The spirit is awake at your level (rare spirits sleep until level 5).
    public static func awake(_ run: Run) -> Spirit? {
        guard let sp = current(run), run.level >= sp.minLevel else { return nil }
        return sp
    }

    /// The spirits a character can pick: every starter plus those earned.
    public static func available(earned: Set<String>) -> [Spirit] {
        all.filter { starterIds.contains($0.id) || earned.contains($0.id) } + CustomSpirits.loaded
    }

    /// The seven spirits every character can pick from the start.
    public static let starterIds: Set<String> = ["ember-fox", "bone-hound", "frost-sprite", "shadow-crow", "stone-turtle", "thunder-moth", "market-sprite"]

    // MARK: Combat hooks

    /// applySpiritOnCombatStart
    static func combatStart(_ run: inout Run, log: inout [String]) {
        guard let sp = awake(run), var e = run.enemy else { return }
        if sp.customAbility != nil {
            CustomSpirits.combatStart(&run, e: &e, log: &log)
            run.enemy = e
            return
        }
        func weaken(_ m: Double) {
            let lo = jsRound(Double(e.atk.lowerBound) * m), hi = jsRound(Double(e.atk.upperBound) * m)
            e.atk = lo...max(lo, hi)
        }
        func burn(_ turns: Int) { e.dotDamage = max(e.dotDamage, 8); e.dotTurns = max(e.dotTurns, turns) }
        switch sp.id {
        case "frost-sprite":
            run.fight.soften = min(run.fight.soften, 0.90)
            run.fight.softenHits = max(run.fight.softenHits, 3)
            log.append("Frost Sprite chills the air — enemy attack reduced for 3 turns.")
        case "stone-turtle":
            run.fight.shield = max(run.fight.shield, 15)
            log.append("Stone Turtle raises its shell — absorbs up to 15 damage!")
        case "inferno-hawk": burn(2); log.append("Inferno Hawk ignites the enemy — burning for 2 turns!")
        case "crystal-serpent": burn(4); log.append("Crystal Serpent injects frost venom — 4 turn poison!")
        case "ash-titan-spirit": burn(3); log.append("Titan Ember ignites the enemy — burning!")
        case "glacial-wolf": run.fight.def += 4; log.append("Glacial Wolf surrounds you in ice armor. +4 defense!")
        case "frost-sovereign-spirit": run.fight.def += 5; log.append("Frost Crown hardens your defenses. +5 defense!")
        case "shadow-stalker": weaken(0.80); log.append("Shadow Stalker webs the enemy — attack reduced 20%!")
        case "grave-hound": weaken(0.85); log.append("Grave Hound growls — enemy attack reduced 15%!")
        case "medusa-spirit": run.fight.medusaGuard = true; log.append("🐍 Medusa: Serpent Guard active.")
        default: break
        }
        run.enemy = e
    }

    /// applySpiritOnAttack: after your attack, if the enemy is still up.
    static func attack(_ run: inout Run, base: Int, dice: inout some Dice, log: inout [String]) {
        if let sp = awake(run), sp.customAbility != nil, var e = run.enemy, !e.isDead {
            CustomSpirits.attack(&run, e: &e, base: base, dice: &dice, log: &log)
            run.enemy = e
            return
        }
        guard let sp = current(run), sp.strike > 0, var e = run.enemy, !e.isDead else { return }
        guard run.level >= sp.minLevel else {
            log.append("\(sp.name) dormant — reach level \(sp.minLevel) to awaken.")
            return
        }
        var share = sp.strike
        if sp.id == "bone-hound" && Bestiary.undeadNames.contains(e.name) { share += 0.10 }
        let dmg = jsRound(Double(base) * share) * (run.spiritBoost ? 2 : 1)
        switch sp.id {
        case "thunder-moth" where dice.chance(0.20):
            e.stunTurns = max(e.stunTurns, 1)
            log.append("Thunder Moth shocks the enemy — stunned!")
        case "glacial-wolf" where dice.chance(0.25):
            e.stunTurns = max(e.stunTurns, 1)
            log.append("Glacial Wolf freezes the enemy!")
        case "void-wraith":
            run.hp = min(run.maxHp, run.hp + 8)
            log.append("Void Wraith drains 8 HP!")
        case "archivist-spirit":
            e.atk = max(1, e.atk.lowerBound - 1)...max(1, e.atk.upperBound - 1)
        default: break
        }
        if dmg > 0 {
            e.hp = max(0, e.hp - dmg)
            log.append("\(sp.icon) \(sp.name) strikes for \(dmg)!")
        }
        run.enemy = e
    }

    /// Medusa's Serpent Guard and the Void Moth's wings, against a hit.
    static func guards(_ run: inout Run, dice: inout some Dice, log: inout [String]) -> Bool {
        // Medusa walking with you this run (the Medusa arc) guards like her spirit.
        if Medusa.walksWithYou(run) && run.fight.medusaGuard {
            run.fight.medusaGuard = false
            log.append("🐍 Medusa intercepts the attack! Serpent Guard blocks the hit.")
            return true
        }
        guard let sp = awake(run) else { return false }
        if CustomSpirits.blocks(run, dice: &dice, log: &log) { return true }
        if sp.id == "medusa-spirit" && run.fight.medusaGuard {
            run.fight.medusaGuard = false
            log.append("🐍 Medusa's Serpent Guard absorbs the attack!")
            return true
        }
        if sp.id == "void-moth" && dice.chance(0.15) {
            log.append("🦋 Void Wings — the Void Moth negates the hit!")
            return true
        }
        return false
    }

    /// applySpiritOnKill. Returns gold the spirit found (for the wallet).
    public static func kill(_ run: inout Run, dice: inout some Dice, log: inout [String]) -> Int {
        guard let sp = awake(run) else { return 0 }
        CustomSpirits.kill(&run, log: &log)
        switch sp.id {
        case "shadow-crow": run.gold += 3; log.append("Shadow Crow steals 3 gold!"); return 3
        case "the-lantern": run.gold += 5; log.append("The Lantern glows — +5 gold!"); return 5
        case "bone-hound-prime": run.sp = min(run.maxSp, run.sp + 5); log.append("Bone Hound Prime drains 5 SP!")
        case "ash-phoenix": run.hp = min(run.maxHp, run.hp + 12); log.append("Ash Phoenix blazes — +12 HP!")
        case "death-knight-spirit": run.hp = min(run.maxHp, run.hp + 5); log.append("Knight Shade channels the fallen — +5 HP!")
        case "easter-bunny" where dice.chance(0.20):
            run.hp = min(run.maxHp, run.hp + 10)
            log.append("Easter Bunny found an egg! Restored 10 HP.")
        default: break
        }
        return 0
    }

    /// Market Sprite: shop prices 20% lower.
    public static func shopPrice(_ price: Int, _ run: Run) -> Int {
        run.spirit == "market-sprite" ? max(1, jsRound(Double(price) * 0.80)) : price
    }

    // MARK: Earning spirits

    /// 30% of elite kills give a random elite spirit not yet earned.
    public static func eliteReward(earned: Set<String>, dice: inout some Dice) -> Spirit? {
        let left = eliteIds.filter { !earned.contains($0) }
        guard !left.isEmpty, dice.chance(0.30) else { return nil }
        return spirit(left[dice.roll(0...(left.count - 1))])
    }

    /// awardRareSpirit: beating a dungeon gives its rare spirit (Nightmare
    /// gives the Void Wraith or Void Moth).
    public static func victoryReward(_ run: Run, earned: Set<String>, dice: inout some Dice) -> Spirit? {
        let map = ["Crypt of Malachar": "bone-hound-prime", "The Ashbound Wastes": "inferno-hawk", "Frosthold Abyss": "glacial-wolf",
                   "The Sunken Archives": "crystal-serpent", "The Hollow": "grave-hound"]
        let id = run.difficulty == .nightmare ? (dice.chance(0.5) ? "void-wraith" : "void-moth") : map[run.dungeon]
        guard let id, !earned.contains(id) else { return nil }
        return spirit(id)
    }
}
