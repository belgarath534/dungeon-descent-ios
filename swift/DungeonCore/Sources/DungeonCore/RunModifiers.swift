import Foundation

/// RUN MODIFIERS: each run can roll one twist before you descend (Settings →
/// Gameplay turns them off, "dd_run_modifiers"). The web version applied
/// only Gold Curse's and Burning Dungeon's gold and Berserk's no-defend; in
/// Swift every modifier does what it says.
public enum RunModifiers {
    public struct Modifier: Sendable, Equatable {
        public let id, icon, name, desc: String
    }

    /// RUN_MODIFIERS
    public static let all: [Modifier] = [
        Modifier(id: "burning", icon: "🔥", name: "Burning Dungeon", desc: "Enemies deal fire damage (2 more each hit) but drop 50% more gold."),
        Modifier(id: "frozen", icon: "❄️", name: "Frozen Floors", desc: "Enemies hit 20% less hard. Fewer rooms per floor."),
        Modifier(id: "watching", icon: "👁️", name: "The Watching", desc: "No event rooms this run. Double XP from all kills."),
        Modifier(id: "deathmarch", icon: "💀", name: "Death March", desc: "Enemies 25% stronger. The boss drops a legendary item."),
        Modifier(id: "goldcurse", icon: "💰", name: "Gold Curse", desc: "Triple gold from all kills but potions cost double."),
        Modifier(id: "phantom", icon: "👻", name: "Phantom Run", desc: "Enemies don't see you coming: your first strike in every fight is a critical hit."),
        Modifier(id: "berserk", icon: "😤", name: "Berserk Mode", desc: "Your attacks deal 40% more damage but you cannot defend."),
        Modifier(id: "blessed", icon: "✨", name: "Blessed Run", desc: "Start with four Health Potions and 100 bonus gold."),
    ]

    public static func modifier(_ id: String?) -> Modifier? { all.first { $0.id == id } }

    public static func enabled(_ store: GameStore) -> Bool { store.getItem("dd_run_modifiers") != "0" }
    public static func setEnabled(_ on: Bool, store: GameStore) { store.setItem("dd_run_modifiers", on ? "1" : "0") }

    static func has(_ run: Run, _ id: String) -> Bool { run.modifier == id }

    /// rollRunModifier + applyRunModifier. Blessed Run's gold goes to the wallet.
    public static func start(_ run: inout Run, store: GameStore, wallet: Wallet, dice: inout some Dice) -> Modifier? {
        guard enabled(store) else { return nil }
        let m = all[dice.roll(0...(all.count - 1))]
        run.modifier = m.id
        if m.id == "blessed" {
            for _ in 0..<4 { run.inventory.append(Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "Restores 40 HP.", heal: 40)) }
            run.gold += 100
            wallet.addGold(100)
        }
        if m.id == "frozen" { run.floorRoomsNeeded = rooms(run.floorRoomsNeeded, run) }
        return m
    }

    /// Frozen Floors: one room fewer (never under 4; the boss floor keeps its one).
    public static func rooms(_ n: Int, _ run: Run) -> Int {
        has(run, "frozen") && n > 1 ? max(4, n - 1) : n
    }

    static func goldMult(_ run: Run) -> Double { has(run, "burning") ? 1.5 : has(run, "goldcurse") ? 3 : 1 }
    static func xpMult(_ run: Run) -> Int { has(run, "watching") ? 2 : 1 }
    static func enemyMult(_ run: Run) -> Double { has(run, "frozen") ? 0.8 : has(run, "deathmarch") ? 1.25 : 1 }
    static func fire(_ run: Run) -> Int { has(run, "burning") ? 2 : 0 }
    static func attackMult(_ run: Run) -> Double { has(run, "berserk") ? 1.4 : 1 }
    public static func noDefend(_ run: Run) -> Bool { has(run, "berserk") }
    static func noEvents(_ run: Run) -> Bool { has(run, "watching") }
    static func firstStrikeCrit(_ run: Run) -> Bool { has(run, "phantom") }
    public static func potionCost(_ item: Item, _ cost: Int, _ run: Run) -> Int {
        has(run, "goldcurse") && ["potion", "elixir", "heal", "sp-potion"].contains(item.type) ? cost * 2 : cost
    }

    /// Death March: the boss leaves a legendary weapon or armor.
    public static func bossPrize(_ run: inout Run, dice: inout some Dice) -> Item? {
        guard has(run, "deathmarch"), let legendary = Rarity.tiers.first(where: { $0.id == "legendary" }) else { return nil }
        let item = Inventory.equipment(level: max(1, 1 + run.floor / 3), tier: legendary, dice: &dice)
        run.inventory.append(item)
        return item
    }
}
