import Foundation

/// The Mystery Coin Shop (COIN_UPGRADES): permanent upgrades bought with
/// Mystery Coins, saved in "dd_coin_upgrades" as {id: true}.
public enum CoinShop {
    public struct Upgrade: Sendable, Identifiable {
        public let id: String
        public let name: String
        public let icon: String
        public let desc: String
        public let cost: Int
    }

    public static let upgrades: [Upgrade] = [
        Upgrade(id: "cu-starting-gold", name: "Veteran Cache", icon: "💰", desc: "All new characters start with 15 extra gold.", cost: 10),
        Upgrade(id: "cu-hp-boost", name: "Hardened Soul", icon: "❤️", desc: "All characters gain +10 max HP permanently.", cost: 15),
        Upgrade(id: "cu-xp-boost", name: "Ancient Knowledge", icon: "📖", desc: "XP gain increased by 15% on all runs.", cost: 20),
        Upgrade(id: "cu-starting-blade", name: "Soulbound Blade", icon: "⚔️", desc: "All characters start with a +2 attack blade equipped.", cost: 20),
        Upgrade(id: "cu-second-wind", name: "Second Wind", icon: "💨", desc: "Once per run, survive a killing blow with 1 HP.", cost: 40),
        Upgrade(id: "cu-loot-boost", name: "Fortune Eye", icon: "👁️", desc: "Loot discovery chance increased by 8%.", cost: 15),
        Upgrade(id: "cu-sp-boost", name: "Arcane Reservoir", icon: "🔮", desc: "Start every run with 5 extra SP.", cost: 15),
        Upgrade(id: "cu-raid-boost", name: "Raid Veteran", icon: "⚔️", desc: "Start raids with 1 extra potion.", cost: 15),
        Upgrade(id: "cu-void-touched", name: "Void Touched", icon: "🗡️", desc: "Start every run with a random rare weapon in inventory.", cost: 50),
        Upgrade(id: "cu-alchemist-gift", name: "Alchemist's Gift", icon: "🧪", desc: "Start every run with 2 extra potions.", cost: 25),
        Upgrade(id: "cu-soul-surge", name: "Soul Surge", icon: "⚡", desc: "All skills cost 1 less SP permanently.", cost: 35),
        Upgrade(id: "cu-blood-pact", name: "Blood Pact", icon: "🩸", desc: "Steal 2 HP from every enemy you kill.", cost: 30),
        Upgrade(id: "cu-berserker-mark", name: "Berserker's Mark", icon: "💢", desc: "Deal +3 damage when below 50% HP.", cost: 25),
        Upgrade(id: "cu-treasure-sense", name: "Treasure Sense", icon: "💎", desc: "Start every run with a random gem in your inventory.", cost: 20),
        Upgrade(id: "cu-iron-skin", name: "Iron Skin", icon: "🛡️", desc: "All characters gain +2 DEF permanently.", cost: 20),
        Upgrade(id: "cu-lucky-descent", name: "Lucky Descent", icon: "🌟", desc: "First loot found every run is always rare quality.", cost: 35),
        Upgrade(id: "cu-ember-ward", name: "Ember Ward", icon: "🔥", desc: "Reduce all incoming enemy damage by 2 permanently.", cost: 30),
        Upgrade(id: "cu-void-pact", name: "Void Pact", icon: "🌑", desc: "+5% chance to find Mystery Coins while exploring dungeons.", cost: 30),
        Upgrade(id: "cu-third-eye", name: "Third Eye", icon: "👁", desc: "See enemy HP and special ability before every combat begins.", cost: 40),
        Upgrade(id: "cu-gamblers-spirit", name: "Gambler's Spirit", icon: "🎲", desc: "Once per run — double or halve your current gold. Your choice.", cost: 20),
        Upgrade(id: "cu-deaths-bargain", name: "Death's Bargain", icon: "⚰️", desc: "On death, unleash one final powerful counterattack.", cost: 45),
        Upgrade(id: "cu-hunters-mark", name: "Hunter's Mark", icon: "🏹", desc: "Your first attack in every combat is always a critical hit.", cost: 40),
        Upgrade(id: "cu-night-blessing", name: "Night Blessing", icon: "🌙", desc: "During Night Mode gain +5 ATK and +10% gold on all runs.", cost: 25),
        Upgrade(id: "cu-bloodhound", name: "Bloodhound's Nose", icon: "🐺", desc: "+5% chance for enemies to drop equipment on kill.", cost: 25),
        Upgrade(id: "cu-trapper", name: "Trapper's Kit", icon: "🪤", desc: "Start every run with a Soul Trap in your inventory.", cost: 30),
        Upgrade(id: "cu-warm-blood", name: "Warm Blood", icon: "💗", desc: "Heal 1 HP every time you reach a new floor.", cost: 20),
    ]

    /// The upgrades bought so far.
    public static func owned(_ store: GameStore) -> Set<String> {
        guard let s = store.getItem("dd_coin_upgrades"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) else { return [] }
        return Set(v.compactMap { k, val in
            switch val {
            case .bool(let b): return b ? k : nil
            case .number(let n): return n != 0 ? k : nil
            case .string(let s): return s.isEmpty ? nil : k
            case .null: return nil
            default: return k
            }
        })
    }

    /// renderCoinShop: the balance is the larger of "dd_mystery_coins" and the
    /// raid save's count, written back so both agree.
    public static func coins(_ store: GameStore) -> Int {
        let raid = RaidSave(store: store).coins
        let dd = jsParseInt(store.getItem("dd_mystery_coins")) ?? 0
        if raid > dd {
            store.setItem("dd_mystery_coins", String(raid))
            return raid
        }
        return dd
    }

    /// buyCoinUpgrade. False when it's already owned or there aren't enough coins.
    @discardableResult
    public static func buy(_ upgrade: Upgrade, store: GameStore) -> Bool {
        let have = coins(store)
        guard have >= upgrade.cost, !owned(store).contains(upgrade.id) else { return false }
        let left = have - upgrade.cost
        store.setItem("dd_mystery_coins", String(left))
        RaidSave(store: store).syncCoins(left)
        var all: [String: JSONValue] = [:]
        if let s = store.getItem("dd_coin_upgrades"), let d = s.data(using: .utf8),
           let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) { all = v }
        all[upgrade.id] = .bool(true)
        if let d = try? JSONEncoder().encode(all), let s = String(data: d, encoding: .utf8) {
            store.setItem("dd_coin_upgrades", s)
        }
        return true
    }

    /// Void Touched's weapons.
    static let rareWeapons: [Item] = [
        Item(name: "Void Shard", icon: "🌑", type: "weapon", desc: "A fragment of the void. Cold to the touch.", atkBase: [8, 16]),
        Item(name: "Soul Cleaver", icon: "⚔️", type: "weapon", desc: "Cleaves both flesh and spirit.", atkBase: [9, 17]),
        Item(name: "Eclipse Blade", icon: "🌘", type: "weapon", desc: "Darkens the air around it.", atkBase: [7, 18]),
    ]

    /// Treasure Sense's gems.
    static let gems: [Item] = [
        Item(name: "Void Crystal", icon: "💎", type: "gem", desc: "Worth 30 gold.", gold: 30),
        Item(name: "Shadow Shard", icon: "🔮", type: "gem", desc: "Worth 25 gold.", gold: 25),
        Item(name: "Ember Stone", icon: "🔥", type: "gem", desc: "Worth 20 gold.", gold: 20),
    ]

    /// applyCoinUpgrades and the starting gold from initDungeon. Returns log lines.
    @discardableResult
    public static func apply(_ owned: Set<String>, to run: inout Run, dice: inout some Dice, wallet: Wallet) -> [String] {
        var log: [String] = []
        run.coinUpgrades = owned
        if owned.contains("cu-hp-boost") { run.maxHp += 10; run.hp = min(run.maxHp, run.hp + 10) }
        if owned.contains("cu-starting-blade") { run.atkBonus += 2 }
        if owned.contains("cu-sp-boost") { run.sp = min(run.maxSp, run.sp + 5) }
        if owned.contains("cu-iron-skin") { run.defBonus += 2 }
        run.secondWind = owned.contains("cu-second-wind")
        run.deathsBargain = owned.contains("cu-deaths-bargain")
        if owned.contains("cu-trapper") {
            run.inventory.append(Item(name: "Soul Trap", icon: "🪤", type: "soul-trap",
                                      desc: "Captures the current enemy as a permanent minion. Use during combat."))
        }
        if owned.contains("cu-gamblers-spirit") && !run.gamblerUsed
            && !run.inventory.contains(where: { $0.type == "gamblers-spirit" }) {
            run.inventory.append(Item(name: "Gambler's Spirit", icon: "🎲", type: "gamblers-spirit",
                                      desc: "Once per run — double or halve your gold. Your choice. No refunds."))
        }
        if owned.contains("cu-void-touched") {
            var w = rareWeapons[dice.roll(0...(rareWeapons.count - 1))]
            w.extra["rarity"] = .string("rare")
            run.inventory.append(w)
        }
        if owned.contains("cu-alchemist-gift") {
            for _ in 0..<2 {
                run.inventory.append(Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "Restores 40 HP.", heal: 40))
            }
        }
        // The web version put the gem in the bag; here gems are always gold.
        if owned.contains("cu-treasure-sense") {
            let gem = gems[dice.roll(0...(gems.count - 1))]
            let g = gem.gold ?? 0
            run.gold += g
            wallet.addGold(g)
            log.append("💎 Treasure Sense — \(gem.icon) \(gem.name), worth \(g) gold.")
        }
        if owned.contains("cu-starting-gold") {
            run.gold += 15
            wallet.addGold(15)
        }
        return log
    }

    /// isNightTime: 8 PM to 8 AM.
    public static func isNight(hour: Int) -> Bool { hour >= 20 || hour < 8 }
    public static func isNightNow() -> Bool { isNight(hour: Calendar.current.component(.hour, from: Date())) }
}

extension RaidSave {
    /// The raid save's own Mystery Coin count.
    public var coins: Int {
        guard let s = store.getItem("dd_raid"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d),
              case .number(let n)? = v["mysteryCoins"] else { return 0 }
        return Int(n)
    }
}
