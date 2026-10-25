import Foundation

/// An item, in the same JSON shape the web version saves in inventories
/// ("dd_global_inv", "dd_equipped_weapon"). Unknown fields are kept in `extra`.
public struct Item: Equatable, Sendable {
    public var id: String?
    public var name: String
    public var icon: String
    /// Web type string: "potion", "elixir", "weapon", "rune", "fire-potion" …
    public var type: String
    public var desc: String
    public var heal: Int?
    public var healPct: Double?
    public var gold: Int?
    public var cost: Int?
    public var atkBonus: Int?
    public var defBonus: Int?
    public var atkBase: [Int]?
    public var defBase: Int?
    public var level: Int?
    public var weaponType: String?
    public var armorType: String?
    public var effect: String?
    public var isEquippable: Bool?
    public var atk: Int?
    public var def: Int?
    public var sp: Int?
    public var extra: [String: JSONValue] = [:]

    public init(id: String? = nil, name: String, icon: String, type: String, desc: String,
                heal: Int? = nil, healPct: Double? = nil, gold: Int? = nil, cost: Int? = nil,
                atkBonus: Int? = nil, defBonus: Int? = nil, atkBase: [Int]? = nil, defBase: Int? = nil,
                level: Int? = nil, weaponType: String? = nil, armorType: String? = nil,
                effect: String? = nil, isEquippable: Bool? = nil, atk: Int? = nil, def: Int? = nil, sp: Int? = nil) {
        self.id = id; self.name = name; self.icon = icon; self.type = type; self.desc = desc
        self.heal = heal; self.healPct = healPct; self.gold = gold; self.cost = cost
        self.atkBonus = atkBonus; self.defBonus = defBonus; self.atkBase = atkBase; self.defBase = defBase
        self.level = level; self.weaponType = weaponType; self.armorType = armorType
        self.effect = effect; self.isEquippable = isEquippable; self.atk = atk; self.def = def; self.sp = sp
    }

    public var isWeapon: Bool { type == "weapon" }
    public var isArmor: Bool { type == "armor" }

    /// Attack range a weapon gives (getWeaponAtk): +2.5 per level above 1.
    public var weaponAttack: ClosedRange<Int> {
        let base = atkBase ?? [5, 8]
        let bonus = jsRound(Double((level ?? 1) - 1) * 2.5)
        let lo = (base.first ?? 5) + bonus
        let hi = (base.count > 1 ? base[1] : lo) + bonus
        return lo...max(lo, hi)
    }

    /// Defense an armor gives (getArmorDef): +1.5 per level above 1.
    public var armorDefense: Int {
        (defBase ?? 4) + jsRound(Double((level ?? 1) - 1) * 1.5)
    }
}

extension Item: Codable {
    private static let knownKeys: Set<String> = [
        "id", "name", "icon", "type", "desc", "heal", "healPct", "gold", "cost", "atkBonus", "defBonus",
        "atkBase", "defBase", "level", "weaponType", "armorType", "effect", "isEquippable", "atk", "def", "sp",
    ]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func s(_ k: String) -> String? { try? c.decode(String.self, forKey: AnyKey(k)) }
        func i(_ k: String) -> Int? { (try? c.decode(Double.self, forKey: AnyKey(k))).map { Int($0) } }
        id = s("id")
        name = s("name") ?? "Unknown item"
        icon = s("icon") ?? "❔"
        type = s("type") ?? "misc"
        desc = s("desc") ?? ""
        heal = i("heal")
        healPct = try? c.decode(Double.self, forKey: AnyKey("healPct"))
        // Some web items store gold as [min, max]; keep those in `extra`.
        gold = i("gold")
        cost = i("cost")
        atkBonus = i("atkBonus")
        defBonus = i("defBonus")
        atkBase = (try? c.decode([Double].self, forKey: AnyKey("atkBase")))?.map { Int($0) }
        defBase = i("defBase")
        level = i("level")
        weaponType = s("weaponType")
        armorType = s("armorType")
        effect = s("effect")
        isEquippable = try? c.decode(Bool.self, forKey: AnyKey("isEquippable"))
        atk = i("atk")
        def = i("def")
        sp = i("sp")
        var rest: [String: JSONValue] = [:]
        for key in c.allKeys where !Self.knownKeys.contains(key.stringValue) {
            rest[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
        }
        if gold == nil, let g = try? c.decode(JSONValue.self, forKey: AnyKey("gold")) { rest["gold"] = g }
        extra = rest
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (k, v) in extra { try c.encode(v, forKey: AnyKey(k)) }
        try c.encodeIfPresent(id, forKey: AnyKey("id"))
        try c.encode(name, forKey: AnyKey("name"))
        try c.encode(icon, forKey: AnyKey("icon"))
        try c.encode(type, forKey: AnyKey("type"))
        try c.encode(desc, forKey: AnyKey("desc"))
        try c.encodeIfPresent(heal, forKey: AnyKey("heal"))
        try c.encodeIfPresent(healPct, forKey: AnyKey("healPct"))
        try c.encodeIfPresent(gold, forKey: AnyKey("gold"))
        try c.encodeIfPresent(cost, forKey: AnyKey("cost"))
        try c.encodeIfPresent(atkBonus, forKey: AnyKey("atkBonus"))
        try c.encodeIfPresent(defBonus, forKey: AnyKey("defBonus"))
        try c.encodeIfPresent(atkBase, forKey: AnyKey("atkBase"))
        try c.encodeIfPresent(defBase, forKey: AnyKey("defBase"))
        try c.encodeIfPresent(level, forKey: AnyKey("level"))
        try c.encodeIfPresent(weaponType, forKey: AnyKey("weaponType"))
        try c.encodeIfPresent(armorType, forKey: AnyKey("armorType"))
        try c.encodeIfPresent(effect, forKey: AnyKey("effect"))
        try c.encodeIfPresent(isEquippable, forKey: AnyKey("isEquippable"))
        try c.encodeIfPresent(atk, forKey: AnyKey("atk"))
        try c.encodeIfPresent(def, forKey: AnyKey("def"))
        try c.encodeIfPresent(sp, forKey: AnyKey("sp"))
    }
}

public struct Trap: Decodable, Sendable {
    public let name: String
    public let damage: Int
    public let effect: String
    public let turns: Int
    public let msg: String
}

/// Item tables from gamedata.json (the web version's LOOT, SHOP_STOCK, TRAP_TYPES).
public enum ItemTables {
    /// Item types whose effects the Swift version handles. The shop only
    /// stocks these until the rest (soul trap, mirror flask, rage tonic …) are ported.
    static let supportedTypes: Set<String> = [
        "potion", "elixir", "heal", "atk-potion", "def-potion", "luck-potion", "fire-potion",
        "curse-potion", "swift-potion", "phoenix-feather", "weapon", "armor", "rune", "scroll", "ring", "gem", "sp-potion",
    ]
    static let supportedIds: [String: Set<String>] = [
        "rune": ["rune-strength", "rune-protection", "rune-speed", "rune-fortune", "rune-vitality"],
        "scroll": ["scroll-smite", "scroll-mending", "scroll-reveal"],
    ]

    static func supported(_ i: Item) -> Bool {
        guard supportedTypes.contains(i.type) else { return false }
        if let ids = supportedIds[i.type] { return i.id.map(ids.contains) ?? false }
        return true
    }

    public static func loot(for dungeon: String) -> [Item] {
        GameContent.shared.dungeon(dungeon).loot.filter(supported)
    }

    public static func shop(for dungeon: String) -> [Item] {
        GameContent.shared.dungeon(dungeon).shop.filter { supported($0) && $0.type != "gem" && ($0.cost ?? 0) > 0 }
    }

    public static func traps(for dungeon: String, difficulty: GameData.Difficulty = .wanderer) -> [Trap] {
        let t = GameContent.shared.traps
        if difficulty == .nightmare, let n = t["nightmare"] { return n }
        switch dungeon {
        case "The Ashbound Wastes": return t["ashbound"] ?? t["crypt"] ?? []
        case "Frosthold Abyss": return t["frosthold"] ?? t["crypt"] ?? []
        default: return t["crypt"] ?? []
        }
    }

    public static var cryptLoot: [Item] { loot(for: GameData.dungeons[0]) }
    public static var cryptShop: [Item] { shop(for: GameData.dungeons[0]) }
}
