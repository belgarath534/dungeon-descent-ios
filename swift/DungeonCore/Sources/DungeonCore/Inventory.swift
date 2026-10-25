import Foundation

/// Using items, searching rooms, loot rooms, traps, gear and the shop.
/// Ports of useItem / searchRoom / enterRoom's loot branch / triggerTrap /
/// equipWeapon / equipArmor / openShop / buyItem.
///
/// Where an item's description and the web code disagree, this follows the
/// description (see "Web bugs fixed" in swift/MIGRATION.md).
public enum Inventory {
    public struct Outcome: Equatable, Sendable {
        public var message: String
        /// False when nothing happened and the item was kept.
        public var used = true
        public var enemyDied = false
        public var playerDied = false
    }

    // MARK: Using items

    /// Uses the item at `index`. Items never cost a combat turn, as in the web version.
    public static func use(_ run: inout Run, at index: Int) -> Outcome {
        guard run.inventory.indices.contains(index) else { return Outcome(message: "That item is gone.", used: false) }
        let item = run.inventory[index]
        var out = Outcome(message: "")

        switch item.type {
        case "potion":
            guard run.hp < run.maxHp else { return Outcome(message: "Your health is already full.", used: false) }
            var heal = jsRound(Double(item.heal ?? 40) * run.potionMult)
            if run.cls == "Alchemist" { heal = jsRound(Double(heal) * 1.35) }
            run.hp = min(run.maxHp, run.hp + heal)
            out.message = "You drink \(item.name), restoring \(heal) HP. HP: \(run.hp) of \(run.maxHp)."
        case "elixir", "heal":
            guard run.hp < run.maxHp else {
                return Outcome(message: "Your health is already full. Save the elixir for when you need it.", used: false)
            }
            let heal = jsRound(Double(run.maxHp) * (item.healPct ?? 0.6))
            run.hp = min(run.maxHp, run.hp + heal)
            out.message = "Elixir used. \(item.name). Restored \(heal) HP. Current HP: \(run.hp) of \(run.maxHp)."
        case "sp-potion":
            guard run.sp < run.maxSp else { return Outcome(message: "Your SP is already full.", used: false) }
            let before = run.sp
            run.sp = min(run.maxSp, run.sp + (item.sp ?? 15))
            out.message = "Used \(item.name). +\(run.sp - before) SP. SP: \(run.sp) of \(run.maxSp)."
        case "atk-potion":
            let n = item.atk ?? 4
            run.tempAtk = n
            run.tempAtkTurns = 3
            out.message = "Used \(item.name). +\(n) attack for 3 turns."
        case "def-potion":
            let n = item.def ?? 3
            run.tempDef = n
            run.tempDefTurns = 3
            out.message = "Used \(item.name). +\(n) defense for 3 turns."
        case "luck-potion":
            run.luckKills = 3
            out.message = "Lucky Potion used. Next 3 kills drop double gold."
        case "swift-potion":
            run.swiftTurns = 2
            out.message = "Swift Potion used. Flee is guaranteed for 2 turns."
        case "fire-potion":
            guard var e = run.enemy, run.inCombat else {
                return Outcome(message: "No enemy to target. Use this in combat.", used: false)
            }
            let dmg = jsRound(Double(e.maxHp) * 0.40)
            e.hp = max(0, e.hp - dmg)
            run.enemy = e
            out.message = "Fire Potion! \(dmg) fire damage to \(e.name) — ignores all defense!"
            out.enemyDied = e.isDead
        case "curse-potion":
            guard var e = run.enemy, run.inCombat else {
                return Outcome(message: "No enemy to target. Use this in combat.", used: false)
            }
            e.cursedTurns = 3
            run.enemy = e
            out.message = "Curse Potion! \(e.name)'s attack is halved for 3 turns."
        case "rune":
            switch item.id {
            case "rune-strength": run.atkBonus += 6; out.message = "Rune of Strength. Plus 6 attack for the rest of this run."
            case "rune-protection": run.defBonus += 5; out.message = "Rune of Protection. Plus 5 defense for the rest of this run."
            case "rune-speed": run.runeSpeed = true; out.message = "Rune of Speed. Flee guaranteed for the rest of this run."
            case "rune-fortune": run.runeFortune = true; out.message = "Rune of Fortune. 25 percent bonus gold this run."
            case "rune-vitality":
                run.maxHp += 20
                run.hp = min(run.maxHp, run.hp + 20)
                out.message = "Rune of Vitality. Plus 20 max HP."
            default: return Outcome(message: "Unknown rune.", used: false)
            }
        case "scroll":
            switch item.id {
            case "scroll-smite":
                guard var e = run.enemy, run.inCombat else { return Outcome(message: "No enemy to smite.", used: false) }
                e.hp = max(0, e.hp - 80)
                run.enemy = e
                out.message = "Scroll of Smite. 80 unblockable damage to \(e.name)."
                out.enemyDied = e.isDead
            case "scroll-mending":
                guard !run.inCombat else { return Outcome(message: "Scroll of Mending only works outside combat.", used: false) }
                let h = jsRound(Double(run.maxHp) * 0.5)
                run.hp = min(run.maxHp, run.hp + h)
                out.message = "Scroll of Mending. Healed \(h) HP."
            case "scroll-reveal":
                // Rolled when used, then consumed by the next rooms (see Rooms.next).
                out.message = "Scroll of Reveal."
            default: return Outcome(message: "Unknown scroll.", used: false)
            }
        case "weapon", "armor":
            return equip(&run, at: index)
        case "gem":
            return Outcome(message: "\(item.name) is worth \(item.gold ?? 0) gold. Sell it at the Blacksmith.", used: false)
        case "phoenix-feather":
            return Outcome(message: "The Phoenix Feather works on its own. It ignites if you would die.", used: false)
        case "ring":
            return Outcome(message: "\(item.name) works while you carry it.", used: false)
        default:
            return Outcome(message: "\(item.name) can't be used in the Swift version yet.", used: false)
        }

        run.inventory.remove(at: index)
        return out
    }

    /// Fills in which rooms a Scroll of Reveal shows. Call right after using one.
    public static func reveal(_ run: inout Run, dice: inout some Dice) -> String {
        while run.upcomingRooms.count < 3 { run.upcomingRooms.append(Rooms.roll(run.difficulty, dice: &dice)) }
        let names = run.upcomingRooms.prefix(3).map { o -> String in
            switch o {
            case .fight: return "Combat Room"
            case .loot: return "Treasure Room"
            case .event: return "Quiet Room"
            }
        }
        return "Next 3 rooms: " + names.joined(separator: ", ") + "."
    }

    // MARK: Gear

    /// Equips a weapon or armor from the inventory; whatever was equipped goes back in.
    public static func equip(_ run: inout Run, at index: Int) -> Outcome {
        guard run.inventory.indices.contains(index) else { return Outcome(message: "That item is gone.", used: false) }
        let item = run.inventory[index]
        if item.isWeapon {
            run.inventory.remove(at: index)
            if let old = run.equippedWeapon { run.inventory.append(old) }
            run.equippedWeapon = item
            let r = item.weaponAttack
            return Outcome(message: "Equipped \(item.icon) \(item.name) Level \(item.level ?? 1). Weapon attack \(r.lowerBound) to \(r.upperBound).")
        }
        if item.isArmor {
            guard !run.inCombat else { return Outcome(message: "Cannot change armor during combat.", used: false) }
            run.inventory.remove(at: index)
            if let old = run.equippedArmor { run.inventory.append(old) }
            run.equippedArmor = item
            return Outcome(message: "Equipped \(item.icon) \(item.name) Level \(item.level ?? 1). Defense increased by \(item.armorDefense).")
        }
        return Outcome(message: "\(item.name) can't be equipped.", used: false)
    }

    public static func unequipWeapon(_ run: inout Run) -> String {
        guard let w = run.equippedWeapon else { return "No weapon equipped." }
        run.inventory.append(w)
        run.equippedWeapon = nil
        return "Weapon unequipped and returned to inventory."
    }

    public static func unequipArmor(_ run: inout Run) -> String {
        guard !run.inCombat else { return "Cannot change armor during combat." }
        guard let a = run.equippedArmor else { return "No armor equipped." }
        run.inventory.append(a)
        run.equippedArmor = nil
        return "Armor unequipped and returned to inventory."
    }

    // MARK: Finding things

    public struct Find: Equatable, Sendable {
        public var message: String
        public var item: Item? = nil
        public var gold = 0
        public var trap: String? = nil
        public var playerDied = false
    }

    /// Picks up a found item: gems turn into gold, everything else goes in the bag.
    static func pickUp(_ run: inout Run, _ item: Item, wallet: Wallet) -> (gold: Int, kept: Item?) {
        if item.type == "gem" {
            let g = max(0, item.gold ?? 0)
            run.gold += g
            wallet.addGold(g)
            return (g, nil)
        }
        if (item.isWeapon || item.isArmor) && run.inventory.contains(where: { $0.name == item.name }) {
            return (0, nil)
        }
        run.inventory.append(item)
        run.atkBonus += item.isWeapon ? (item.atkBonus ?? 0) : 0
        run.defBonus += item.isArmor ? (item.defBonus ?? 0) : 0
        return (0, item)
    }

    /// A loot room (28% of rooms): one random item from the dungeon's loot table.
    public static func lootRoom(_ run: inout Run, dice: inout some Dice, wallet: Wallet) -> Find {
        let table = ItemTables.loot(for: run.dungeon)
        var item = table[dice.roll(0...(table.count - 1))]
        if item.isWeapon || item.isArmor {
            item = Rarity.apply(Rarity.roll(dice: &dice), to: item, dice: &dice)
        }
        let got = pickUp(&run, item, wallet: wallet)
        if got.gold > 0 {
            return Find(message: "You find a \(item.name) worth \(got.gold) gold glinting in the dust.", gold: got.gold)
        }
        if got.kept == nil {
            return Find(message: "You already carry a \(item.name). The duplicate fades back into the dark.")
        }
        return Find(message: "You discover: \(item.icon) \(item.name). \(item.desc)", item: item)
    }

    /// Searching a room, once per room. Finds something 35% of the time
    /// (50% for a Thief); 20% of the time it's a trap; the first search of a
    /// run always finds something.
    public static func search(_ run: inout Run, dice: inout some Dice, wallet: Wallet) -> Find {
        guard !run.searched else { return Find(message: "You have already searched this room. You find nothing more here.") }
        run.searched = true
        let findChance = run.prof == "Thief" ? 0.50 : 0.35
        let first = !run.firstSearchDone
        run.firstSearchDone = true

        if first || dice.chance(findChance) {
            let table = ItemTables.loot(for: run.dungeon)
            let item = table[dice.roll(0...(table.count - 1))]
            let got = pickUp(&run, item, wallet: wallet)
            if got.gold > 0 {
                return Find(message: "Searching carefully, you find \(got.gold) gold hidden in the shadows.", gold: got.gold)
            }
            if got.kept == nil {
                return Find(message: "You find another \(item.name), but you already carry one.")
            }
            return Find(message: "Searching carefully, you find \(item.icon) \(item.name). \(item.desc)", item: item)
        }
        if dice.chance(0.20 / (1 - findChance)) {
            if run.prof == "Scholar" {
                return Find(message: "Your scholarly instincts warn you. You step around the trap easily.", trap: "avoided")
            }
            return triggerTrap(&run, dice: &dice)
        }
        return Find(message: "Dust. Silence. Nothing but old stone and older shadows.")
    }

    static func triggerTrap(_ run: inout Run, dice: inout some Dice) -> Find {
        let pool = ItemTables.traps(for: run.dungeon, difficulty: run.difficulty)
        let trap = pool[dice.roll(0...(pool.count - 1))]
        run.hp = max(0, run.hp - trap.damage)
        switch trap.effect {
        case "poison", "burn":
            run.poisonTurns = trap.turns
            run.poisonDamage = trap.effect == "burn" ? 6 : 8
        case "sp": run.sp = max(0, run.sp - 8)
        case "freeze": if run.armorEffect != "juggernaut" { run.frozen = true }
        case "pushback": if run.roomsOnFloor > 1 { run.roomsOnFloor -= 1 }
        default: break
        }
        return Find(message: "Trap! \(trap.name) — \(trap.msg) HP: \(run.hp) of \(run.maxHp).",
                    trap: trap.name, playerDied: run.isDead)
    }

    // MARK: Shop

    public struct ShopItem: Identifiable, Equatable, Sendable {
        public let id: Int
        public var item: Item
        public var sold = false
    }

    /// Four random items from the dungeon's stock, like openShop().
    public static func shopStock(for run: Run, dice: inout some Dice) -> [ShopItem] {
        var stock = ItemTables.shop(for: run.dungeon)
        var picks: [ShopItem] = []
        while picks.count < 4 && !stock.isEmpty {
            picks.append(ShopItem(id: picks.count, item: stock.remove(at: dice.roll(0...(stock.count - 1)))))
        }
        return picks
    }

    /// Price after the night discount (25% off from 8pm to 8am, as isNightTime()).
    public static func price(_ item: Item, hour: Int) -> Int {
        let cost = item.cost ?? 0
        let night = hour >= 20 || hour < 8
        return night ? Int((Double(cost) * 0.75).rounded(.down)) : cost
    }

    /// Buys a shop item with gold from the run and the shared wallet.
    public static func buy(_ run: inout Run, _ entry: inout ShopItem, wallet: Wallet, hour: Int) -> Outcome {
        guard !entry.sold else { return Outcome(message: "Already sold.", used: false) }
        let cost = price(entry.item, hour: hour)
        guard run.gold >= cost, wallet.spendGold(cost) else {
            return Outcome(message: "Not enough gold. You need \(cost) gold. You have \(run.gold).", used: false)
        }
        run.gold -= cost
        entry.sold = true
        var item = entry.item
        item.cost = nil
        run.inventory.append(item)
        let hint = item.isWeapon || item.isArmor ? " Open your inventory to equip it." : ""
        return Outcome(message: "Bought \(item.name).\(hint) Gold remaining: \(run.gold).")
    }

    /// The cost of rerolling the shop's stock.
    public static let refreshCost = 50

    // MARK: Death

    /// A Phoenix Feather in the bag revives at 30% HP instead of losing a life.
    static func usePhoenixFeather(_ run: inout Run) -> Bool {
        guard let i = run.inventory.firstIndex(where: { $0.type == "phoenix-feather" }) else { return false }
        run.inventory.remove(at: i)
        run.hp = max(1, jsRound(Double(run.maxHp) * 0.30))
        return true
    }
}

/// The items kept between runs ("dd_global_inv") and the gear you have on
/// ("dd_equipped_weapon", "dd_equipped_armor"), stored like the web version.
public struct GlobalInventory {
    let store: GameStore
    public init(store: GameStore) { self.store = store }

    /// Item types that carry over to the next run after a victory (saveProgress).
    public static let keepTypes: Set<String> = ["enchanter", "soul-trap", "music-player", "skill-orb", "rune", "scroll", "sp-potion"]

    public var items: [Item] {
        guard let s = store.getItem("dd_global_inv"), let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: d)) ?? []
    }

    public func save(_ items: [Item]) {
        if let d = try? JSONEncoder().encode(items), let s = String(data: d, encoding: .utf8) {
            store.setItem("dd_global_inv", s)
        }
    }

    public var equippedWeapon: Item? { load("dd_equipped_weapon") }
    public var equippedArmor: Item? { load("dd_equipped_armor") }

    public func saveEquipped(weapon: Item?, armor: Item?) {
        put("dd_equipped_weapon", weapon)
        put("dd_equipped_armor", armor)
    }

    /// Loads saved items and gear into a new run, dropping duplicate gear.
    public func load(into run: inout Run) {
        var seen = Set<String>()
        run.inventory = items.filter { i in
            guard i.isWeapon || i.isArmor else { return true }
            return seen.insert(i.type + "::" + i.name).inserted
        }
        run.equippedWeapon = equippedWeapon
        run.equippedArmor = equippedArmor
    }

    /// Saves what a run keeps: gear and the keep-types, without duplicates.
    public func keep(from run: Run) {
        var seen = Set<String>()
        let kept = run.inventory.filter { i in
            if i.isWeapon || i.isArmor { return seen.insert(i.type + "::" + i.name).inserted }
            return Self.keepTypes.contains(i.type)
        }
        save(kept)
        saveEquipped(weapon: run.equippedWeapon, armor: run.equippedArmor)
    }

    private func load(_ key: String) -> Item? {
        guard let s = store.getItem(key), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Item.self, from: d)
    }

    private func put(_ key: String, _ item: Item?) {
        guard let item else { store.removeItem(key); return }
        if let d = try? JSONEncoder().encode(item), let s = String(data: d, encoding: .utf8) { store.setItem(key, s) }
    }
}
