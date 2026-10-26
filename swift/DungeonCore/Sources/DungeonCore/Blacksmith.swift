import Foundation

/// The Blacksmith (#ov-blacksmith): upgrade, buy, sell, equip, reforge and
/// repair gear. It works on a `Forge` (your gear, bag and gold), which the
/// app fills from the run in a dungeon or from the saved gear on the menu.
public struct Forge: Sendable {
    public var weapon: Item?
    public var armor: Item?
    public var bag: [Item]
    public var gold: Int
    /// The character's profession in a run (Blacksmiths get 10% off); nil on the menu.
    public var prof: String?
    /// Items bought here that also go in the saved stash (addToGlobalInventory).
    public var stashed: [Item] = []

    public init(weapon: Item?, armor: Item?, bag: [Item], gold: Int, prof: String?) {
        self.weapon = weapon; self.armor = armor; self.bag = bag; self.gold = gold; self.prof = prof
    }
}

public enum Blacksmith {
    public static let maxLevel = 10
    public static let maxDurability = 100
    /// UPGRADE_COSTS, by the gear's current level.
    static let upgradeCosts = [0, 40, 80, 140, 220, 320, 440, 580, 740, 920, 1150]

    // MARK: Discounts

    /// dd_blacksmith_discount: a seasonal shop, birthday code or reward.
    public static func discount(_ store: GameStore, now: Date = Date()) -> (pct: Double, source: String) {
        guard let raw = store.getItem("dd_blacksmith_discount") else { return (0, "") }
        if let n = Double(raw) { return (n, store.getItem("dd_blacksmith_discount_source") ?? "Promo") }
        guard let d = raw.data(using: .utf8), let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) else { return (0, "") }
        if case .number(let exp)? = v["expires"], exp <= now.timeIntervalSince1970 * 1000 {
            store.removeItem("dd_blacksmith_discount")
            return (0, "")
        }
        var pct = 0.0, source = "Event"
        if case .number(let p)? = v["pct"] { pct = p }
        if case .string(let s)? = v["source"] { source = s }
        return (pct, source)
    }

    /// getUpgradeCost
    public static func upgradeCost(level: Int, prof: String?, store: GameStore, now: Date = Date()) -> Int {
        var cost = upgradeCosts.indices.contains(level) && level > 0 ? upgradeCosts[level]
            : jsRound(3000 * pow(1.4, Double(level - 10)))
        if prof == "Blacksmith" { cost = jsRound(Double(cost) * 0.9) }
        let d = discount(store, now: now).pct
        if d > 0 { cost = jsRound(Double(cost) * (1 - d)) }
        return max(1, cost)
    }

    /// The weapon shop's price multiplier: 10% off for Blacksmiths, times any discount.
    public static func shopMultiplier(prof: String?, store: GameStore) -> Double {
        (prof == "Blacksmith" ? 0.9 : 1) * (1 - discount(store).pct)
    }

    // MARK: Catalogs

    /// BLACKSMITH_WEAPONS
    public static let weapons: [Item] = [
        w("starter-blade", "Worn Blade", "🗡️", "sword", 1, 0, [4, 8], "A battered but reliable blade. Free for any new adventurer."),
        w("iron-sword", "Iron Sword", "⚔️", "sword", 1, 40, [5, 10], "Standard iron. Reliable in any dungeon."),
        w("hunters-bow", "Hunter's Bow", "🏹", "bow", 1, 50, [4, 9], "Quick to draw. Good attack range."),
        w("oak-staff", "Oak Staff", "🪄", "staff", 1, 55, [4, 8], "Channels arcane energy. Restores 10 SP on equip."),
        w("battle-axe", "Battle Axe", "🪓", "axe", 1, 70, [7, 13], "Heavy and slow but devastating damage."),
        w("shadow-dagger", "Shadow Dagger", "🔪", "dagger", 1, 65, [5, 9], "Fast strikes. Higher crit chance."),
        w("war-hammer", "War Hammer", "🔨", "hammer", 1, 80, [7, 14], "Crushes through armor. Ignores 2 enemy defense."),
        w("silver-rapier", "Silver Rapier", "🤺", "sword", 2, 120, [6, 11], "Elegant and precise. Level 2 right out of the forge."),
        w("soul-drinker", "Soul Drinker", "🩸", "sword", 1, 130, [5, 10], "Heals 5 HP on every kill. Thirsty blade.", ["soulDrinker": .bool(true)]),
        w("thunderfist", "Thunderfist", "⚡", "hammer", 1, 140, [6, 12], "30% chance to stun enemy — they skip their next attack.", ["stunChance": .number(0.30)]),
        w("last-blade", "The Last Blade", "💔", "sword", 10, 200, [9, 16], "Starts at level 10 but degrades one level per floor. Use it while it lasts.", ["degrading": .bool(true)]),
    ]

    /// BLACKSMITH_ARMORS
    public static let armors: [Item] = [
        a("leather-vest", "Leather Vest", "🦺", "light", 50, 3, "Light leather. +3 defense. Doesn't slow you down."),
        a("chain-mail", "Chain Mail", "⛓️", "medium", 80, 5, "Linked iron rings. +5 defense. Balanced protection."),
        a("iron-plate", "Iron Plate", "🛡️", "heavy", 110, 8, "Heavy iron plate. +8 defense. -1 attack. Worth it."),
        a("ember-shield", "Ember Shield", "🔥", "medium", 140, 6, "Forged in ashbound fire. +6 defense. Resists heat."),
        a("void-cloak", "Void Cloak", "🌑", "light", 160, 4, "Woven from void silk. +4 defense. +5% dodge chance."),
        a("thornmail", "Thornmail", "🌵", "medium", 180, 5, "+5 defense. Reflects 20% of incoming damage back at attacker.", ["thornReflect": .number(0.20)]),
        a("ghost-shroud", "Ghost Shroud", "👻", "light", 200, 3, "+3 defense. 10% chance to become untargetable for one turn.", ["ghostDodge": .number(0.10)]),
    ]

    static func w(_ id: String, _ name: String, _ icon: String, _ type: String, _ level: Int, _ cost: Int, _ atk: [Int],
                  _ desc: String, _ extra: [String: JSONValue] = [:]) -> Item {
        var i = Item(id: id, name: name, icon: icon, type: "weapon", desc: desc, cost: cost, atkBase: atk, level: level,
                     weaponType: type, isEquippable: true)
        i.extra = extra
        return i
    }

    static func a(_ id: String, _ name: String, _ icon: String, _ type: String, _ cost: Int, _ def: Int,
                  _ desc: String, _ extra: [String: JSONValue] = [:]) -> Item {
        var i = Item(id: id, name: name, icon: icon, type: "armor", desc: desc, cost: cost, defBase: def, level: 1,
                     armorType: type, isEquippable: true)
        i.extra = extra
        return i
    }

    // MARK: Upgrading

    public enum Slot: Sendable { case weapon, armor }

    static func enchanterIndex(_ bag: [Item]) -> Int? {
        bag.firstIndex { $0.type == "enchanter" && charges($0) > 0 }
    }

    static func charges(_ i: Item) -> Int { if case .number(let n)? = i.extra["charges"] { return Int(n) }; return 0 }

    public static func hasEnchanter(_ forge: Forge) -> Bool { enchanterIndex(forge.bag) != nil }

    /// upgradeEquipped: an Enchanter charge pays first, otherwise gold. Both
    /// weapons and armor stop at level 10 (the web version let armor climb
    /// forever at ever-growing prices).
    public static func upgrade(_ slot: Slot, _ forge: inout Forge, wallet: Wallet, store: GameStore) -> (ok: Bool, message: String) {
        guard var item = slot == .weapon ? forge.weapon : forge.armor else {
            return (false, "Nothing equipped to upgrade. Go to the Inventory tab to equip something first.")
        }
        let lvl = item.level ?? 1
        if lvl >= maxLevel { return (false, "\(item.name) is already at maximum level \(maxLevel).") }
        let cost = upgradeCost(level: lvl, prof: forge.prof, store: store)
        var note = ""
        if let e = enchanterIndex(forge.bag) {
            let left = charges(forge.bag[e]) - 1
            if left <= 0 { forge.bag.remove(at: e) } else { forge.bag[e].extra["charges"] = .number(Double(left)) }
            note = "Enchanter used! Free upgrade applied." + (left > 0 ? " \(left) charges remaining. " : " Enchanter used up. ")
        } else {
            guard forge.gold >= cost, wallet.spendGold(cost) else {
                return (false, "Not enough gold. Need \(cost)g but you have \(forge.gold)g. Find an Enchanter to upgrade for free.")
            }
            forge.gold -= cost
        }
        item.level = lvl + 1
        if slot == .weapon {
            forge.weapon = item
            let r = item.weaponAttack
            return (true, note + "\(item.name) upgraded to Level \(lvl + 1)! Attack is now \(r.lowerBound) to \(r.upperBound).")
        }
        forge.armor = item
        return (true, note + "\(item.name) upgraded to Level \(lvl + 1)! Defense is now +\(item.armorDefense).")
    }

    // MARK: Buying

    public static func starterClaimed(_ store: GameStore) -> Bool { store.getItem("dd_starter_weapon_given") == "1" }

    public static func price(_ item: Item, forge: Forge, store: GameStore) -> Int {
        let c = item.cost ?? 0
        return c == 0 ? 0 : jsRound(Double(c) * shopMultiplier(prof: forge.prof, store: store))
    }

    static func freshId(_ id: String?) -> String { "\(id ?? "item")-\(Int(Date().timeIntervalSince1970 * 1000))" }

    /// buyBlacksmithWeapon: the Worn Blade is free, once.
    public static func buyWeapon(_ item: Item, _ forge: inout Forge, wallet: Wallet, store: GameStore) -> (ok: Bool, message: String) {
        let free = (item.cost ?? 0) == 0
        if free && starterClaimed(store) { return (false, "Already claimed your starter weapon.") }
        let cost = price(item, forge: forge, store: store)
        if !free {
            guard forge.gold >= cost, wallet.spendGold(cost) else { return (false, "Not enough gold.") }
            forge.gold -= cost
        } else {
            store.setItem("dd_starter_weapon_given", "1")
        }
        var bought = item
        bought.id = freshId(item.id)
        bought.extra["shopId"] = .string(item.id ?? "")
        forge.bag.append(bought)
        forge.stashed.append(bought)
        return (true, "Purchased \(item.name). Added to your inventory. Open inventory to equip it. Gold remaining: \(forge.gold).")
    }

    /// Whether this armor is already yours (in the bag or worn).
    public static func owns(_ armor: Item, _ forge: Forge) -> Bool {
        let key = armor.id
        func match(_ i: Item) -> Bool { i.id == key || i.extra["shopId"] == .string(key ?? "") }
        return forge.bag.contains(where: match) || forge.armor.map(match) == true
    }

    /// buyBlacksmithArmor (no discount, one of each).
    public static func buyArmor(_ item: Item, _ forge: inout Forge, wallet: Wallet) -> (ok: Bool, message: String) {
        if owns(item, forge) { return (false, "Already owned.") }
        let cost = item.cost ?? 0
        guard forge.gold >= cost, wallet.spendGold(cost) else { return (false, "Not enough gold. Need \(cost)g.") }
        forge.gold -= cost
        var bought = item
        bought.id = freshId(item.id)
        bought.extra["shopId"] = .string(item.id ?? "")
        forge.bag.append(bought)
        forge.stashed.append(bought)
        return (true, "Purchased \(item.name). Open inventory to equip it.")
    }

    // MARK: Equipping

    /// equipWeapon / equipArmor from the bag; what was worn goes back in.
    public static func equip(at index: Int, _ forge: inout Forge, sp: inout Int, maxSp: Int) -> String {
        guard forge.bag.indices.contains(index) else { return "That item is gone." }
        let item = forge.bag.remove(at: index)
        if item.isWeapon {
            if let old = forge.weapon { forge.bag.append(old) }
            forge.weapon = item
            if item.weaponType == "staff" { sp = min(maxSp, sp + 10) }
        } else if item.isArmor {
            if let old = forge.armor { forge.bag.append(old) }
            forge.armor = item
        } else {
            forge.bag.insert(item, at: index)
            return "\(item.name) can't be equipped."
        }
        return "Equipped \(item.icon) \(item.name) Level \(item.level ?? 1)."
    }

    public static func unequip(_ slot: Slot, _ forge: inout Forge) -> String {
        guard let item = slot == .weapon ? forge.weapon : forge.armor else { return "Nothing equipped." }
        forge.bag.append(item)
        if slot == .weapon { forge.weapon = nil } else { forge.armor = nil }
        return "\(item.name) unequipped."
    }

    // MARK: Reforging

    /// Reroll and next-tier prices by the weapon's current rarity.
    static let reforgeCosts = [80, 80, 150, 300, 600, 1200]
    static let rarityUpCosts = [100, 200, 400, 800, 1600]

    public static func rarityIndex(_ item: Item) -> Int {
        guard case .string(let id)? = item.extra["rarity"] else { return 0 }
        return Rarity.tiers.firstIndex { $0.id == id } ?? 0
    }

    public static func reforgeCost(_ item: Item) -> Int { reforgeCosts[rarityIndex(item)] }
    public static func rarityUpCost(_ item: Item) -> Int? {
        let i = rarityIndex(item)
        return i < Rarity.tiers.count - 1 ? rarityUpCosts[i] : nil
    }

    /// The weapon as it was before any rarity: the web version stacked a new
    /// rarity on top of the old one ("Rare Uncommon Sword" with both boosts),
    /// and a reforge that rolled Common changed nothing at all.
    static func base(_ item: Item) -> Item {
        var b = item
        let i = rarityIndex(item)
        guard i > 0 else { return b }
        let tier = Rarity.tiers[i]
        if case .array(let a)? = item.extra["baseAtk"] {
            b.atkBase = a.compactMap { if case .number(let n) = $0 { return Int(n) }; return nil }
        } else if let atk = item.atkBase {
            b.atkBase = atk.map { jsRound(Double($0) / tier.multiplier) }
        }
        if b.name.hasPrefix(tier.label + " ") { b.name = String(b.name.dropFirst(tier.label.count + 1)) }
        if let r = b.desc.range(of: "] "), b.desc.hasPrefix("["),
           case .string(let en)? = item.extra["rarityEffectName"], case .string(let ed)? = item.extra["rarityEffectDesc"] {
            let prefix = "[\(tier.label)] \(en) — \(ed) "
            if b.desc.hasPrefix(prefix) { b.desc = String(b.desc.dropFirst(prefix.count)) } else { b.desc = String(b.desc[r.upperBound...]) }
        }
        for k in ["rarity", "rarityLabel", "raritySymbol", "rarityEffect", "rarityEffectName", "rarityEffectDesc", "baseAtk"] { b.extra[k] = nil }
        return b
    }

    static func withRarity(_ tier: Rarity.Tier, _ item: Item, dice: inout some Dice) -> Item {
        let b = base(item)
        guard tier.id != "common" else { return b }
        var out = Rarity.apply(tier, to: b, dice: &dice)
        if let atk = b.atkBase { out.extra["baseAtk"] = .array(atk.map { .number(Double($0)) }) }
        return out
    }

    /// reforgeWeapon: a random new rarity for the equipped weapon.
    public static func reforge(_ forge: inout Forge, wallet: Wallet, dice: inout some Dice) -> (ok: Bool, message: String) {
        guard let wpn = forge.weapon else { return (false, "No weapon equipped.") }
        let cost = reforgeCost(wpn)
        guard forge.gold >= cost, wallet.spendGold(cost) else { return (false, "Not enough gold. Need \(cost) gold.") }
        forge.gold -= cost
        let tier = Rarity.roll(dice: &dice)
        forge.weapon = withRarity(tier, wpn, dice: &dice)
        return (true, "Reforged! New rarity: \(tier.symbol) \(tier.label).")
    }

    /// upgradeWeaponRarity: the next tier up.
    public static func raiseRarity(_ forge: inout Forge, wallet: Wallet, dice: inout some Dice) -> (ok: Bool, message: String) {
        guard let wpn = forge.weapon, let cost = rarityUpCost(wpn) else { return (false, "Your weapon is already Mythic.") }
        guard forge.gold >= cost, wallet.spendGold(cost) else { return (false, "Not enough gold. Need \(cost) gold.") }
        forge.gold -= cost
        let tier = Rarity.tiers[rarityIndex(wpn) + 1]
        forge.weapon = withRarity(tier, wpn, dice: &dice)
        return (true, "Weapon upgraded to \(tier.label)! \(tier.symbol) \(tier.label).")
    }

    // MARK: Durability

    public static func durability(_ w: Item?) -> Int {
        guard let w else { return maxDurability }
        if case .number(let n)? = w.extra["durability"] { return Int(n) }
        return maxDurability
    }

    public static func durabilityLabel(_ d: Int) -> String {
        d >= 80 ? "Perfect" : d >= 60 ? "Good" : d >= 40 ? "Worn" : d >= 20 ? "Damaged" : d > 0 ? "Critical" : "Broken"
    }

    /// getWeaponRepairCost: 60% of the weapon's price for the missing share.
    public static func repairCost(_ w: Item?) -> Int {
        guard let w else { return 0 }
        let missing = Double(maxDurability - durability(w)) / Double(maxDurability)
        return jsRound(missing * Double(w.cost ?? 50) * 0.6)
    }

    public static func repair(_ forge: inout Forge, wallet: Wallet) -> (ok: Bool, message: String) {
        guard var w = forge.weapon else { return (false, "No weapon equipped.") }
        let cost = repairCost(w)
        if cost == 0 { return (false, "Weapon is already in perfect condition.") }
        guard forge.gold >= cost, wallet.spendGold(cost) else { return (false, "Not enough gold. Need \(cost) gold to repair.") }
        forge.gold -= cost
        w.extra["durability"] = .number(Double(maxDurability))
        forge.weapon = w
        return (true, "Weapon repaired to perfect condition for \(cost) gold!")
    }

    /// getWeaponDamageMult: broken weapons hit for half, critical ones 75%.
    static func damageMultiplier(_ run: Run) -> Double {
        guard run.equippedWeapon != nil else { return 1 }
        let d = durability(run.equippedWeapon)
        return d == 0 ? 0.5 : d < 20 ? 0.75 : 1
    }

    /// degradeWeapon: 1 per attack, 2 per heavy strike, with warnings.
    static func degrade(_ run: inout Run, by amount: Int, log: inout [String]) {
        guard var w = run.equippedWeapon else { return }
        let before = durability(w)
        let d = max(0, before - amount)
        w.extra["durability"] = .number(Double(d))
        run.equippedWeapon = w
        func crossed(_ t: Int) -> Bool { before > t && d <= t }
        if crossed(0) { log.append("💔 \(w.name) has BROKEN! Your attacks deal half damage until repaired.") }
        else if crossed(20) { log.append("🔴 \(w.name) is Damaged! Repair it soon or it will break!") }
        else if crossed(40) { log.append("⚠ \(w.name) is Worn. Visit the Blacksmith to repair it.") }
    }

    /// The Last Blade loses a level every new floor and crumbles at level 1.
    public static func onFloor(_ run: inout Run) -> String? {
        guard var w = run.equippedWeapon, w.extra["degrading"] == .bool(true) else { return nil }
        let lvl = max(1, (w.level ?? 10) - 1)
        if lvl <= 1 {
            run.equippedWeapon = nil
            return "💔 The Last Blade has crumbled. It is gone."
        }
        w.level = lvl
        run.equippedWeapon = w
        return "💔 The Last Blade degrades to level \(lvl)."
    }

    /// sellItem: same prices as the Wandering Merchant (getSellPrice).
    public static func sell(at index: Int, _ forge: inout Forge, wallet: Wallet, store: GameStore) -> (ok: Bool, message: String) {
        guard forge.bag.indices.contains(index) else { return (false, "That item is gone.") }
        let item = forge.bag.remove(at: index)
        let price = Inventory.sellPrice(item)
        forge.gold += price
        wallet.addGold(price)
        store.setItem("dd_total_sells", String((jsParseInt(store.getItem("dd_total_sells")) ?? 0) + 1))
        return (true, "Sold \(item.name) for \(price) gold.")
    }
}
