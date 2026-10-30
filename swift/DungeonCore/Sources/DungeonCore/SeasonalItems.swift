import Foundation

/// The seasonal shops' combat items (Liberty Shop, Shamrock Shop, Chocolate
/// Shop). Bought from the menu, they wait in your next run's bag and do what
/// they say when used. The web version applied the buffs at the moment of
/// buying (to no run at all from the menu), never let the Patriot Cannon be
/// used, and never gave the Freedom Potion's debuff immunity.
public enum SeasonalItems {
    static func make(_ id: String, _ name: String, _ icon: String, _ type: String, _ desc: String) -> Item {
        var it = Item(name: name, icon: icon, type: type, desc: desc)
        it.extra["seasonal"] = .string(id)
        return it
    }

    public static let all: [String: Item] = [
        "liberty-firework": make("liberty-firework", "Mega Firework", "🎆", "consumable", "Use in combat: deals 80 damage plus 5 per level."),
        "liberty-cannon": make("liberty-cannon", "Patriot Cannon", "💣", "consumable", "Use in combat: instantly defeats any non-boss enemy."),
        "liberty-potion": make("liberty-potion", "Freedom Potion", "🔵", "potion", "Heals 100 HP and grants immunity to debuffs for 3 turns."),
        "stpat-stout": make("stpat-stout", "Irish Stout", "🍺", "potion", "Heals 50 HP but reduces your ATK by 3 for 2 turns."),
        "stpat-charm": make("stpat-charm", "Leprechaun's Charm", "🧝", "consumable", "Your next attack is guaranteed to critically hit."),
        "stpat-rainbow": make("stpat-rainbow", "Rainbow Shield", "🌈", "consumable", "Use in combat: absorbs the next 40 damage taken."),
        "val-love-potion": make("val-love-potion", "Love Potion", "💘", "consumable", "Use in combat: charms a non-boss enemy to fight for you for 2 turns, then it turns on you."),
        "val-rose": make("val-rose", "Enchanted Rose", "🌹", "consumable", "+8 ATK for 4 turns. Beautiful and dangerous."),
        "val-cupid-arrow": make("val-cupid-arrow", "Cupid's Arrow", "🏹", "consumable", "Guaranteed critical hit on your next attack."),
        "val-heart-shield": make("val-heart-shield", "Heart Shield", "💗", "consumable", "Use in combat: absorbs the next 45 damage taken."),
    ]

    public static func id(_ item: Item) -> String? {
        if case .string(let s)? = item.extra["seasonal"] { return s }
        return nil
    }

    /// Uses one. Nil when the item isn't a seasonal one.
    static func use(_ run: inout Run, at index: Int) -> Inventory.Outcome? {
        guard let id = id(run.inventory[index]) else { return nil }
        let item = run.inventory[index]
        func combatOnly() -> Inventory.Outcome { Inventory.Outcome(message: "\(item.name) can only be used in combat — face an enemy first.", used: false) }
        var out = Inventory.Outcome(message: "")
        switch id {
        case "liberty-firework":
            guard run.inCombat, var e = run.enemy else { return combatOnly() }
            let d = 80 + run.level * 5
            e.hp = max(0, e.hp - d)
            run.enemy = e
            out.message = "🎆 BOOM! The firework deals \(d) damage to \(e.name)!"
            out.enemyDied = e.isDead
        case "liberty-cannon":
            guard run.inCombat, var e = run.enemy else { return combatOnly() }
            guard !e.isBoss else { return Inventory.Outcome(message: "The Patriot Cannon can't bring down a boss.", used: false) }
            e.hp = 0
            run.enemy = e
            out.message = "💣 The Patriot Cannon fires! One shot, one kill — \(e.name) is gone."
            out.enemyDied = true
        case "liberty-potion", "stpat-stout":
            let base = id == "liberty-potion" ? 100 : 50
            let heal = jsRound(Double(base) * run.potionMult)
            run.hp = min(run.maxHp, run.hp + heal)
            if id == "liberty-potion" {
                run.poisonTurns = 0
                run.frozen = false
                if !run.debuffImmune { run.debuffImmune = true; run.freedomTurns = 3 }
                out.message = "🔵 Freedom Potion! \(heal) HP restored. Immune to debuffs for 3 turns. HP: \(run.hp) of \(run.maxHp)."
            } else {
                run.tempAtk = -3
                run.tempAtkTurns = 2
                out.message = "🍺 Irish Stout! \(heal) HP restored. Attack down 3 for 2 turns. HP: \(run.hp) of \(run.maxHp)."
            }
            run.usedPotion = true
        case "stpat-charm", "val-cupid-arrow":
            run.markedKill = true
            out.message = id == "stpat-charm" ? "🧝 Leprechaun's Charm! Your next attack is a guaranteed crit."
                                              : "🏹 Cupid's Arrow! Your next attack is a guaranteed crit."
        case "stpat-rainbow", "val-heart-shield":
            guard run.inCombat else { return combatOnly() }
            let n = id == "stpat-rainbow" ? 40 : 45
            run.fight.shield += n
            out.message = (id == "stpat-rainbow" ? "🌈 Rainbow Shield!" : "💗 Heart Shield!") + " Absorbs the next \(n) damage."
        case "val-love-potion":
            guard run.inCombat, let e = run.enemy else { return combatOnly() }
            guard !e.isBoss else { return Inventory.Outcome(message: "Bosses cannot be charmed. Their will is too strong.", used: false) }
            run.fight.controlled = max(run.fight.controlled, 2)
            out.message = "💘 Love Potion! \(e.name) falls for you and turns its blows on itself for 2 turns. Then it remembers who you are."
        case "val-rose":
            run.tempAtk = 8
            run.tempAtkTurns = 4
            out.message = "🌹 Enchanted Rose! Plus 8 attack for 4 turns."
        default: return nil
        }
        run.inventory.remove(at: index)
        return out
    }
}
