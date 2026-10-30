import Foundation

/// What each race does in a run (the race cards at character creation and
/// the Help screen's Races list).
///
/// The web version applied about half of this. The stat lines (+STR, +AGI …)
/// on Human, Elf, Dwarf, Orc, Tiefling, Shade, Gnome and Merfolk never did
/// anything; nor did Golem at all, Halfling's dodge, Vampire's smaller HP,
/// Goblin's starting gold or Angel's heal on level up. Swift does what the
/// cards say. Each "+STAT" is one level point spent on that stat, "-STAT"
/// takes one away, and Human's "small bonus to every stat" is half a point
/// of each.
///
/// Race abilities follow the Class Traits setting, like the web version's;
/// the stat lines always apply.
public enum Races {
    /// Turns the race on for a new run. Returns lines for the run log.
    public static func start(_ run: inout Run, classTraits: Bool, wallet: Wallet) -> [String] {
        var notes: [String] = []
        switch run.race {
        case "Human":
            run.atkBonus += 1
            run.maxHp += 5; run.hp += 5
            run.defBonus += 1
            run.maxSp += 3; run.sp += 3
            run.critBonus += 0.015; run.fleeBonus += 0.025
            run.luckBonus += 0.05
        case "Elf": agility(&run); intelligence(&run)
        case "Dwarf": strength(&run); run.defBonus += 2
        case "Orc":
            strength(&run); strength(&run)
            // Never below zero defense: the penalty can't make hits land harder.
            run.defBonus -= min(2, max(0, run.totalDef))
        case "Tiefling": luck(&run); intelligence(&run)
        case "Shade": agility(&run); luck(&run)
        case "Gnome": luck(&run)
        case "Merfolk": agility(&run)
        case "Golem": run.defBonus += 5
        case "Goblin":
            run.gold += 30
            wallet.addGold(30)
            notes.append("👺 Goblin's purse: +30 gold.")
        default: break
        }
        guard classTraits else { return notes }
        run.raceTraits = true
        switch run.race {
        case "Vampire":
            run.maxHp = max(1, jsRound(Double(run.maxHp) * 0.80))
            run.hp = min(run.hp, run.maxHp)
        case "Angel":
            run.lives += 1
            run.maxLives += 1
        case "Demon": run.atkBonus += 2
        case "Gnome": run.maxSp += 10; run.sp += 10
        case "Merfolk" where run.dungeon == "The Sunken Archives":
            run.maxHp = jsRound(Double(run.maxHp) * 1.10)
            run.hp = run.maxHp
            run.atkBonus += 3
            notes.append("🌊 Merfolk in their element — +10% HP and +3 attack in the Sunken Archives!")
        default: break
        }
        return notes
    }

    static func strength(_ run: inout Run) { run.atkBonus += 2 }
    static func intelligence(_ run: inout Run) { run.maxSp += 5; run.sp += 5 }
    static func agility(_ run: inout Run) { run.fleeBonus += 0.05; run.critBonus += 0.03 }
    static func luck(_ run: inout Run) { run.luckBonus += 0.10 }

    /// The race's ability is on for this run.
    public static func trait(_ run: Run, _ race: String) -> Bool { run.raceTraits && run.race == race }

    /// Your hit after Dragonborn's burn (10%: +30% of the hit, so it grows
    /// with the floor as your hits do) and Demon's +15%.
    static func attack(_ run: Run, _ dmg: Int, dice: inout some Dice, log: inout [String]) -> Int {
        guard dmg > 0 else { return dmg }
        var d = dmg
        if trait(run, "Dragonborn") && dice.chance(0.10) {
            let burn = jsRound(Double(d) * 0.30)
            d += burn
            log.append("🔥 Dragon Blood ignites — +\(burn) burn damage!")
        }
        if trait(run, "Demon") { d = jsRound(Double(d) * 1.15) }
        return d
    }

    /// Demons take 15% more.
    static func incoming(_ run: Run, _ taken: Int) -> Int {
        trait(run, "Demon") ? jsRound(Double(taken) * 1.15) : taken
    }

    /// Halflings slip 15% of attacks.
    static func dodges(_ run: Run, _ enemy: Enemy, dice: inout some Dice, log: inout [String]) -> Bool {
        guard trait(run, "Halfling"), dice.chance(0.15) else { return false }
        log.append("🧑‍🌾 Too quick to catch — you duck under \(enemy.name)'s attack!")
        return true
    }

    /// Golems can't be poisoned or frozen.
    public static func immune(_ run: Run) -> Bool { trait(run, "Golem") }

    /// Merfolk potions heal 20% more.
    static func potionHeal(_ run: Run, _ heal: Int) -> Int {
        trait(run, "Merfolk") ? jsRound(Double(heal) * 1.20) : heal
    }

    /// Gnome skills cost 2 SP less.
    static func skillCostCut(_ run: Run) -> Int { trait(run, "Gnome") ? 2 : 0 }

    /// Vampires drain 5 HP from every kill. Returns a note for the kill message.
    static func onKill(_ run: inout Run) -> String {
        guard trait(run, "Vampire"), run.hp > 0, run.hp < run.maxHp else { return "" }
        let healed = min(5, run.maxHp - run.hp)
        run.hp += healed
        return " 🧛 You drain \(healed) HP."
    }

    /// Angels heal 15 HP for every level gained.
    static func onLevelUp(_ run: inout Run, levels: Int) {
        guard trait(run, "Angel"), levels > 0 else { return }
        run.hp = min(run.maxHp, run.hp + 15 * levels)
    }

    /// Dwarves pay 10% less in the shop.
    public static func shopPrice(_ price: Int, _ run: Run) -> Int {
        run.race == "Dwarf" ? max(1, jsRound(Double(price) * 0.90)) : price
    }
}
