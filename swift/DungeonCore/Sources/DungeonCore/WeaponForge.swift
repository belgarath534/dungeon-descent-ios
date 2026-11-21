import Foundation

/// WEAPON FORGE SYSTEM (Home → Forge): enemies drop materials, and recipes
/// turn them into weapons with a random special effect.
///
/// The web version had two bugs here: a forged weapon kept its attack in
/// `atkRange`, which nothing read, so it always hit for the default 5–8; and
/// its special effect was saved but never used in a fight. Here the weapon
/// hits for its recipe's range and every effect works.
public enum WeaponForge {
    public struct Material: Sendable {
        public let id, name, icon, desc, rarity: String
    }

    public struct Effect: Sendable {
        public let id, name, desc: String
    }

    public struct Recipe: Sendable {
        public let id, name, icon: String
        public let atk: ClosedRange<Int>
        /// Material id and count, in the web version's order.
        public let materials: [(id: String, count: Int)]
        public let desc: String
    }

    /// FORGE_MATERIALS
    public static let materials: [Material] = [
        Material(id: "iron-scrap", name: "Iron Scrap", icon: "🔩", desc: "Common metal. Found everywhere.", rarity: "common"),
        Material(id: "bone-shard", name: "Bone Shard", icon: "🦴", desc: "Brittle but sharp. From undead foes.", rarity: "common"),
        Material(id: "wolf-fang", name: "Wolf Fang", icon: "🐺", desc: "Sharp and durable.", rarity: "common"),
        Material(id: "goblin-gem", name: "Goblin Gem", icon: "💎", desc: "Stolen goods. Valuable.", rarity: "uncommon"),
        Material(id: "frost-crystal", name: "Frost Crystal", icon: "❄️", desc: "Icy shard from frozen foes.", rarity: "uncommon"),
        Material(id: "fire-ember", name: "Fire Ember", icon: "🔥", desc: "Still burning somehow.", rarity: "uncommon"),
        Material(id: "shadow-dust", name: "Shadow Dust", icon: "🌑", desc: "Left behind by shadow creatures.", rarity: "rare"),
        Material(id: "void-fragment", name: "Void Fragment", icon: "🌀", desc: "Unstable essence of the void.", rarity: "rare"),
        Material(id: "dragon-scale", name: "Dragon Scale", icon: "🐉", desc: "Nearly indestructible.", rarity: "rare"),
    ]

    /// FORGE_SPECIAL_EFFECTS. Enemies have no defense here, so Shattering
    /// cracks their guard instead: each hit you land adds 2 damage, up to 10.
    public static let effects: [Effect] = [
        Effect(id: "burn", name: "Burning", desc: "15% chance to burn enemy for 5 dmg/turn for 3 turns."),
        Effect(id: "lifesteal", name: "Life Steal", desc: "Heal 10% of damage dealt."),
        Effect(id: "crit-boost", name: "Keen Edge", desc: "+10% critical hit chance."),
        Effect(id: "poison", name: "Venomous", desc: "20% chance to poison enemy for 4 dmg/turn for 3 turns."),
        Effect(id: "gold-find", name: "Lucky", desc: "Enemies drop +5 gold on kill."),
        Effect(id: "sp-regen", name: "Arcane", desc: "Restore 2 SP each time you attack."),
        Effect(id: "armor-break", name: "Shattering", desc: "Each hit cracks the enemy's guard: +2 damage per hit landed, up to +10."),
        Effect(id: "double-hit", name: "Swift", desc: "10% chance to attack twice."),
        Effect(id: "thorns", name: "Thorned", desc: "Reflect 15% of damage taken back to enemy."),
        Effect(id: "execute", name: "Executioner", desc: "+50% damage to enemies below 25% HP."),
    ]

    /// FORGE_RECIPES
    public static let recipes: [Recipe] = [
        Recipe(id: "iron-blade", name: "Iron Blade", icon: "⚔️", atk: 8...14, materials: [("iron-scrap", 3)], desc: "A reliable blade forged from scrap metal."),
        Recipe(id: "bone-dagger", name: "Bone Dagger", icon: "🦴", atk: 6...16, materials: [("bone-shard", 3)], desc: "Light and vicious. Fast strikes."),
        Recipe(id: "fang-sword", name: "Fang Sword", icon: "🐺", atk: 10...18, materials: [("wolf-fang", 2), ("iron-scrap", 2)], desc: "Serrated like a beast's jaw."),
        Recipe(id: "frost-blade", name: "Frost Blade", icon: "❄️", atk: 12...20, materials: [("frost-crystal", 2), ("iron-scrap", 2)], desc: "Chills to the bone."),
        Recipe(id: "ember-sword", name: "Ember Sword", icon: "🔥", atk: 14...22, materials: [("fire-ember", 2), ("iron-scrap", 2)], desc: "Burns with an inner fire."),
        Recipe(id: "shadow-blade", name: "Shadow Blade", icon: "🌑", atk: 16...26, materials: [("shadow-dust", 2), ("bone-shard", 2)], desc: "Strikes from the darkness."),
        Recipe(id: "void-cleaver", name: "Void Cleaver", icon: "🌀", atk: 18...30, materials: [("void-fragment", 2), ("goblin-gem", 1)], desc: "Tears through reality itself."),
        Recipe(id: "dragon-blade", name: "Dragon Blade", icon: "🐉", atk: 22...36, materials: [("dragon-scale", 2), ("fire-ember", 1)], desc: "The pinnacle of forged weapons."),
    ]

    public static func material(_ id: String) -> Material? { materials.first { $0.id == id } }
    public static func effect(_ id: String) -> Effect? { effects.first { $0.id == id } }

    // MARK: Stash (dd_forge_stash)

    public static func stash(_ store: GameStore) -> [String: Int] {
        guard let s = store.getItem("dd_forge_stash"), let d = s.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: Double].self, from: d) else { return [:] }
        return raw.mapValues { Int($0) }.filter { $0.value > 0 }
    }

    static func save(_ stash: [String: Int], _ store: GameStore) {
        let kept = stash.filter { $0.value > 0 }
        if let d = try? JSONEncoder().encode(kept), let s = String(data: d, encoding: .utf8) {
            store.setItem("dd_forge_stash", s)
        }
    }

    public static func add(_ id: String, _ count: Int = 1, store: GameStore) {
        var s = stash(store)
        s[id, default: 0] += count
        save(s, store)
    }

    /// tryDropMaterial: 15% on a kill. Only commons before floor 5, and no
    /// rares before floor 8.
    public static func drop(floor: Int, store: GameStore, dice: inout some Dice) -> Material? {
        guard dice.chance(0.15) else { return nil }
        let pool = floor >= 8 ? materials
            : floor >= 5 ? materials.filter { $0.rarity != "rare" }
            : materials.filter { $0.rarity == "common" }
        let m = pool[dice.roll(0...(pool.count - 1))]
        add(m.id, store: store)
        return m
    }

    public static func canCraft(_ r: Recipe, _ stash: [String: Int]) -> Bool {
        r.materials.allSatisfy { (stash[$0.id] ?? 0) >= $0.count }
    }

    /// "Iron Scrap x3, Bone Shard x2"
    public static func needs(_ r: Recipe) -> String {
        r.materials.map { m in
            let mat = material(m.id)
            return "\(mat?.icon ?? "") \(mat?.name ?? m.id) x\(m.count)"
        }.joined(separator: ", ")
    }

    // MARK: Crafting

    /// forgeCraft: spends the materials and forges the weapon with a random effect.
    public static func craft(_ id: String, store: GameStore, dice: inout some Dice, now: Date = Date()) -> Item? {
        guard let r = recipes.first(where: { $0.id == id }) else { return nil }
        var s = stash(store)
        guard canCraft(r, s) else { return nil }
        for m in r.materials { s[m.id, default: 0] -= m.count }
        save(s, store)
        let fx = effects[dice.roll(0...(effects.count - 1))]
        var w = Item(id: "\(r.id)_\(Int(now.timeIntervalSince1970 * 1000))", name: r.name, icon: r.icon, type: "weapon",
                     desc: r.desc, atkBonus: r.atk.lowerBound, atkBase: [r.atk.lowerBound, r.atk.upperBound], level: 1)
        w.extra["atkRange"] = .array([.number(Double(r.atk.lowerBound)), .number(Double(r.atk.upperBound))])
        w.extra["forgeRecipe"] = .string(r.id)
        apply(fx, to: &w, recipe: r)
        return w
    }

    static func apply(_ fx: Effect, to w: inout Item, recipe: Recipe) {
        w.extra["forgeEffect"] = .string(fx.id)
        w.extra["forgeEffectName"] = .string(fx.name)
        w.desc = "\(recipe.desc) [\(fx.name): \(fx.desc)]"
    }

    /// forgeReroll: 2 Iron Scraps for a new effect. Nil when you're short.
    public static func reroll(_ w: Item, store: GameStore, dice: inout some Dice) -> Item? {
        var s = stash(store)
        guard (s["iron-scrap"] ?? 0) >= 2,
              case .string(let rid)? = w.extra["forgeRecipe"], let r = recipes.first(where: { $0.id == rid }) else { return nil }
        s["iron-scrap", default: 0] -= 2
        save(s, store)
        var out = w
        apply(effects[dice.roll(0...(effects.count - 1))], to: &out, recipe: r)
        return out
    }

    /// forgeKeep: into the global inventory, counted for The Forger
    /// achievements. The stash keeps one weapon of each name, so a second
    /// forged Iron Blade is named for its effect ("Iron Blade (Burning)")
    /// instead of vanishing like the web version's would on the next run.
    public static func keep(_ w: Item, store: GameStore) -> Item {
        let inv = GlobalInventory(store: store)
        let names = Set(inv.items.filter(\.isWeapon).map(\.name))
        var item = w
        if names.contains(item.name) {
            let base = "\(w.name) (\(w.forgeEffectName ?? "Forged"))"
            item.name = base
            var n = 2
            while names.contains(item.name) { item.name = "\(base) \(n)"; n += 1 }
        }
        inv.add(item)
        let count = Int(store.getItem("dd_forge_count") ?? "0") ?? 0
        store.setItem("dd_forge_count", String(count + 1))
        return item
    }

    public static func count(_ store: GameStore) -> Int { Int(store.getItem("dd_forge_count") ?? "0") ?? 0 }

    // MARK: In combat

    static func fx(_ run: Run) -> String? { run.equippedWeapon?.forgeEffect }

    /// Keen Edge
    static func critBonus(_ run: Run) -> Double { fx(run) == "crit-boost" ? 0.10 : 0 }

    /// Executioner and Shattering, on the damage of a hit.
    static func damage(_ run: Run, _ dmg: Int, log: inout [String]) -> Int {
        guard let e = run.enemy else { return dmg }
        switch fx(run) {
        case "execute" where Double(e.hp) / Double(max(1, e.maxHp)) < 0.25:
            log.append("🔨 Executioner — +50% damage to the weakened foe!")
            return jsRound(Double(dmg) * 1.5)
        case "armor-break":
            return dmg + min(10, e.hitsTaken * 2)
        default: return dmg
        }
    }

    /// Effects after a landed hit: burn, poison, life steal, SP and a second strike.
    static func afterHit(_ run: inout Run, _ dmg: Int, dice: inout some Dice, log: inout [String]) {
        guard dmg > 0, let f = fx(run), var e = run.enemy else { return }
        switch f {
        case "burn" where !e.isDead && dice.chance(0.15):
            e.dotDamage = 5; e.dotTurns = max(e.dotTurns, 3)
            log.append("🔥 Your blade sets \(e.name) burning — 5 damage a turn for 3 turns!")
        case "poison" where !e.isDead && dice.chance(0.20):
            e.dotDamage = max(e.dotDamage, 4); e.dotTurns = max(e.dotTurns, 3)
            log.append("🐍 Venom seeps in — \(e.name) is poisoned!")
        case "lifesteal":
            let h = max(1, jsRound(Double(dmg) * 0.10))
            if run.hp < run.maxHp {
                run.hp = min(run.maxHp, run.hp + h)
                log.append("🩸 Life Steal heals \(h) HP.")
            }
        case "sp-regen":
            run.sp = min(run.maxSp, run.sp + 2)
        case "double-hit" where !e.isDead && dice.chance(0.10):
            e.hp = max(0, e.hp - dmg)
            log.append("⚡ Swift — you strike twice for another \(dmg)!")
        default: break
        }
        run.enemy = e
    }

    /// Thorned: 15% of the damage you take goes back.
    static func thorns(_ run: Run, taken: Int) -> Int {
        fx(run) == "thorns" && taken > 0 ? jsRound(Double(taken) * 0.15) : 0
    }

    /// Lucky: 5 more gold a kill.
    static func gold(_ run: Run) -> Int { fx(run) == "gold-find" ? 5 : 0 }
}

extension Item {
    public var forgeEffect: String? {
        if case .string(let s)? = extra["forgeEffect"] { return s }
        return nil
    }

    public var forgeEffectName: String? {
        if case .string(let s)? = extra["forgeEffectName"] { return s }
        return forgeEffect.flatMap { WeaponForge.effect($0)?.name }
    }
}
