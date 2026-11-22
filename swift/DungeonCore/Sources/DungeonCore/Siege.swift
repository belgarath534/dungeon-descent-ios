import Foundation

/// THE SIEGE — fortress defense: ten waves, one enemy each, getting 20%
/// stronger every wave. Below 50 HP the enemy turns on your fortress; if its
/// durability hits zero you lose. The fortress (level, durability, Wave
/// Points, stationed minions, stocked potions) is kept in "dd_siege_data".
public enum Siege {
    public static let maxWaves = 10

    public enum Difficulty: String, CaseIterable, Sendable {
        case easy, normal, nightmare
        public var blurb: String {
            switch self {
            case .easy: return "Crypt and Ashbound enemies."
            case .normal: return "Ashbound to Hollow enemies."
            case .nightmare: return "Hollow to Abyssal Deep enemies."
            }
        }
    }

    struct Foe { let name: String; let hp: Int; let atk: ClosedRange<Int>; let def: Int; let gold: Int }

    static let pools: [Difficulty: [Foe]] = [
        .easy: [Foe(name: "Crypt Rat", hp: 40, atk: 4...8, def: 0, gold: 30), Foe(name: "Brittle Skeleton", hp: 55, atk: 6...10, def: 1, gold: 35),
                Foe(name: "Tomb Bat", hp: 35, atk: 5...9, def: 0, gold: 28), Foe(name: "Grave Crawler", hp: 60, atk: 7...11, def: 1, gold: 40),
                Foe(name: "Ashen Wisp", hp: 45, atk: 8...12, def: 0, gold: 38), Foe(name: "Cinder Wraith", hp: 65, atk: 9...14, def: 1, gold: 45),
                Foe(name: "Ash Crawler", hp: 70, atk: 8...13, def: 2, gold: 48), Foe(name: "Scorched Husk", hp: 80, atk: 10...15, def: 2, gold: 52),
                Foe(name: "Char Bat", hp: 55, atk: 9...13, def: 1, gold: 42), Foe(name: "Wailing Wraith", hp: 75, atk: 11...16, def: 1, gold: 55)],
        .normal: [Foe(name: "Scorched Husk", hp: 90, atk: 12...18, def: 3, gold: 65), Foe(name: "Flame Wraith", hp: 100, atk: 14...20, def: 3, gold: 70),
                  Foe(name: "Molten Knight", hp: 120, atk: 15...22, def: 4, gold: 80), Foe(name: "Hollow Bride", hp: 95, atk: 13...19, def: 3, gold: 68),
                  Foe(name: "The Portrait", hp: 85, atk: 14...20, def: 2, gold: 72), Foe(name: "Creaking Step", hp: 80, atk: 12...18, def: 3, gold: 65),
                  Foe(name: "The Reflection", hp: 110, atk: 15...21, def: 4, gold: 78), Foe(name: "The Twin", hp: 100, atk: 14...20, def: 3, gold: 75),
                  Foe(name: "Char Stalker", hp: 130, atk: 16...23, def: 5, gold: 85), Foe(name: "Blighted Overseer", hp: 140, atk: 17...25, def: 5, gold: 90)],
        .nightmare: [Foe(name: "The Door Warden", hp: 160, atk: 18...26, def: 6, gold: 110), Foe(name: "The Music Box", hp: 150, atk: 20...28, def: 5, gold: 105),
                     Foe(name: "Void Shadow", hp: 170, atk: 22...30, def: 6, gold: 120), Foe(name: "Infernal Ember", hp: 155, atk: 20...28, def: 7, gold: 115),
                     Foe(name: "Tide Wraith", hp: 175, atk: 21...30, def: 6, gold: 125), Foe(name: "Ink Fiend", hp: 165, atk: 22...32, def: 6, gold: 118),
                     Foe(name: "Deep Stalker", hp: 180, atk: 23...33, def: 7, gold: 130), Foe(name: "Pressure Beast", hp: 200, atk: 24...35, def: 8, gold: 140),
                     Foe(name: "Abyssal Eye", hp: 190, atk: 25...36, def: 7, gold: 145), Foe(name: "Void Sentinel", hp: 210, atk: 26...38, def: 8, gold: 155)],
    ]

    // MARK: The fortress

    public struct Fortress: Equatable, Sendable {
        public var level = 1
        public var durability = 50.0
        public var wavePoints = 0
        public var difficulty = Difficulty.easy
        public var extraPotions = 0
        public var stationed: [Minion] = []
        public var maxDurability: Int { 40 + level * 10 }
        public var minionAtk: Int { stationed.reduce(0) { $0 + max(1, $1.atk) } }
        public init() {}
    }

    public static func load(_ store: GameStore) -> Fortress {
        var f = Fortress()
        guard let s = store.getItem("dd_siege_data"), let d = s.data(using: .utf8),
              let v = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return f }
        f.level = (v["baseLevel"] as? NSNumber)?.intValue ?? 1
        f.durability = (v["baseDur"] as? NSNumber)?.doubleValue ?? 50
        f.wavePoints = (v["wavePoints"] as? NSNumber)?.intValue ?? 0
        f.difficulty = Difficulty(rawValue: v["difficulty"] as? String ?? "") ?? .easy
        f.extraPotions = (v["extraPotions"] as? NSNumber)?.intValue ?? 0
        if let a = v["stationedMinions"], let data = try? JSONSerialization.data(withJSONObject: a),
           let m = try? JSONDecoder().decode([Minion].self, from: data) { f.stationed = m }
        return f
    }

    public static func save(_ f: Fortress, store: GameStore) {
        var v: [String: Any] = [:]
        if let s = store.getItem("dd_siege_data"), let d = s.data(using: .utf8),
           let old = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { v = old }
        v["baseLevel"] = f.level
        v["baseDur"] = f.durability
        v["wavePoints"] = f.wavePoints
        v["difficulty"] = f.difficulty.rawValue
        v["extraPotions"] = f.extraPotions
        if let data = try? JSONEncoder().encode(f.stationed), let a = try? JSONSerialization.jsonObject(with: data) { v["stationedMinions"] = a }
        if let d = try? JSONSerialization.data(withJSONObject: v), let s = String(data: d, encoding: .utf8) { store.setItem("dd_siege_data", s) }
    }

    public struct Upgrade: Sendable { public let id, name, icon, desc: String; public let gold, wavePoints: Int }

    public static let upgrades: [Upgrade] = [
        Upgrade(id: "repair", name: "Repair Kit", icon: "🔧", desc: "Restore base durability to current level maximum.", gold: 600, wavePoints: 500),
        Upgrade(id: "reinforce", name: "Reinforce Base", icon: "🧱", desc: "Upgrade base to next level. +10% max durability per level.", gold: 800, wavePoints: 0),
        Upgrade(id: "station", name: "Station Minion", icon: "👾", desc: "Deploy one of your captured minions to defend the base.", gold: 300, wavePoints: 200),
        Upgrade(id: "stockpile", name: "Extra Potion", icon: "🧪", desc: "Stock one extra health potion for the battle ahead.", gold: 200, wavePoints: 0),
    ]

    /// The upgrades on offer now (no Reinforce at level 5, no Station without
    /// a minion left to send).
    public static func offered(_ f: Fortress, minions: [Minion]) -> [Upgrade] {
        upgrades.filter {
            if $0.id == "reinforce" { return f.level < 5 }
            if $0.id == "station" { return nextMinion(f, minions) != nil }
            return true
        }
    }

    /// The first captured minion not already stationed. (The web version
    /// stationed your first minion again every time.)
    static func nextMinion(_ f: Fortress, _ minions: [Minion]) -> Minion? {
        minions.first { m in !f.stationed.contains { $0.id == m.id } }
    }

    /// buySiegeUpgrade. Returns the message; the caller takes the gold.
    public static func buy(_ id: String, _ f: inout Fortress, gold: Int, minions: [Minion]) -> (ok: Bool, message: String) {
        guard let u = upgrades.first(where: { $0.id == id }) else { return (false, "") }
        guard gold >= u.gold else { return (false, "Not enough gold. Need \(u.gold) gold.") }
        guard f.wavePoints >= u.wavePoints else { return (false, "Not enough Wave Points. Need \(u.wavePoints).") }
        switch id {
        case "repair":
            f.durability = Double(f.maxDurability)
            f.wavePoints -= u.wavePoints
            return (true, "Base repaired. Durability restored to \(f.maxDurability) percent.")
        case "reinforce":
            guard f.level < 5 else { return (false, "Base is already at maximum level.") }
            f.level += 1
            f.durability = min(f.durability + 10, Double(f.maxDurability))
            return (true, "Base reinforced to level \(f.level). Maximum durability is now \(f.maxDurability) percent.")
        case "station":
            guard let m = nextMinion(f, minions) else { return (false, "No minions available to station.") }
            f.stationed.append(m)
            f.wavePoints -= u.wavePoints
            return (true, "\(m.name) stationed at your fortress. They will fight alongside you.")
        default:
            f.extraPotions += 1
            return (true, "Extra health potion added to your supplies.")
        }
    }

    // MARK: The battle

    public struct Enemy: Equatable, Sendable {
        public var name: String
        public var hp: Int
        public var maxHp: Int
        public var atk: ClosedRange<Int>
        public var def: Int
        public var gold: Int
    }

    public struct Battle: Equatable, Sendable {
        public var name: String
        public var wave = 1
        public var hp: Int
        public var maxHp: Int
        public var atk: ClosedRange<Int>
        public var def: Int
        public var potions: Int
        public var gold = 0
        public var enemy: Enemy
        public var fortress: Fortress
        public var damageThisWave = 0
        public var won = false
        public var lost: String? = nil   // "fallen" or "base"

        public var baseUnderAttack: Bool { hp <= 50 }
    }

    /// startSiege: your class's HP +50% and attack + 0.8 a level, defense
    /// from your saved bonus + 0.3 a level, 4 potions plus stocked ones.
    /// (The web version read stats characters don't have, so every hero
    /// fought as a 100 HP, 8–14 attack nobody.)
    public static func start(_ ch: PlayerCharacter, fortress: Fortress) -> Battle {
        let info = GameData.classInfo(ch.cls)
        let lvl = max(1, ch.persistLevel ?? 1)
        let hp = jsRound(Double(info.maxHp) * 1.5)
        let bonus = Int((Double(lvl) * 0.8).rounded(.down))
        var defBonus = 0
        if case .number(let n)? = ch.extra["defBonus"] { defBonus = Int(n) }
        return Battle(name: ch.name, hp: hp, maxHp: hp, atk: (info.atk.lowerBound + bonus)...(info.atk.upperBound + bonus),
                      def: defBonus + Int((Double(lvl) * 0.3).rounded(.down)), potions: 4 + fortress.extraPotions,
                      enemy: enemy(wave: 1, fortress.difficulty), fortress: fortress)
    }

    /// startSiegeWave: the pool's nth enemy, tougher each wave.
    public static func enemy(wave: Int, _ d: Difficulty) -> Enemy {
        let pool = pools[d] ?? pools[.easy]!
        let b = pool[min(wave - 1, pool.count - 1)]
        let m = pow(1.2, Double(wave - 1))
        // Attack grows 10% a wave, not 20% like everything else: at 20% the
        // tenth enemy hit five times harder than the first and no hero could
        // finish (see MIGRATION.md).
        let ma = pow(1.1, Double(wave - 1))
        func s(_ n: Int) -> Int { jsRound(Double(n) * m) }
        func sa(_ n: Int) -> Int { jsRound(Double(n) * ma) }
        return Enemy(name: b.name, hp: s(b.hp), maxHp: s(b.hp), atk: sa(b.atk.lowerBound)...sa(b.atk.upperBound), def: s(b.def), gold: s(b.gold))
    }

    public enum Action: Sendable { case attack, heavy, minion, gun(Int) }

    public struct Step: Equatable, Sendable {
        public var log: [String] = []
        public var acted = true
        public var enemyDied = false
        public var nextWave = false
    }

    /// siegeAttack / siegeCallMinion / siegeGunAction, then the enemy's turn.
    /// Calling the minion takes your turn. (In the web version it was free
    /// and could be pressed again and again.)
    public static func act(_ b: inout Battle, _ a: Action, dice: inout some Dice) -> Step {
        var s = Step()
        guard !b.won, b.lost == nil else { s.acted = false; return s }
        var dmg = 0
        switch a {
        case .attack, .heavy:
            let heavy: Bool = { if case .heavy = a { return true }; return false }()
            if heavy && dice.chance(0.30) {
                s.log.append("You swing and miss!")
            } else {
                var raw = dice.roll(b.atk)
                if heavy { raw = jsRound(Double(raw) * 1.6) }
                dmg = max(1, raw - b.enemy.def)
                let crit = dice.chance(0.10)
                if crit { dmg = jsRound(Double(dmg) * 1.8) }
                s.log.append((crit ? "CRITICAL! " : "") + "You deal \(dmg) damage to \(b.enemy.name).")
            }
        case .minion:
            guard !b.fortress.stationed.isEmpty else { s.acted = false; s.log = ["No minions stationed."]; return s }
            dmg = max(4, b.fortress.minionAtk + dice.roll(0...5))
            s.log.append("Your stationed minion attacks for \(dmg) damage!")
        case .gun(let d):
            dmg = d
            s.log.append("🔫 Your gun fires! \(dmg) damage on \(b.enemy.name)!")
        }
        b.enemy.hp = max(0, b.enemy.hp - dmg)
        b.damageThisWave += dmg
        if b.enemy.hp <= 0 {
            enemyDead(&b, &s)
            return s
        }
        s.log[s.log.count - 1] += " (\(b.enemy.hp) HP left)"
        enemyTurn(&b, &s, dice: &dice)
        return s
    }

    /// siegeUsePotion: half your HP back; it costs no turn.
    public static func potion(_ b: inout Battle) -> String {
        guard b.potions > 0 else { return "No potions left." }
        b.potions -= 1
        let heal = jsRound(Double(b.maxHp) * 0.5)
        b.hp = min(b.maxHp, b.hp + heal)
        return "Potion used. Restored \(heal) HP. Now at \(b.hp) HP. \(b.potions) potions left."
            + (b.hp > 50 ? " HP above 50 — the enemy targets you again." : "")
    }

    static func enemyTurn(_ b: inout Battle, _ s: inout Step, dice: inout some Dice) {
        let hit = max(1, dice.roll(b.enemy.atk) - b.def)
        if b.baseUnderAttack {
            let baseHit = jsRound(Double(hit) * 0.4)
            b.fortress.durability -= Double(baseHit)
            s.log.append("⚠️ YOUR BASE IS UNDER ATTACK! \(b.enemy.name) hits the fortress for \(baseHit) durability damage! Heal up fast!")
            if b.fortress.durability <= 0 {
                b.fortress.durability = 0
                b.lost = "base"
                s.log.append("Your fortress has been destroyed! The siege is lost.")
            }
            return
        }
        b.hp = max(0, b.hp - hit)
        s.log.append("\(b.enemy.name) attacks you for \(hit) damage. (\(b.hp) HP left)")
        if b.hp <= 0 {
            b.lost = "fallen"
            s.log.append("You have fallen. The siege is lost.")
        } else if b.hp <= 50 {
            s.log.append("⚠️ HP dropped below 50! The enemy will now target your base!")
        }
    }

    /// siegeEnemyDead: its gold, 500 Wave Points for every 50 damage you dealt
    /// it, then the next wave or victory.
    static func enemyDead(_ b: inout Battle, _ s: inout Step) {
        s.enemyDied = true
        b.gold += b.enemy.gold
        let wp = (b.damageThisWave / 50) * 500
        b.fortress.wavePoints += wp
        s.log.append("\(b.enemy.name) defeated! +\(b.enemy.gold) gold" + (wp > 0 ? ", +\(wp) Wave Points" : "") + ".")
        if b.wave >= maxWaves {
            b.won = true
            s.log.append("All 10 waves defeated! The Siege is won!")
            return
        }
        b.wave += 1
        // A breather between waves: 20% of your HP back. (The web version gave
        // nothing, and with enemies 20% stronger every wave no hero could
        // reach wave 10.)
        let rest = jsRound(Double(b.maxHp) * 0.2)
        b.hp = min(b.maxHp, b.hp + rest)
        s.log.append("You catch your breath between waves: +\(rest) HP. HP: \(b.hp).")
        b.enemy = enemy(wave: b.wave, b.fortress.difficulty)
        b.damageThisWave = 0
        s.nextWave = true
        s.log.append("--- Wave \(b.wave) incoming --- \(b.enemy.name) approaches! HP: \(b.enemy.hp).")
    }

    /// showSiegeResult: the fortress keeps at least 10% durability.
    public static func finish(_ b: Battle) -> Fortress {
        var f = b.fortress
        f.durability = max(f.durability, 10)
        return f
    }
}
