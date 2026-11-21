import Foundation

/// BOSS LOOT (bossRelicTable): every dungeon boss drops its own relic, which
/// works while you carry it. In the web version a relic was lost when the run
/// ended, though several promise "once per run"; Swift keeps one of each in
/// your stash for later runs. The Crown Fragment follows its description
/// (10% to refuse death, once a run) where the web version always fired.
public enum BossRelics {
    static func relic(_ name: String, _ icon: String, _ desc: String, _ extra: [String: JSONValue]) -> Item {
        var it = Item(name: name, icon: icon, type: "relic", desc: desc)
        for (k, v) in extra { it.extra[k] = v }
        it.extra["bossRelic"] = .bool(true)
        return it
    }

    public static let table: [String: Item] = [
        "Crypt of Malachar": relic("Malachar's Crown Fragment", "👑", "A shard of the Undying King's crown. Grants +15 max HP and 10% chance to ignore death once per run.", ["maxHpBonus": .number(15), "hasCrownShield": .bool(true)]),
        "The Ashbound Wastes": relic("Ember Heart", "❤️‍🔥", "The smoldering core of the Ash boss. Burns enemies for 3 extra damage each turn you attack.", ["ashBurn": .number(3)]),
        "Frosthold Abyss": relic("Frostbite Shard", "🧊", "A frozen splinter from the Frost boss. Each attack has 20% chance to freeze the enemy, skipping their next turn.", ["frostChance": .number(0.20)]),
        "The Sunken Archives": relic("Drowned Tome", "📖", "A waterlogged grimoire. Grants +20 max SP and spells cost 1 fewer SP.", ["maxSpBonus": .number(20), "spellDiscount": .number(1)]),
        "The Hollow": relic("Hollow Mask", "🎭", "A mask worn by the Hollow boss. Grants 15% dodge chance and makes you invisible to the Stalker for 3 floors.", ["hollowDodge": .number(0.15), "stalkerImmunity": .number(3)]),
        "The Whispering Forest": relic("Sylvan Heart", "🌿", "The forest boss's life essence. Heals 3 HP every room you enter.", ["roomHealBonus": .number(3)]),
        "The Infernal Descent": relic("Infernal Brand", "🔱", "Seared into your palm by the Infernal boss. Grants +8 ATK and makes all fire damage deal 25% more.", ["atkBonus": .number(8), "fireAmp": .number(0.25)]),
        "The Abyssal Deep": relic("Leviathan Scale", "🐉", "A scale from the deep boss. Grants +25 max HP and reduces all incoming damage by 3.", ["maxHpBonus": .number(25), "dmgReduction": .number(3)]),
        "The Shadow World": relic("Shadow Tear", "🌑", "A crystallized drop of shadow. Boosts all damage by 12% and makes the Stalker hesitate once.", ["dmgAmp": .number(0.12), "stalkerHesitate": .bool(true)]),
    ]

    public static func isRelic(_ i: Item) -> Bool { i.extra["bossRelic"] == .bool(true) || table.values.contains { $0.name == i.name && i.type == "relic" } }

    /// The sum of a number on every relic you carry.
    static func sum(_ run: Run, _ key: String) -> Double {
        run.inventory.reduce(0) { acc, i in
            if case .number(let n)? = i.extra[key] { return acc + n }
            return acc
        }
    }

    static func has(_ run: Run, _ key: String) -> Bool { run.inventory.contains { $0.extra[key] != nil } }

    /// Stat bonuses, when a relic is picked up or a run starts with it.
    static func grant(_ run: inout Run, _ item: Item) {
        func n(_ k: String) -> Int { if case .number(let v)? = item.extra[k] { return Int(v) }; return 0 }
        run.maxHp += n("maxHpBonus"); run.hp = min(run.maxHp, run.hp + n("maxHpBonus"))
        run.maxSp += n("maxSpBonus"); run.sp = min(run.maxSp, run.sp + n("maxSpBonus"))
        run.atkBonus += n("atkBonus")
    }

    /// The start of a run: relics from your stash give their stats.
    public static func start(_ run: inout Run) {
        for i in run.inventory where isRelic(i) { grant(&run, i) }
    }

    /// The boss falls: its relic, unless you already carry it.
    public static func drop(_ run: inout Run) -> Item? {
        guard let r = table[run.dungeon], !run.inventory.contains(where: { $0.name == r.name }) else { return nil }
        run.inventory.append(r)
        grant(&run, r)
        return r
    }

    /// Your attack: Shadow Tear's 12% (on the roll).
    static func attackRoll(_ run: Run, _ a: Int) -> Int {
        let amp = sum(run, "dmgAmp")
        return amp > 0 ? jsRound(Double(a) * (1 + amp)) : a
    }

    /// After your attack lands: Ember Heart's burn and the Frostbite Shard.
    static func afterAttack(_ run: inout Run, dice: inout some Dice, log: inout [String]) {
        guard var e = run.enemy, !e.isDead else { return }
        let burn = Int(sum(run, "ashBurn"))
        if burn > 0 {
            e.hp = max(0, e.hp - burn)
            log.append("❤️‍🔥 Ember Heart burns for \(burn) extra damage!")
        }
        if !e.isDead && has(run, "frostChance") && dice.chance(0.20) {
            e.stunTurns = max(e.stunTurns, 1)
            log.append("🧊 Frostbite Shard freezes \(e.name)! It skips its next turn.")
        }
        run.enemy = e
    }

    /// The Hollow Mask's dodge.
    static func dodges(_ run: Run, dice: inout some Dice, log: inout [String]) -> Bool {
        guard has(run, "hollowDodge"), dice.chance(0.15) else { return false }
        log.append("🎭 The Hollow Mask — you slip out of reach!")
        return true
    }

    /// The Leviathan Scale.
    static func incoming(_ run: Run, _ taken: Int) -> Int {
        let dr = Int(sum(run, "dmgReduction"))
        return dr > 0 && taken > 0 ? max(1, taken - dr) : taken
    }

    /// The Drowned Tome: skills cost 1 less SP.
    static func skillCostCut(_ run: Run) -> Int { Int(sum(run, "spellDiscount")) }

    /// The Infernal Brand: fire spells hit 25% harder.
    static func fireAmp(_ run: Run) -> Double { sum(run, "fireAmp") }

    /// The Sylvan Heart, entering a room.
    public static func roomHeal(_ run: inout Run) -> String? {
        let h = Int(sum(run, "roomHealBonus"))
        guard h > 0, run.hp < run.maxHp else { return nil }
        run.hp = min(run.maxHp, run.hp + h)
        return "🌿 Sylvan Heart pulses — +\(h) HP."
    }

    /// Malachar's Crown Fragment: 10% to refuse death, once a run.
    static func crownSaves(_ run: inout Run, dice: inout some Dice) -> Bool {
        guard has(run, "hasCrownShield"), !run.crownUsed, dice.chance(0.10) else { return false }
        run.crownUsed = true
        run.hp = max(1, jsRound(Double(run.maxHp) * 0.20))
        return true
    }
}
