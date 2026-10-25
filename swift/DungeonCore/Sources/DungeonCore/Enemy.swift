import Foundation

/// An enemy definition from the bestiary tables (the web version's ENEMIES.t1 etc).
public struct EnemyTemplate: Sendable {
    public let name: String
    public let icon: String
    public let hp: Int
    public let atk: ClosedRange<Int>
    public let gold: ClosedRange<Int>
    public var coward = false
    public var phaseMsg2: String? = nil
    public var phaseMsg3: String? = nil
}

/// An enemy in a fight, with its numbers already scaled for the floor.
public struct Enemy: Equatable, Sendable {
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
    public var isDead: Bool { hp <= 0 }
}

public struct DungeonEnemies: Sendable {
    public let t1: [EnemyTemplate]
    public let t2: [EnemyTemplate]
    public let t3: [EnemyTemplate]
    public let bosses: [EnemyTemplate]

    /// Floors 1–3 use tier 1, 4–6 tier 2, 7+ tier 3.
    public func pool(forFloor floor: Int) -> [EnemyTemplate] {
        floor <= 3 ? t1 : floor <= 6 ? t2 : t3
    }
}

public enum Bestiary {
    /// Enemy tables per dungeon. Only the Crypt is ported so far; the others
    /// fall back to it until their tables are copied over.
    public static func enemies(for dungeon: String) -> DungeonEnemies {
        switch dungeon {
        default: return crypt
        }
    }

    private static func e(_ name: String, _ icon: String, _ hp: Int, _ atk: ClosedRange<Int>, _ gold: ClosedRange<Int>, coward: Bool = false) -> EnemyTemplate {
        EnemyTemplate(name: name, icon: icon, hp: hp, atk: atk, gold: gold, coward: coward)
    }

    private static func boss(_ name: String, _ icon: String, _ hp: Int, _ atk: ClosedRange<Int>, _ gold: ClosedRange<Int>, _ m2: String, _ m3: String) -> EnemyTemplate {
        EnemyTemplate(name: name, icon: icon, hp: hp, atk: atk, gold: gold, phaseMsg2: m2, phaseMsg3: m3)
    }

    public static let crypt = DungeonEnemies(
        t1: [
            e("Hollow Shade", "👻", 24, 4...9, 2...5),
            e("Crypt Rat", "🐀", 16, 3...7, 1...3, coward: true),
            e("Brittle Skeleton", "💀", 28, 5...10, 2...6),
            e("Grave Crawler", "🦂", 20, 4...8, 1...4),
            e("Tomb Bat", "🦇", 14, 3...6, 1...3),
            e("Rotting Ghoul", "🧟", 30, 5...9, 2...5),
            e("Ashen Wisp", "🌫️", 18, 4...8, 1...4),
            e("Bone Shard", "🦴", 22, 5...9, 2...4),
        ],
        t2: [
            e("Wailing Wraith", "👁️", 36, 7...13, 4...8),
            e("Armored Skeleton", "🗡️", 44, 8...14, 5...10),
            e("Plague Hound", "🐺", 30, 6...12, 3...7),
            e("Crypt Banshee", "👻", 40, 8...14, 5...9),
            e("Shadow Stalker", "🌑", 34, 7...13, 4...8),
            e("Cursed Knight", "🛡️", 50, 8...15, 6...11),
            e("Plague Wraith", "☠️", 38, 7...14, 5...9),
            e("Bone Archer", "🏹", 28, 9...16, 4...8),
            e("Crypt Spider", "🕷️", 32, 7...14, 4...8),
            e("Venom Spitter", "🕸️", 26, 8...15, 3...7),
        ],
        t3: [
            e("Death Knight", "⚔️", 60, 10...18, 8...15),
            e("Bone Colossus", "🦴", 72, 12...20, 10...18),
            e("Soul Harvester", "🌑", 55, 11...19, 7...14),
            e("Void Reaper", "💀", 65, 11...20, 9...16),
            e("Ancient Revenant", "🧟", 70, 12...19, 9...17),
            e("Nightmare Shade", "😱", 58, 11...21, 8...15),
            e("Blood Golem", "🔴", 80, 11...18, 10...17),
            e("Web Stalker", "🕷️", 66, 12...20, 8...15),
            e("Brood Mother", "🕸️", 74, 11...19, 9...16),
        ],
        bosses: [
            boss("Malachar the Undying", "👑", 120, 15...25, 30...50,
                 "Malachar screams — his shield cracks. Phase 2: He summons a wall of undead fire!",
                 "The fire wall falls. Malachar stands exposed — ancient and furious!"),
            boss("The Bone Sovereign", "💀", 110, 14...23, 28...48,
                 "The Bone Sovereign splinters — and rebuilds himself from the fallen dead around him!",
                 "His final form rises — a throne of bones animated by pure malice!"),
            boss("The Void Walker", "🌑", 115, 15...24, 29...49,
                 "The Void Walker tears a rift in reality itself. Phase 2: Reality warps around you!",
                 "The rift collapses inward. The Void Walker channels all of nothing at you!"),
            boss("The Crypt Tyrant", "👺", 125, 16...26, 31...51,
                 "The Crypt Tyrant bellows — the walls crack and dead rise from the rubble!",
                 "His power peaks. Ancient runes ignite across his armour. Final phase!"),
            boss("The Pale Queen", "👸", 108, 14...22, 27...47,
                 "The Pale Queen shrieks — her veil tears and reveals something ancient beneath!",
                 "She abandons grace entirely. Raw death magic pours from her hands!"),
        ]
    )

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
        return Enemy(name: t.name, icon: t.icon, hp: hp, maxHp: hp, atk: lo...max(lo, hi), gold: t.gold)
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
        return Enemy(name: t.name, icon: t.icon, hp: hp, maxHp: hp, atk: lo...max(lo, hi), gold: t.gold,
                     isBoss: true, phase1Hp: jsRound(Double(hp) * 0.66), phase2Hp: jsRound(Double(hp) * 0.33),
                     phaseMsg2: t.phaseMsg2, phaseMsg3: t.phaseMsg3)
    }
}
