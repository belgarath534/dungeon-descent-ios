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
        /// Gold for the caller to add to the shared wallet.
        public var gold = 0
    }

    // MARK: Using items

    /// Uses the item at `index`. Items never cost a combat turn, as in the web version.
    public static func use(_ run: inout Run, at index: Int) -> Outcome {
        var d = SystemDice()
        return use(&run, at: index, dice: &d)
    }

    public static func use(_ run: inout Run, at index: Int, dice: inout some Dice) -> Outcome {
        guard run.inventory.indices.contains(index) else { return Outcome(message: "That item is gone.", used: false) }
        let item = run.inventory[index]
        var out = Outcome(message: "")

        if ShapeshifterMask.isMask(item) { return ShapeshifterMask.use(&run, at: index) }
        if let o = Intros.use(&run, at: index) { return o }

        // Mirror Fragment (Shadow World): purges every corruption stack.
        if item.extra["shadowItem"] == .string("mirrorFragment") {
            guard run.shadowCorruption > 0 else { return Outcome(message: "You have no corruption to purge.", used: false) }
            run.shadowCorruption = 0
            run.inventory.remove(at: index)
            return Outcome(message: "🪞 The Mirror Fragment shatters. All corruption purged.")
        }

        // The Whispering Forest's Music Box: its melody clears the corruption.
        if WhisperingForest.isMusicBox(item) {
            guard WhisperingForest.here(run) else {
                return Outcome(message: "The Music Box only works in the Whispering Forest.", used: false)
            }
            run.forestCorruption = 0
            run.inventory.remove(at: index)
            return Outcome(message: "🎵 You open the Music Box. The melody plays. The corruption inside you fades to nothing.")
        }

        if HollowEvents.isBoxItem(item) {
            return Outcome(message: "The Music Box is for the Weeping Child. It will be offered when you meet her.", used: false)
        }

        // Daily Dungeon's Dry Run: no potions or elixirs at all.
        if Challenges.has(run, "no-potions") && (item.type.contains("potion") || item.type == "elixir" || item.type == "heal") {
            return Outcome(message: "Daily modifier Dry Run: potions cannot be used in this run.", used: false)
        }
        // Cursed Day: no potions in a fight.
        if DailyChallenge.blocksPotions(run) && (item.type.contains("potion") || item.type == "elixir" || item.type == "heal") {
            return Outcome(message: "Cursed Day: potions cannot be used in combat.", used: false)
        }
        if let seasonal = SeasonalItems.use(&run, at: index) { return seasonal }

        switch item.type {
        case "potion":
            let cleanses = item.name == "Null Potion" && run.shadowCorruption > 0
            guard run.hp < run.maxHp || cleanses || Alchemy.hasEffect(item) else { return Outcome(message: "Your health is already full.", used: false) }
            if Alchemy.effect(item) == "life-steal" && !run.inCombat {
                return Outcome(message: "No enemy to drain. Use this in combat.", used: false)
            }
            if let fx = Alchemy.applyEffect(item, &run) {
                let heal = (item.heal ?? 0) >= 9999 ? 0 : jsRound(Double(item.heal ?? 0) * run.potionMult)
                if heal > 0 { run.hp = min(run.maxHp, run.hp + heal) }
                out.message = "You drink \(item.name)." + (heal > 0 ? " Restored \(heal) HP." : "") + " " + fx + " HP: \(run.hp) of \(run.maxHp)."
                out.enemyDied = run.inCombat && run.enemy?.isDead == true
                break
            }
            var heal = jsRound(Double(item.heal ?? 40) * run.potionMult)
            heal = Races.potionHeal(run, heal)
            if let b = run.weather?.potionBoost, b > 0 { heal = jsRound(Double(heal) * (1 + b)) }
            run.hp = min(run.maxHp, run.hp + heal)
            out.message = "You drink \(item.name), restoring \(heal) HP. HP: \(run.hp) of \(run.maxHp)."
            if cleanses {
                run.shadowCorruption = 0
                out.message += " All corruption removed."
            }
            if WhisperingForest.here(run) && run.forestCorruption > 0 {
                run.forestCorruption = max(0, run.forestCorruption - WhisperingForest.potionCleanse)
                out.message += " The forest's corruption recedes to \(run.forestCorruption) percent."
            }
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
        case "ring", "relic":
            return Outcome(message: "\(item.name) works while you carry it.", used: false)
        case "enchanter":
            let left = Blacksmith.charges(item)
            return Outcome(message: "Enchanter. \(left) charge\(left == 1 ? "" : "s") remaining. Go to the Blacksmith and upgrade a weapon — the Enchanter will be used automatically instead of gold.", used: false)
        case "soul-trap":
            return Outcome(message: "Use the Soul Trap button during a fight to capture the enemy.", used: false)
        case "skill-orb":
            return Outcome(message: "Skill Orbs are used from your Home, under Skill Upgrade.", used: false)
        case "warding-bell":
            run.wardingBell += 1
            out.message = "🔔 Warding Bell attuned. It will ring out and warn you the next time you search a room with a trap."
        case "cursed":
            // Cursed Vial / Cursed Heirloom: one of six things, good or bad.
            switch dice.roll(0...5) {
            case 0: run.hp = min(run.maxHp, run.hp + 60); out.message = "Massive heal! +60 HP. Lucky."
            case 1: run.hp = max(1, run.hp - 30); out.message = "Burns! -30 HP. Unlucky."
            case 2: run.sp = min(run.maxSp, run.sp + 25); out.message = "SP surge! +25 SP."
            case 3: run.atkBonus += 6; out.message = "Rage! +6 attack permanently this run."
            case 4: run.defBonus = max(0, run.defBonus - 2); run.hp = max(1, run.hp - 15); out.message = "Weakness! -2 defense, -15 HP."
            default: run.gold += 40; out.gold = 40; out.message = "Gold appears from nowhere. +40 gold."
            }
            out.message = "\(item.name) consumed. " + out.message
        case _ where Alchemy.tacticalTypes.contains(item.type):
            let o = Alchemy.useTactical(item, &run) ?? Outcome(message: "Use this in combat.", used: false)
            guard o.used else { return o }
            out = o
        default:
            return Outcome(message: "\(item.name) can't be used in the Swift version yet.", used: false)
        }

        // Healing breaks the "no potions" daily quest.
        if ["potion", "elixir", "heal"].contains(item.type) { run.usedPotion = true }
        run.inventory.remove(at: index)
        return out
    }

    /// Fills in which rooms a Scroll of Reveal shows. Call right after using one.
    public static func reveal(_ run: inout Run, dice: inout some Dice) -> String {
        while run.upcomingRooms.count < 3 { run.upcomingRooms.append(Rooms.roll(run.difficulty, bonus: (run.weather?.combatBonus ?? 0) + DailyChallenge.combatBonus(run), dice: &dice)) }
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
            if item.weaponType == "staff" { run.sp = min(run.maxSp, run.sp + 10) }
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
        public var mysteryCoin = false
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

    /// WEAPON_TYPES and ARMOR_TYPES: the gear enemies drop.
    static let weaponTypes: [(id: String, icon: String, name: String, atk: [Int], desc: String)] = [
        ("sword", "⚔️", "Sword", [5, 8], "Balanced. Reliable damage."),
        ("mace", "🔨", "Mace", [6, 10], "Slow but hits hard."),
        ("axe", "🪓", "Axe", [7, 11], "High variance. Feast or famine."),
        ("dagger", "🗡️", "Dagger", [3, 7], "Fast. 15% chance to strike twice."),
        ("staff", "🪄", "Staff", [4, 9], "Boosts SP by 10 when equipped."),
        ("bow", "🏹", "Bow", [5, 10], "First strike every combat."),
    ]
    static let armorTypes: [(id: String, icon: String, name: String, def: Int, desc: String)] = [
        ("light", "🥋", "Light Armor", 2, "Fast. +1 speed, low protection."),
        ("medium", "🛡️", "Medium Armor", 4, "Balanced protection."),
        ("heavy", "⛓️", "Heavy Armor", 7, "High protection. -1 ATK."),
    ]

    /// checkEquipmentDrop / rollEquipmentDrop: 15% of kills (20% with
    /// Bloodhound's Nose) drop a weapon or armor a level higher every 3
    /// floors, with a rolled rarity. It goes in the bag.
    public static func equipmentDrop(_ run: inout Run, dice: inout some Dice) -> Item? {
        guard dice.chance(0.15 + (run.has("cu-bloodhound") ? 0.05 : 0)) else { return nil }
        let item = equipment(level: max(1, 1 + run.floor / 3), tier: Rarity.roll(dice: &dice), dice: &dice)
        run.inventory.append(item)
        return item
    }

    /// A random weapon or armor of a level and rarity.
    static func equipment(level: Int, tier: Rarity.Tier, dice: inout some Dice) -> Item {
        var item: Item
        if dice.chance(0.5) {
            let t = weaponTypes[dice.roll(0...(weaponTypes.count - 1))]
            item = Item(id: "drop-weapon-\(Int(Date().timeIntervalSince1970 * 1000))-\(dice.roll(0...9999))", name: t.name,
                        icon: t.icon, type: "weapon", desc: t.desc, atkBase: t.atk, level: level, weaponType: t.id, isEquippable: true)
        } else {
            let t = armorTypes[dice.roll(0...(armorTypes.count - 1))]
            item = Item(id: "drop-armor-\(Int(Date().timeIntervalSince1970 * 1000))-\(dice.roll(0...9999))", name: t.name,
                        icon: t.icon, type: "armor", desc: t.desc, defBase: t.def, level: level, armorType: t.id, isEquippable: true)
        }
        if tier.id != "common" { item = Rarity.apply(tier, to: item, dice: &dice) }
        return item
    }

    /// getSellPrice
    public static func sellPrice(_ item: Item) -> Int {
        let level = item.level ?? 1
        switch item.type {
        case "potion": return item.heal.map { $0 * 15 / 100 } ?? 5
        case "gem": return item.gold ?? 10
        case "ring": return 15
        case "weapon": return (item.cost.map { $0 * 35 / 100 } ?? 20) + (level - 1) * 15
        case "armor": return (item.cost.map { $0 * 35 / 100 } ?? 15) + (level - 1) * 10
        default: return 5
        }
    }

    /// renderShopSell's sale: the item goes, its price joins your gold, and
    /// "dd_total_sells" counts toward the selling achievements.
    @discardableResult
    public static func sell(_ run: inout Run, at index: Int, wallet: Wallet, store: GameStore) -> Int? {
        guard run.inventory.indices.contains(index) else { return nil }
        let item = run.inventory.remove(at: index)
        let price = sellPrice(item)
        run.gold += price
        wallet.addGold(price)
        store.setItem("dd_total_sells", String((jsParseInt(store.getItem("dd_total_sells")) ?? 0) + 1))
        return price
    }

    /// A loot room (28% of rooms): one random item from the dungeon's loot table.
    public static func lootRoom(_ run: inout Run, dice: inout some Dice, wallet: Wallet) -> Find {
        let table = ItemTables.loot(for: run.dungeon)
        var item = table[dice.roll(0...(table.count - 1))]
        var lucky = false
        if item.isWeapon || item.isArmor {
            var tier = Rarity.roll(dice: &dice)
            // Lucky Descent: the run's first weapon or armor is rare.
            if run.has("cu-lucky-descent") && !run.luckyDescentUsed,
               let rare = Rarity.tiers.first(where: { $0.id == "rare" }) {
                run.luckyDescentUsed = true
                tier = rare
                lucky = true
            }
            item = Rarity.apply(tier, to: item, dice: &dice)
        }
        // Void Pact: 5% chance of a Mystery Coin.
        let coin = run.has("cu-void-pact") && dice.chance(0.05)
        var found = lootRoomFind(&run, item, wallet: wallet)
        if lucky { found.message = "🌟 Lucky Descent — rare quality guaranteed! " + found.message }
        if coin {
            found.mysteryCoin = true
            found.message += " 🌑 Void Pact — Mystery Coin found!"
        }
        return found
    }

    static func lootRoomFind(_ run: inout Run, _ item: Item, wallet: Wallet) -> Find {
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
        let findChance = (run.prof == "Thief" ? 0.50 : 0.35) + (run.has("cu-loot-boost") ? 0.08 : 0)
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
            // Trap sense: a Scholar, the Frost Sprite, or a Warding Bell's one ring.
            if run.prof == "Scholar" {
                return Find(message: "Your scholarly instincts warn you. You step around the trap easily.", trap: "avoided")
            }
            if run.spirit == "frost-sprite" {
                return Find(message: "❄️ Frost Sprite senses the trap! You step around it easily.", trap: "avoided")
            }
            if run.wardingBell > 0 {
                run.wardingBell -= 1
                return Find(message: "🔔 The Warding Bell rings sharply. You sense the trap and step around it.", trap: "avoided")
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
        case "poison" where Races.immune(run): break
        case "poison", "burn":
            run.poisonTurns = trap.turns
            run.poisonDamage = trap.effect == "burn" ? 6 : 8
        case "sp": run.sp = max(0, run.sp - 8)
        case "freeze": if run.armorEffect != "juggernaut" && !Races.immune(run) { run.frozen = true }
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
        public init(id: Int, item: Item, sold: Bool = false) { self.id = id; self.item = item; self.sold = sold }
    }

    /// Four random items from the dungeon's stock, like openShop().
    public static func shopStock(for run: Run, dice: inout some Dice) -> [ShopItem] {
        var stock = ItemTables.shop(for: run.dungeon)
        var picks: [ShopItem] = []
        while picks.count < 4 && !stock.isEmpty {
            picks.append(ShopItem(id: picks.count, item: stock.remove(at: dice.roll(0...(stock.count - 1)))))
        }
        if let classItem = Intros.classShopItem(run) { picks.append(ShopItem(id: picks.count, item: classItem)) }
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
        let cost = Races.shopPrice(Spirits.shopPrice(RunModifiers.potionCost(entry.item, price(entry.item, hour: hour), run), run), run)
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

    /// Adds one item to the stash like addToGlobalInventory(): one of each
    /// music player, enchanter, soul trap and skill orb, and gear unique by name.
    public func add(_ item: Item) {
        var inv = items
        if ["music-player", "enchanter", "soul-trap", "skill-orb"].contains(item.type),
           inv.contains(where: { $0.type == item.type }) { return }
        if item.isWeapon || item.isArmor || BossRelics.isRelic(item), inv.contains(where: { $0.type == item.type && $0.name == item.name }) { return }
        inv.append(item)
        save(inv)
    }

    /// What a run keeps when the hero dies (showDefeat): gear and the
    /// enchanter, soul trap, music player and skill orb.
    public func keepOnDeath(from run: Run) {
        for item in run.inventory where item.isWeapon || item.isArmor || BossRelics.isRelic(item)
            || ["enchanter", "soul-trap", "music-player", "skill-orb"].contains(item.type) {
            add(item)
        }
    }

    /// Saves what a run keeps: gear and the keep-types, without duplicates.
    public func keep(from run: Run) {
        var seen = Set<String>()
        let kept = run.inventory.filter { i in
            if i.isWeapon || i.isArmor || BossRelics.isRelic(i) { return seen.insert(i.type + "::" + i.name).inserted }
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

/// Small drops from searches and kills: the Enchanter (tryDropEnchanter, 2.5%
/// of both), a Spirit Orb (checkSpiritOrbDrop, 5% of searches: a spirit this
/// character hasn't earned) and July 4th Fireworks (checkFireworkDrop, 15% of
/// kills during the event).
public enum Drops {
    public static func enchanter() -> Item {
        var it = Item(name: "Enchanter", icon: "✨", type: "enchanter", desc: "Rare crystal. Use at the Blacksmith for 3 free weapon upgrades.")
        it.extra["charges"] = .number(3)
        return it
    }

    /// Adds an Enchanter to the bag 2.5% of the time. Returns it for the caller
    /// to keep in the saved items too.
    public static func rollEnchanter(_ run: inout Run, dice: inout some Dice) -> Item? {
        guard dice.chance(0.025) else { return nil }
        let e = enchanter()
        run.inventory.append(e)
        return e
    }

    /// A spirit this character hasn't earned, 5% of searches.
    public static func spiritOrb(earned: Set<String>, dice: inout some Dice) -> Spirit? {
        guard dice.chance(0.05) else { return nil }
        let left = Spirits.all.filter { !Spirits.starterIds.contains($0.id) && !earned.contains($0.id) }
        guard !left.isEmpty else { return nil }
        return left[dice.roll(0...(left.count - 1))]
    }

    public static func firework(_ run: inout Run, dice: inout some Dice) -> Bool {
        guard run.event == "july4", dice.chance(0.15), let f = SeasonalItems.all["liberty-firework"] else { return false }
        var it = f
        it.name = "Firework"
        run.inventory.append(it)
        return true
    }
}
