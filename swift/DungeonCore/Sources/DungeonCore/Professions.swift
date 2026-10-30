import Foundation

/// Profession bonuses that start with the run (initDungeon) or come into
/// play later. The web version gave the Tinkerer's two potions and
/// Street Rat's Smoke Bomb at the start, but never applied the Tinkerer's
/// cheaper skills' second half or the Warden's debuff immunity; Swift does.
public enum Professions {
    /// The start of a run, after the saved items are loaded into the bag.
    public static func start(_ run: inout Run, prof: String) -> [String] {
        switch prof {
        case "Street Rat":
            run.fleeBonus += 0.20
            if !run.unlockedSkills.contains("smoke-bomb") { run.unlockedSkills.append("smoke-bomb") }
            return ["🐀 Street Rat — Smoke Bomb learned, and +20% flee chance."]
        case "Tinkerer":
            for _ in 0..<2 { run.inventory.append(Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "Restores 40 HP.", heal: 40)) }
            return ["🔧 Tinkerer — 2 Health Potions packed, and skills cost 2 less SP."]
        default:
            return []
        }
    }

    /// Tinkerer: every skill costs 2 less SP.
    static func skillCostCut(_ run: Run) -> Int { run.prof == "Tinkerer" ? 2 : 0 }

    /// Warden: the first debuff each floor slides off. True when it does.
    static func wardenBlocks(_ run: inout Run, log: inout [String]) -> Bool {
        guard run.prof == "Warden", run.wardenFloor != run.floor else { return false }
        run.wardenFloor = run.floor
        log.append("🛡 Warden — you shrug off the effect. (Once a floor.)")
        return true
    }
}
