import Foundation

/// ALCHEMY SYSTEM (Home → Alchemy): buy ingredients or find them on kills,
/// brew potions. Alchemists brew stronger potions and two recipes of their
/// own; anyone else's brew goes wrong one time in five. Also the tactical
/// potions (Mirror Flask, Rage Tonic …) that the shops sell.
///
/// Web bugs fixed here: Bloodfire's burn, Glacier Tonic's stun and the Time
/// Potion did nothing; and the tactical potions ignored the stronger numbers
/// an Alchemist brewed into them.
public enum Alchemy {
    public struct Ingredient: Sendable {
        public let id, name, icon: String
        public let cost: Int
        public let desc: String
    }

    public struct Recipe: Sendable {
        public let id, name, icon: String
        public let ingredients: [(id: String, count: Int)]
        public let desc: String
        public var alchemistOnly = false
        /// The potion, brewed by an Alchemist or not.
        let craft: @Sendable (Bool) -> Item
    }

    /// Potion effects that last beyond one fight, like the web version's DS._ fields.
    public struct Brews: Codable, Equatable, Sendable {
        public var burnNext = false
        public var stunNext = false
        public var dodge = 0.0
        public var dodgeTurns = 0
        public var mirror = false
        public var phantomTurns = 0
        public var gravityTurns = 0
        public var leech = 0.0
        public var leechTurns = 0
        public var rageTurns = 0
        public var fogTurns = 0
        public var timeStop = 0
        public var corrDamage = 0
        public var corrTurns = 0
        public init() {}
    }

    /// ALCHEMY_INGREDIENTS
    public static let ingredients: [Ingredient] = [
        Ingredient(id: "bone-powder", name: "Bone Powder", icon: "🦴", cost: 8, desc: "Ground from undead remains. Common drop from skeleton enemies."),
        Ingredient(id: "glowing-shroom", name: "Glowing Mushroom", icon: "🍄", cost: 10, desc: "Found in dark dungeon corners. Bioluminescent properties."),
        Ingredient(id: "blood-vial", name: "Blood Vial", icon: "🩸", cost: 12, desc: "Carefully collected from fallen enemies. Rare drop."),
        Ingredient(id: "void-herb", name: "Void Herb", icon: "🌿", cost: 14, desc: "Grows only in void-touched dungeons. Resonates with dark magic."),
        Ingredient(id: "crystal-dust", name: "Crystal Dust", icon: "💎", cost: 10, desc: "Ground from dungeon crystals. Magical conductor."),
        Ingredient(id: "ember-shard", name: "Ember Shard", icon: "🔥", cost: 12, desc: "Drops from fire enemies. Still warm to the touch."),
        Ingredient(id: "frost-crystal", name: "Frost Crystal", icon: "❄️", cost: 12, desc: "Drops from ice enemies. Never melts."),
        Ingredient(id: "shadow-essence", name: "Shadow Essence", icon: "🌑", cost: 15, desc: "Extracted from shadow creatures. Absorbs light."),
        Ingredient(id: "venom-gland", name: "Venom Gland", icon: "🐍", cost: 10, desc: "Removed from serpent enemies. Handle with care."),
        Ingredient(id: "storm-spark", name: "Storm Spark", icon: "⚡", cost: 18, desc: "Rare lightning fragment. Crackles with energy."),
        Ingredient(id: "moon-petal", name: "Moon Petal", icon: "🌸", cost: 16, desc: "Blooms only in the deepest floors. Calming properties."),
        Ingredient(id: "iron-dust", name: "Iron Dust", icon: "⚙️", cost: 6, desc: "Ground iron from forge scraps. Fortifying."),
        Ingredient(id: "corrupted-core", name: "Corrupted Core", icon: "💜", cost: 20, desc: "From corrupted enemies. Unstable but powerful."),
        Ingredient(id: "golden-honey", name: "Golden Honey", icon: "🍯", cost: 14, desc: "From the dungeon hives. Sweet and restorative."),
    ]

    public static func ingredient(_ id: String) -> Ingredient? { ingredients.first { $0.id == id } }

    static func potion(_ name: String, _ icon: String, heal: Int, _ desc: String, _ extra: [String: JSONValue] = [:]) -> Item {
        var i = Item(name: name, icon: icon, type: "potion", desc: desc, heal: heal)
        i.extra = extra
        return i
    }

    static func tactical(_ name: String, _ icon: String, _ type: String, _ desc: String, _ extra: [String: JSONValue] = [:]) -> Item {
        var i = Item(name: name, icon: icon, type: type, desc: desc)
        i.extra = extra
        return i
    }

    private static func n(_ v: Double) -> JSONValue { .number(v) }
    private static func s(_ v: String) -> JSONValue { .string(v) }

    /// ALCHEMY_RECIPES
    public static let recipes: [Recipe] = [
        Recipe(id: "basic-health", name: "Health Potion", icon: "🧪", ingredients: [("bone-powder", 1), ("golden-honey", 1)],
               desc: "Restores 40 HP.") { a in
            potion("Health Potion", "🧪", heal: a ? 60 : 40, "Restores \(a ? 60 : 40) HP.") },
        Recipe(id: "greater-health", name: "Greater Potion", icon: "💊", ingredients: [("glowing-shroom", 1), ("bone-powder", 1), ("golden-honey", 1)],
               desc: "Restores 80 HP. Alchemists: 120 HP.") { a in
            potion("Greater Potion", "💊", heal: a ? 120 : 80, "Restores \(a ? 120 : 80) HP.") },
        Recipe(id: "spirit-tonic", name: "Spirit Tonic", icon: "🔵", ingredients: [("crystal-dust", 1), ("void-herb", 1)],
               desc: "Restores 20 SP. Alchemists: 35 SP.") { a in
            var i = Item(name: "Spirit Tonic", icon: "🔵", type: "sp-potion", desc: "Restores \(a ? 35 : 20) SP.")
            i.sp = a ? 35 : 20
            return i },
        Recipe(id: "bloodfire", name: "Bloodfire Potion", icon: "🔥", ingredients: [("blood-vial", 1), ("ember-shard", 1)],
               desc: "Restores 50 HP. Burns the next enemy for 8 damage per turn for 3 turns.") { a in
            potion("Bloodfire Potion", "🔥", heal: a ? 70 : 50, "Heals and burns next enemy.", ["applyEffect": s("burn-next")]) },
        Recipe(id: "glacier-tonic", name: "Glacier Tonic", icon: "❄️", ingredients: [("frost-crystal", 1), ("crystal-dust", 1)],
               desc: "Restores 50 HP. Stuns the next enemy for 1 turn.") { a in
            potion("Glacier Tonic", "❄️", heal: a ? 65 : 50, "Heals and stuns next enemy.", ["applyEffect": s("stun-next")]) },
        Recipe(id: "void-draught", name: "Void Draught", icon: "🌑", ingredients: [("void-herb", 1), ("shadow-essence", 1)],
               desc: "Restores 40 HP. Grants +10 ATK for 4 turns.") { a in
            potion("Void Draught", "🌑", heal: a ? 55 : 40, "Heals and boosts ATK.",
                   ["applyEffect": s("atk-boost"), "atkBoost": n(a ? 15 : 10), "boostTurns": n(4)]) },
        Recipe(id: "antidote", name: "Antidote", icon: "💚", ingredients: [("venom-gland", 1), ("moon-petal", 1)],
               desc: "Cures poison and restores 30 HP.") { a in
            potion("Antidote", "💚", heal: a ? 50 : 30, "Cures poison and heals.", ["applyEffect": s("cure-poison")]) },
        Recipe(id: "berserker-brew", name: "Berserker Brew", icon: "💢", ingredients: [("blood-vial", 1), ("storm-spark", 1)],
               desc: "No HP restore. +25 ATK for 5 turns. Pure rage in a bottle.") { a in
            potion("Berserker Brew", "💢", heal: 0, "Massive ATK boost. No healing.",
                   ["applyEffect": s("atk-boost"), "atkBoost": n(a ? 35 : 25), "boostTurns": n(5)]) },
        Recipe(id: "ironflesh", name: "Ironflesh Tonic", icon: "⚙️", ingredients: [("iron-dust", 2), ("crystal-dust", 1)],
               desc: "Restores 30 HP. +10 DEF for 4 turns.") { a in
            potion("Ironflesh Tonic", "⚙️", heal: a ? 45 : 30, "Heals and boosts DEF.",
                   ["applyEffect": s("def-boost"), "defBoost": n(a ? 15 : 10), "boostTurns": n(4)]) },
        Recipe(id: "shadow-cloak", name: "Shadow Cloak", icon: "🌒", ingredients: [("shadow-essence", 2), ("void-herb", 1)],
               desc: "No heal. 40% chance to dodge the next 3 attacks.") { a in
            potion("Shadow Cloak", "🌒", heal: 0, "Grants dodge chance for several turns.",
                   ["applyEffect": s("dodge-buff"), "dodgeChance": n(a ? 0.55 : 0.40), "dodgeTurns": n(a ? 4 : 3)]) },
        Recipe(id: "storm-draught", name: "Storm Draught", icon: "⚡", ingredients: [("storm-spark", 1), ("crystal-dust", 1)],
               desc: "Restores 35 HP. Next attack crits guaranteed.") { a in
            potion("Storm Draught", "⚡", heal: a ? 50 : 35, "Heals and guarantees next crit.", ["applyEffect": s("next-crit")]) },
        Recipe(id: "corrupted-brew", name: "Corrupted Brew", icon: "💜", ingredients: [("corrupted-core", 1), ("blood-vial", 1)],
               desc: "Deals 40 damage to enemy. Heals you for same amount. Dangerous.") { a in
            potion("Corrupted Brew", "💜", heal: 0, "Steals life from enemy.", ["applyEffect": s("life-steal"), "stealAmt": n(a ? 60 : 40)]) },
        Recipe(id: "mirror-flask-r", name: "Mirror Flask", icon: "🪞", ingredients: [("crystal-dust", 1), ("shadow-essence", 1)],
               desc: "Reflects next enemy attack back at them.") { _ in
            tactical("Mirror Flask", "🪞", "mirror-flask", "Reflects next enemy attack.") },
        Recipe(id: "phantom-potion-r", name: "Phantom Potion", icon: "👻", ingredients: [("void-herb", 1), ("moon-petal", 1)],
               desc: "Untargetable for 2 turns. Alchemists: 3 turns.") { a in
            tactical("Phantom Potion", "👻", "phantom-potion", "Untargetable for \(a ? 3 : 2) turns.", ["phantomTurns": n(a ? 3 : 2)]) },
        Recipe(id: "gravity-tonic-r", name: "Gravity Tonic", icon: "🌀", ingredients: [("crystal-dust", 2), ("iron-dust", 1)],
               desc: "Enemy ATK drops to 1 for 3 turns.") { a in
            tactical("Gravity Tonic", "🌀", "gravity-tonic", "Crushes enemy ATK for \(a ? 4 : 3) turns.", ["gravityTurns": n(a ? 4 : 3)]) },
        Recipe(id: "leech-brew-r", name: "Leech Brew", icon: "🩸", ingredients: [("blood-vial", 1), ("void-herb", 1)],
               desc: "30% life steal per hit for 4 turns.") { a in
            tactical("Leech Brew", "🩸", "leech-brew", "Life steal per hit for \(a ? 5 : 4) turns.",
                     ["leechPct": n(a ? 0.45 : 0.30), "leechTurns": n(a ? 5 : 4)]) },
        Recipe(id: "rage-tonic-r", name: "Rage Tonic", icon: "💢", ingredients: [("ember-shard", 1), ("storm-spark", 1)],
               desc: "Triple ATK, double damage taken for 3 turns.") { a in
            tactical("Rage Tonic", "💢", "rage-tonic", "Triple ATK for \(a ? 4 : 3) turns.", ["rageTurns": n(a ? 4 : 3)]) },
        Recipe(id: "fog-flask-r", name: "Fog Flask", icon: "🌫️", ingredients: [("shadow-essence", 1), ("glowing-shroom", 1)],
               desc: "Enemy 70% miss chance for 3 turns.") { a in
            tactical("Fog Flask", "🌫️", "fog-flask", "Enemy misses 70% for \(a ? 4 : 3) turns.", ["fogTurns": n(a ? 4 : 3)]) },
        Recipe(id: "time-potion-r", name: "Time Potion", icon: "⌛", ingredients: [("crystal-dust", 2), ("moon-petal", 1)],
               desc: "2 free attacks this turn. Alchemists: 3.") { a in
            tactical("Time Potion", "⌛", "time-potion", "\(a ? 3 : 2) free attacks this turn.", ["freeAttacks": n(a ? 3 : 2)]) },
        Recipe(id: "corruption-flask-r", name: "Corruption Flask", icon: "💜", ingredients: [("corrupted-core", 1), ("void-herb", 1)],
               desc: "20 corruption damage to enemy per turn for 4 turns.") { a in
            tactical("Corruption Flask", "💜", "corruption-flask", "Corruption damage per turn.",
                     ["corrDmg": n(a ? 30 : 20), "corrTurns": n(a ? 5 : 4)]) },
        Recipe(id: "elixir-of-life", name: "Elixir of Life", icon: "✨", ingredients: [("glowing-shroom", 2), ("moon-petal", 2), ("golden-honey", 2)],
               desc: "ALCHEMIST ONLY. Fully restores HP and SP.", alchemistOnly: true) { _ in
            potion("Elixir of Life", "✨", heal: 9999, "Fully restores HP and SP.", ["restoreSP": .bool(true)]) },
        Recipe(id: "philosophers", name: "Philosopher's Brew", icon: "⭐",
               ingredients: [("corrupted-core", 1), ("storm-spark", 1), ("shadow-essence", 1), ("crystal-dust", 1)],
               desc: "ALCHEMIST ONLY. +5 permanent ATK, DEF, and SP for this run.", alchemistOnly: true) { _ in
            potion("Philosopher's Brew", "⭐", heal: 0, "Permanent stat boost this run.", ["applyEffect": s("perm-buff")]) },
    ]

    /// What a non-Alchemist sometimes gets instead.
    static let mishaps: [Item] = [
        potion("Unstable Brew", "🧪", heal: 25, "Something went wrong. Heals 25 HP."),
        potion("Mystery Tonic", "❓", heal: 50, "Tastes odd. Heals 50 HP."),
        potion("Lucky Accident", "🍀", heal: 0, "Somehow gives next crit.", ["applyEffect": s("next-crit")]),
    ]

    public static func recipes(alchemist: Bool) -> [Recipe] { recipes.filter { alchemist || !$0.alchemistOnly } }

    // MARK: Ingredients (dd_alchemy_ingredients)

    public static func stock(_ store: GameStore) -> [String: Int] {
        guard let s = store.getItem("dd_alchemy_ingredients"), let d = s.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: Double].self, from: d) else { return [:] }
        return raw.mapValues { Int($0) }.filter { $0.value > 0 }
    }

    static func save(_ stock: [String: Int], _ store: GameStore) {
        if let d = try? JSONEncoder().encode(stock.filter { $0.value > 0 }), let s = String(data: d, encoding: .utf8) {
            store.setItem("dd_alchemy_ingredients", s)
        }
    }

    public static func add(_ id: String, _ count: Int = 1, store: GameStore) {
        var s = stock(store)
        s[id, default: 0] += count
        save(s, store)
    }

    /// buyAlchemyIngredient
    public static func buy(_ id: String, store: GameStore, wallet: Wallet) -> String {
        guard let i = ingredient(id) else { return "" }
        guard wallet.spendGold(i.cost) else { return "Not enough gold. Need \(i.cost)g." }
        add(id, store: store)
        return "Bought \(i.name)."
    }

    public static func canCraft(_ r: Recipe, _ stock: [String: Int]) -> Bool {
        r.ingredients.allSatisfy { (stock[$0.id] ?? 0) >= $0.count }
    }

    public static func needs(_ r: Recipe, _ stock: [String: Int]) -> String {
        r.ingredients.map { x in
            let i = ingredient(x.id)
            return "\(i?.name ?? x.id) ×\(x.count) (have \(stock[x.id] ?? 0))"
        }.joined(separator: ", ")
    }

    public struct Brewed: Sendable {
        public let potion: Item
        /// The brew went wrong (non-Alchemists, 20%).
        public let mishap: Bool
    }

    /// craftAlchemyPotion: spends the ingredients and brews.
    public static func craft(_ id: String, alchemist: Bool, store: GameStore, dice: inout some Dice) -> Brewed? {
        guard let r = recipes.first(where: { $0.id == id }), alchemist || !r.alchemistOnly else { return nil }
        var s = stock(store)
        guard canCraft(r, s) else { return nil }
        for x in r.ingredients { s[x.id, default: 0] -= x.count }
        save(s, store)
        if !alchemist && dice.chance(0.20) {
            return Brewed(potion: mishaps[dice.roll(0...(mishaps.count - 1))], mishap: true)
        }
        return Brewed(potion: r.craft(alchemist), mishap: false)
    }

    // MARK: Potions brewed outside a run (dd_alchemy_stored)

    public static func stored(_ store: GameStore) -> [Item] {
        guard let s = store.getItem("dd_alchemy_stored"), let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: d)) ?? []
    }

    public static func store(_ item: Item, in store: GameStore) {
        var all = stored(store)
        all.append(item)
        if let d = try? JSONEncoder().encode(all), let s = String(data: d, encoding: .utf8) { store.setItem("dd_alchemy_stored", s) }
    }

    /// A new run picks up what was brewed at home. Returns how many.
    public static func collect(into run: inout Run, store: GameStore) -> Int {
        let all = stored(store)
        guard !all.isEmpty else { return 0 }
        run.inventory += all
        store.removeItem("dd_alchemy_stored")
        return all.count
    }

    // MARK: Drops (alchemyDropOnKill)

    /// 10% on a kill: an ingredient that suits the enemy, or a common one.
    public static func drop(_ e: Enemy, store: GameStore, dice: inout some Dice) -> Ingredient? {
        guard dice.chance(0.10) else { return nil }
        let n = e.name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        var pool: [String] = []
        if has("skeleton", "bone", "undead") { pool.append("bone-powder") }
        if has("void") { pool.append("void-herb") }
        if has("shadow", "shade") { pool.append("shadow-essence") }
        if has("fire", "flame", "ember") { pool.append("ember-shard") }
        if has("frost", "ice", "frozen") { pool.append("frost-crystal") }
        if has("serpent", "snake", "cobra", "venom") { pool.append("venom-gland") }
        if has("corrupt") { pool.append("corrupted-core") }
        pool += ["bone-powder", "glowing-shroom", "golden-honey"]
        let id = pool[dice.roll(0...(pool.count - 1))]
        add(id, store: store)
        return ingredient(id)
    }

    // MARK: Drinking

    static func num(_ i: Item, _ k: String) -> Double? {
        if case .number(let v)? = i.extra[k] { return v }
        return nil
    }

    static func effect(_ i: Item) -> String? {
        if case .string(let v)? = i.extra["applyEffect"] { return v }
        return nil
    }

    /// Whether a healing potion is still worth drinking at full health.
    static func hasEffect(_ i: Item) -> Bool { effect(i) != nil || (i.heal ?? 0) >= 9999 }

    /// applyPotionEffect: what an alchemy potion does beyond healing.
    static func applyEffect(_ i: Item, _ run: inout Run) -> String? {
        if (i.heal ?? 0) >= 9999 {
            run.hp = run.maxHp
            if i.extra["restoreSP"] == .bool(true) { run.sp = run.maxSp }
            return "✨ \(i.name)! HP and SP fully restored."
        }
        switch effect(i) {
        case "burn-next":
            run.brews.burnNext = true
            return "🔥 Bloodfire active — the next enemy will burn for 3 turns!"
        case "stun-next":
            run.brews.stunNext = true
            return "❄️ Glacier Tonic active — the next enemy will be stunned for a turn!"
        case "atk-boost":
            let b = Int(num(i, "atkBoost") ?? 10), t = Int(num(i, "boostTurns") ?? 4)
            run.tempAtk += b
            run.tempAtkTurns = max(run.tempAtkTurns, t)
            return "💢 ATK +\(b) for \(t) turns!"
        case "def-boost":
            let b = Int(num(i, "defBoost") ?? 10), t = Int(num(i, "boostTurns") ?? 4)
            run.tempDef += b
            run.tempDefTurns = max(run.tempDefTurns, t)
            return "⚙️ DEF +\(b) for \(t) turns!"
        case "cure-poison":
            run.poisonTurns = 0
            return "💚 Poison cured!"
        case "next-crit":
            run.markedKill = true
            return "⚡ Your next attack is a guaranteed critical hit!"
        case "dodge-buff":
            run.brews.dodge = num(i, "dodgeChance") ?? 0.40
            run.brews.dodgeTurns = Int(num(i, "dodgeTurns") ?? 3)
            return "🌒 Shadow Cloak! \(jsRound(run.brews.dodge * 100))% dodge for \(run.brews.dodgeTurns) turns!"
        case "life-steal":
            guard var e = run.enemy, run.inCombat else { return nil }
            let steal = min(e.hp, Int(num(i, "stealAmt") ?? 40))
            e.hp -= steal
            run.enemy = e
            run.hp = min(run.maxHp, run.hp + steal)
            return "💜 Corrupted Brew! Stole \(steal) life from \(e.name)!"
        case "perm-buff":
            run.atkBonus += 5
            run.defBonus += 5
            run.maxSp += 5
            run.sp = min(run.maxSp, run.sp + 5)
            return "⭐ Philosopher's Brew! +5 ATK, +5 DEF and +5 max SP for the rest of this run!"
        default: return nil
        }
    }

    /// The tactical potions. Nil when the type isn't one of them; otherwise
    /// the outcome (with `used` false when it can't be used now).
    static func useTactical(_ i: Item, _ run: inout Run) -> Inventory.Outcome? {
        let combatOnly = Inventory.Outcome(message: "Use this in combat.", used: false)
        switch i.type {
        case "mirror-flask":
            guard run.inCombat else { return combatOnly }
            run.brews.mirror = true
            return .init(message: "🪞 Mirror Flask! The next hit the enemy deals will be reflected back at them.")
        case "phantom-potion":
            guard run.inCombat else { return combatOnly }
            let t = Int(num(i, "phantomTurns") ?? 2)
            run.brews.phantomTurns = t
            return .init(message: "👻 Phantom Potion! You become untargetable for \(t) turns. Enemy attacks pass through you.")
        case "gravity-tonic":
            guard run.inCombat, let e = run.enemy else { return .init(message: "No enemy to target.", used: false) }
            let t = Int(num(i, "gravityTurns") ?? 3)
            run.brews.gravityTurns = t
            return .init(message: "🌀 Gravity Tonic! \(e.name)'s attack drops to 1 for \(t) turns.")
        case "leech-brew":
            guard run.inCombat else { return combatOnly }
            run.brews.leech = num(i, "leechPct") ?? 0.30
            run.brews.leechTurns = Int(num(i, "leechTurns") ?? 4)
            return .init(message: "🩸 Leech Brew! Every hit heals you for \(jsRound(run.brews.leech * 100))% of the damage for \(run.brews.leechTurns) turns.")
        case "rage-tonic":
            guard run.inCombat else { return combatOnly }
            let t = Int(num(i, "rageTurns") ?? 3)
            run.brews.rageTurns = t
            return .init(message: "💢 Rage Tonic! Triple attack but double incoming damage for \(t) turns. Pure chaos.")
        case "fog-flask":
            guard run.inCombat, let e = run.enemy else { return .init(message: "No enemy to target.", used: false) }
            let t = Int(num(i, "fogTurns") ?? 3)
            run.brews.fogTurns = t
            return .init(message: "🌫️ Fog Flask! \(e.name) has a 70% chance to miss for \(t) turns.")
        case "time-potion":
            guard run.inCombat else { return combatOnly }
            let t = Int(num(i, "freeAttacks") ?? 2)
            run.brews.timeStop += t
            return .init(message: "⌛ Time Potion! Time slows. Your next \(t) attacks are free — the enemy cannot respond.")
        case "corruption-flask":
            guard run.inCombat, let e = run.enemy else { return .init(message: "No enemy to target.", used: false) }
            run.brews.corrDamage = Int(num(i, "corrDmg") ?? 20)
            run.brews.corrTurns = Int(num(i, "corrTurns") ?? 4)
            return .init(message: "💜 Corruption Flask! \(e.name) takes \(run.brews.corrDamage) corruption damage each turn for \(run.brews.corrTurns) turns.")
        default: return nil
        }
    }

    public static let tacticalTypes: Set<String> = [
        "mirror-flask", "phantom-potion", "gravity-tonic", "leech-brew", "rage-tonic", "fog-flask", "time-potion", "corruption-flask",
    ]

    // MARK: In combat

    /// A new fight: Bloodfire burns it, Glacier Tonic stuns it.
    static func combatStart(_ run: inout Run, log: inout [String]) {
        guard var e = run.enemy else { return }
        if run.brews.burnNext {
            run.brews.burnNext = false
            e.dotDamage = max(e.dotDamage, 8)
            e.dotTurns = max(e.dotTurns, 3)
            log.append("🔥 Bloodfire! \(e.name) burns for 8 damage a turn for 3 turns.")
        }
        if run.brews.stunNext {
            run.brews.stunNext = false
            e.stunTurns = max(e.stunTurns, 1)
            log.append("❄️ Glacier Tonic! \(e.name) is frozen solid for a turn.")
        }
        run.enemy = e
    }

    /// Rage Tonic triples your attack.
    static func rage(_ run: inout Run, _ atk: Int, log: inout [String]) -> Int {
        guard run.brews.rageTurns > 0 else { return atk }
        run.brews.rageTurns -= 1
        if run.brews.rageTurns == 0 { log.append("💢 Rage fades. ATK returns to normal.") }
        return atk * 3
    }

    /// Leech Brew, on a landed hit.
    static func leech(_ run: inout Run, _ dmg: Int, log: inout [String]) {
        guard run.brews.leechTurns > 0, dmg > 0 else { return }
        run.brews.leechTurns -= 1
        let h = jsRound(Double(dmg) * run.brews.leech)
        run.hp = min(run.maxHp, run.hp + h)
        log.append("🩸 Leech! +\(h) HP from life steal." + (run.brews.leechTurns == 0 ? " Leech fades." : " \(run.brews.leechTurns) turns left."))
    }

    /// Corruption Flask, once a turn on your target.
    static func corrupt(_ run: inout Run, log: inout [String]) {
        guard run.brews.corrTurns > 0, var e = run.enemy, !e.isDead else { return }
        run.brews.corrTurns -= 1
        e.hp = max(0, e.hp - run.brews.corrDamage)
        run.enemy = e
        log.append("💜 Corruption! \(e.name) takes \(run.brews.corrDamage) corruption damage."
                   + (run.brews.corrTurns == 0 ? " Corruption fades." : " \(run.brews.corrTurns) turns left."))
    }

    /// Time Potion: the enemies lose their turn.
    static func timeStopped(_ run: inout Run, log: inout [String]) -> Bool {
        guard run.brews.timeStop > 0 else { return false }
        run.brews.timeStop -= 1
        log.append("⌛ Time stands still. The enemy cannot respond." + (run.brews.timeStop > 0 ? " \(run.brews.timeStop) free attacks left." : ""))
        return true
    }

    /// Before an enemy's attack: Phantom, Shadow Cloak and Fog. True when it misses.
    static func avoids(_ run: inout Run, _ e: Enemy, dice: inout some Dice, log: inout [String]) -> Bool {
        if run.brews.phantomTurns > 0 {
            run.brews.phantomTurns -= 1
            log.append("👻 Phantom — the attack passes through you! " + (run.brews.phantomTurns > 0 ? "\(run.brews.phantomTurns) turns left." : "Phantom fades."))
            return true
        }
        if run.brews.dodgeTurns > 0 {
            run.brews.dodgeTurns -= 1
            let dodged = dice.chance(run.brews.dodge)
            if run.brews.dodgeTurns == 0 { run.brews.dodge = 0 }
            if dodged {
                log.append("🌒 Shadow Cloak — you slip away from \(e.name)'s attack!" + (run.brews.dodgeTurns == 0 ? " Shadow Cloak fades." : ""))
                return true
            }
            if run.brews.dodgeTurns == 0 { log.append("Shadow Cloak faded.") }
        }
        if run.brews.fogTurns > 0 {
            run.brews.fogTurns -= 1
            if dice.chance(0.70) {
                log.append("🌫️ \(e.name) swings wildly through the fog — missed!" + (run.brews.fogTurns == 0 ? " The fog clears." : ""))
                return true
            }
            if run.brews.fogTurns == 0 { log.append("🌫️ The fog clears.") }
        }
        return false
    }

    /// Gravity Tonic: the hit lands for 1.
    static func gravity(_ run: inout Run, log: inout [String]) -> Bool {
        guard run.brews.gravityTurns > 0 else { return false }
        run.brews.gravityTurns -= 1
        if run.brews.gravityTurns == 0 { log.append("🌀 Gravity fades. Enemy attack returns.") }
        return true
    }

    /// Rage doubles what you take; the Mirror Flask sends 80% of it back
    /// and you take none. Returns the damage you take.
    static func incoming(_ run: inout Run, _ taken: Int, log: inout [String]) -> Int {
        var t = taken
        if run.brews.rageTurns > 0 { t *= 2 }
        guard run.brews.mirror, var e = run.enemy, t > 0 else { return t }
        run.brews.mirror = false
        let back = jsRound(Double(t) * 0.8)
        e.hp = max(0, e.hp - back)
        run.enemy = e
        log.append("🪞 Mirror Flask reflects the hit! \(back) damage reflected back at \(e.name)!")
        return 0
    }
}

/// ELIXIR VENDOR (Home → Vendor): sells you one elixir a day from a
/// rotating list, and buys spare elixirs for 25 gold.
public enum ElixirVendor {
    public struct Elixir: Sendable {
        public let name, icon: String
        public let healPct: Double
        public let desc: String
        public var item: Item { Item(name: name, icon: icon, type: "elixir", desc: desc, healPct: healPct) }
    }

    /// VENDOR_ELIXIRS
    public static let elixirs: [Elixir] = [
        Elixir(name: "Volcanic Elixir", icon: "🌋", healPct: 0.65, desc: "Restores 65% of max HP. A rare find in the wastes."),
        Elixir(name: "Void Elixir", icon: "🌑", healPct: 0.65, desc: "Restores 65% of max HP. Brewed from the abyss itself."),
        Elixir(name: "Elixir of the Depths", icon: "💧", healPct: 0.60, desc: "Restores 60% of max HP. Drawn from an eternal spring below the Archives."),
        Elixir(name: "Hollow Elixir", icon: "🩶", healPct: 0.55, desc: "Restores 55% of max HP. Left behind by someone who no longer needs it."),
        Elixir(name: "Hellfire Elixir", icon: "🔱", healPct: 0.65, desc: "Restores 65% of max HP. Distilled from infernal flame — somehow healing."),
        Elixir(name: "Sylvan Elixir", icon: "🌿", healPct: 0.60, desc: "Restores 60% of max HP. Pressed from the oldest flowers in the forest."),
        Elixir(name: "Shadow Elixir", icon: "🌑", healPct: 0.65, desc: "Restores 65% of max HP. Brewed from the dark between worlds. Glows faintly wrong."),
        Elixir(name: "Gravebound Elixir", icon: "💀", healPct: 0.60, desc: "Restores 60% of max HP. Bottled in the Crypt of Malachar."),
        Elixir(name: "Frostbound Elixir", icon: "🧊", healPct: 0.65, desc: "Restores 65% of max HP. Brewed by the vendor from ice they swear came from the Frosthold Abyss. Vendor exclusive."),
        Elixir(name: "Tidal Elixir", icon: "🌊", healPct: 0.60, desc: "Restores 60% of max HP. Drawn from the Abyssal Deep."),
    ]
    public static let sellPrice = 25
    public static let buyPrice = 55

    static func todayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 2026)-\(c.month ?? 1)-\(c.day ?? 1)"
    }

    /// getVendorDailyElixir: by day of the year.
    public static func daily(_ date: Date = Date()) -> Elixir {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return elixirs[day % elixirs.count]
    }

    public static func boughtToday(_ store: GameStore, _ date: Date = Date()) -> Bool {
        store.getItem("dd_elixir_vendor_last_buy") == todayKey(date)
    }

    /// buyVendorDailyElixir: what to say.
    public static func buy(_ run: inout Run, store: GameStore, wallet: Wallet, date: Date = Date()) -> String {
        if boughtToday(store, date) { return "Already bought the elixir vendor's special today. Come back tomorrow." }
        guard wallet.spendGold(buyPrice) else { return "Not enough gold. Need \(buyPrice)g." }
        store.setItem("dd_elixir_vendor_last_buy", todayKey(date))
        let e = daily(date)
        run.inventory.append(e.item)
        return "Bought \(e.name) from the vendor."
    }

    /// Spare elixirs in the run's pack, by name.
    public static func spares(_ run: Run) -> [(name: String, icon: String, count: Int)] {
        var order: [String] = []
        var counts: [String: (String, Int)] = [:]
        for i in run.inventory where i.type == "elixir" {
            if counts[i.name] == nil { order.append(i.name); counts[i.name] = (i.icon, 0) }
            counts[i.name]!.1 += 1
        }
        return order.map { (name: $0, icon: counts[$0]!.0, count: counts[$0]!.1) }
    }

    /// sellVendorElixir
    public static func sell(_ name: String, _ run: inout Run, wallet: Wallet) -> String? {
        guard let i = run.inventory.firstIndex(where: { $0.type == "elixir" && $0.name == name }) else { return nil }
        run.inventory.remove(at: i)
        wallet.addGold(sellPrice)
        return "Sold \(name) for \(sellPrice) gold."
    }
}
