import Foundation

/// An enemy definition from the bestiary tables (the web version's ENEMIES.t1 etc),
/// loaded from gamedata.json.
public struct EnemyTemplate: Sendable {
    public let name: String
    public let icon: String
    public let hp: Int
    public let atk: ClosedRange<Int>
    public let gold: ClosedRange<Int>
    public var desc: String? = nil
    public var coward = false
    public var phaseMsg2: String? = nil
    public var phaseMsg3: String? = nil
    /// The enemy's special-ability fields (burn, dodgeEvery, lifesteal …),
    /// kept from the web data until each one is ported.
    public var mechanics: [String: JSONValue] = [:]
}

extension EnemyTemplate: Decodable {
    private static let baseKeys: Set<String> = ["name", "icon", "hp", "atk", "gold", "desc", "coward", "phaseMsg2", "phaseMsg3", "isBoss"]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = try c.decode(String.self, forKey: AnyKey("name"))
        icon = (try? c.decode(String.self, forKey: AnyKey("icon"))) ?? "👾"
        hp = Int(try c.decode(Double.self, forKey: AnyKey("hp")))
        let a = try c.decode([Double].self, forKey: AnyKey("atk")).map { Int($0) }
        atk = (a.first ?? 1)...max(a.first ?? 1, a.last ?? 1)
        if let g = try? c.decode([Double].self, forKey: AnyKey("gold")), let lo = g.first {
            gold = Int(lo)...max(Int(lo), Int(g.last ?? lo))
        } else {
            let n = Int((try? c.decode(Double.self, forKey: AnyKey("gold"))) ?? 0)
            gold = n...n
        }
        desc = try? c.decode(String.self, forKey: AnyKey("desc"))
        coward = (try? c.decode(Bool.self, forKey: AnyKey("coward"))) ?? false
        phaseMsg2 = try? c.decode(String.self, forKey: AnyKey("phaseMsg2"))
        phaseMsg3 = try? c.decode(String.self, forKey: AnyKey("phaseMsg3"))
        var m: [String: JSONValue] = [:]
        for k in c.allKeys where !Self.baseKeys.contains(k.stringValue) {
            m[k.stringValue] = try c.decode(JSONValue.self, forKey: k)
        }
        mechanics = m
    }
}

/// An enemy in a fight, with its numbers already scaled for the floor.
public struct Enemy: Codable, Equatable, Sendable {
    public var name: String
    public var icon: String
    public var hp: Int
    public var maxHp: Int
    public var atk: ClosedRange<Int>
    public var gold: ClosedRange<Int>
    public var isBoss = false
    public var phase1Hp = 0
    public var phase2Hp = 0
    public var phaseMsg2: String? = nil
    public var phaseMsg3: String? = nil
    /// Turns left of a Curse Potion halving its attack.
    public var cursedTurns = 0
    /// Turns the enemy loses (stuns, sleep, frozen).
    public var stunTurns = 0
    /// Damage over time on the enemy (poison, bleeding, burning).
    public var dotDamage = 0
    public var dotTurns = 0
    public var isElite = false
    /// Flavor text, or an elite's ability.
    public var desc: String? = nil
    /// Ability flags from the web data (burn, lifesteal, dodgeChance …).
    public var mechanics: [String: JSONValue] = [:]
    /// Fight bookkeeping for those abilities.
    public var turnsTaken = 0
    public var hitsTaken = 0
    public var vanished = false

    public func number(_ key: String) -> Double? {
        if case .number(let n)? = mechanics[key] { return n }
        return nil
    }

    public func flag(_ key: String) -> Bool {
        switch mechanics[key] {
        case .bool(true): return true
        case .number(let n): return n != 0
        default: return false
        }
    }
    public var isDead: Bool { hp <= 0 }

    /// Attack range this turn, halved while cursed.
    public var currentAtk: ClosedRange<Int> {
        guard cursedTurns > 0 else { return atk }
        let lo = jsRound(Double(atk.lowerBound) * 0.5), hi = jsRound(Double(atk.upperBound) * 0.5)
        return lo...max(lo, hi)
    }
}

public struct DungeonEnemies: Decodable, Sendable {
    public let t1: [EnemyTemplate]
    public let t2: [EnemyTemplate]
    public let t3: [EnemyTemplate]
    public let bosses: [EnemyTemplate]
    public let elites: [EnemyTemplate]

    /// Floors 1–3 use tier 1, 4–6 tier 2, 7+ tier 3.
    public func pool(forFloor floor: Int) -> [EnemyTemplate] {
        floor <= 3 ? t1 : floor <= 6 ? t2 : t3
    }
}

public enum Bestiary {
    /// Enemy tables for a dungeon. Nightmare difficulty uses its own enemies everywhere.
    public static func enemies(for dungeon: String, difficulty: GameData.Difficulty = .wanderer) -> DungeonEnemies {
        if difficulty == .nightmare, let n = GameContent.shared.nightmareEnemies { return n }
        return GameContent.shared.dungeon(dungeon).enemies
    }

    public static var crypt: DungeonEnemies { enemies(for: GameData.dungeons[0]) }

    /// Names the Gravedigger profession resists (doFight's undeadNames).
    public static let undeadNames: Set<String> = [
        "Hollow Shade", "Brittle Skeleton", "Wailing Wraith", "Armored Skeleton",
        "Bone Colossus", "Death Knight", "Soul Harvester", "Malachar the Undying",
    ]
}

extension Enemy {
    /// Scales a normal enemy for the run, matching enterRoom():
    /// +9% HP and +6% attack per floor, +8% both per player level,
    /// New Game+ and Endless bonuses on top.
    public static func spawn(_ t: EnemyTemplate, floor: Int, playerLevel: Int,
                             ngPlusCount: Int? = nil, endless: Bool = false) -> Enemy {
        var ng = ngPlusCount.map { 1.20 + Double($0 - 1) * 0.05 } ?? 1.0
        if endless && floor > 10 { ng *= 1 + Double((floor - 10) / 10) * 0.15 }
        let lvl = playerLevel > 1 ? 1 + Double(playerLevel - 1) * 0.08 : 1.0
        let f = Double(floor - 1)
        let hp = jsRound(Double(t.hp) * (1 + f * 0.09) * ng * lvl)
        let lo = jsRound(Double(t.atk.lowerBound) * (1 + f * 0.06) * ng * lvl)
        let hi = jsRound(Double(t.atk.upperBound) * (1 + f * 0.06) * ng * lvl)
        var e = Enemy(name: t.name, icon: t.icon, hp: hp, maxHp: hp, atk: lo...max(lo, hi), gold: t.gold)
        e.mechanics = t.mechanics
        if t.coward { e.mechanics["coward"] = .bool(true) }
        e.isElite = t.mechanics["isElite"] == .bool(true)
        if case .string(let a)? = t.mechanics["ability"] ?? t.mechanics["eliteAbility"] { e.desc = a } else { e.desc = t.desc }
        return e
    }

    /// Scales a boss, matching startCombat(): +15% HP and attack per player
    /// level, and always at least enough HP to take three max-damage hits.
    public static func spawnBoss(_ t: EnemyTemplate, playerLevel: Int, playerMaxAtk: Int,
                                 ngPlusCount: Int? = nil) -> Enemy {
        let lvl = 1 + Double(playerLevel - 1) * 0.15
        let ng = ngPlusCount.map { 1.20 + Double($0 - 1) * 0.08 } ?? 1.0
        var hp = jsRound(Double(t.hp) * lvl * ng)
        hp = max(hp, jsRound(Double(playerMaxAtk * 3) * lvl))
        let lo = jsRound(Double(t.atk.lowerBound) * lvl)
        let hi = jsRound(Double(t.atk.upperBound) * lvl)
        var e = Enemy(name: t.name, icon: t.icon, hp: hp, maxHp: hp, atk: lo...max(lo, hi), gold: t.gold,
                      isBoss: true, phase1Hp: jsRound(Double(hp) * 0.66), phase2Hp: jsRound(Double(hp) * 0.33),
                      phaseMsg2: t.phaseMsg2, phaseMsg3: t.phaseMsg3)
        // The Shadow World's boss chain.
        for k in ["isEcho", "isShapeshifter", "phaseMsg4", "fourPhase"] { e.mechanics[k] = t.mechanics[k] }
        return e
    }
}
