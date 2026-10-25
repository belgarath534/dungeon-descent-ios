import Foundation

/// The state of one dungeon run (the web version's `DS` object).
/// Only the fields the ported systems use are here so far; more get added as
/// each system moves over.
public struct Run: Codable, Sendable {
    public var name: String
    public var cls: String
    public var race: String
    public var prof: String
    public var dungeon: String
    public var difficulty: GameData.Difficulty

    public var floor: Int
    public var roomsOnFloor = 0
    public var totalRooms = 0
    public var floorRoomsNeeded = 6

    public var maxHp: Int
    public var hp: Int
    public var maxLives: Int
    public var lives: Int
    public var atk: ClosedRange<Int>
    public var def: Int
    public var atkBonus = 0
    public var defBonus = 0
    public var critBonus = 0.0

    public var gold = 0
    public var xp = 0
    public var level = 1
    public var levelCap: Int
    public var levelPoints = 0
    public var sp = 20
    public var maxSp = 20
    public var kills = 0
    public var luckBonus = 0.0
    public var fleeBonus = 0.0

    public var potionMult: Double
    public var undeadRes: Bool
    public var pilgrimProf: Bool
    public var graveRobberLoot = false
    public var ngPlus = false
    public var ngPlusCount: Int? = nil

    public var inCombat = false
    public var defending = false
    public var markedKill = false
    public var enemy: Enemy? = nil
    public var bossPhase = 1

    // Items and gear
    public var inventory: [Item] = []
    public var equippedWeapon: Item? = nil
    public var equippedArmor: Item? = nil

    // Effects from potions, runes, scrolls and traps
    public var tempAtk = 0
    public var tempAtkTurns = 0
    public var tempDef = 0
    public var tempDefTurns = 0
    public var swiftTurns = 0
    public var runeSpeed = false
    public var runeFortune = false
    public var luckKills = 0
    public var poisonTurns = 0
    public var poisonDamage = 0
    public var frozen = false

    // Room state
    public var searched = false
    public var firstSearchDone = false
    /// Rooms already rolled by a Scroll of Reveal, used before rolling new ones.
    public var upcomingRooms: [Rooms.Outcome] = []

    public var isDead: Bool { hp <= 0 }

    /// Attack from the equipped weapon: the middle of its range, as initDungeon() adds it.
    public var weaponBonus: Int {
        guard let w = equippedWeapon else { return 0 }
        let r = w.weaponAttack
        return (r.lowerBound + r.upperBound) / 2
    }

    /// Defense from the equipped armor.
    public var armorDef: Int { equippedArmor?.armorDefense ?? 0 }

    /// Everything added on top of the class's attack roll.
    public var totalAtkBonus: Int {
        atkBonus + weaponBonus + tempAtk - (equippedArmor?.armorType == "heavy" ? 1 : 0)
    }

    /// Total defense, before the +4 for defending.
    public var totalDef: Int { def + defBonus + armorDef + tempDef }

    public var hasFleeRing: Bool { inventory.contains { $0.effect == "flee" } }

    /// Starts a run for a character, like initDungeon().
    public init(character ch: PlayerCharacter, gold: Int = 0) {
        let info = GameData.classInfo(ch.cls)
        name = ch.name
        cls = ch.cls
        race = ch.race
        prof = ch.prof
        dungeon = ch.dungeon
        difficulty = ch.difficultyLevel
        floor = max(ch.floor, 1)
        maxHp = info.maxHp
        hp = info.maxHp
        maxLives = difficulty.lives
        lives = difficulty.lives
        atk = info.atk
        def = info.def
        levelCap = ch.levelCap
        potionMult = ch.prof == "Herbalist" ? 2 : 1
        undeadRes = ch.prof == "Gravedigger"
        pilgrimProf = ch.prof == "Pilgrim"
        // Mercenary's starting blade. (The web version also sets 15 starting
        // gold, but then overwrites it with the wallet balance a few lines
        // later, so it never actually reaches the player.)
        if ch.prof == "Mercenary" { atkBonus += 3 }
        if ch.prof == "Warden" { defBonus += 3 }
        if ch.race == "Halfling" {
            luckBonus += 0.15
            atk = max(1, atk.lowerBound - 2)...max(2, atk.upperBound - 2)
        }
        self.gold = max(0, gold)
        ngPlus = ch.ngPlusActive
        if case .number(let n)? = ch.extra["ngPlusCount"] { ngPlusCount = Int(n) }
    }

    /// Run-start effects that touch the shared wallet. Call once when a run
    /// begins. Grave Robber gets 50 gold every run and +20% gold from kills.
    public mutating func applyStartBonuses(wallet: Wallet) {
        if prof == "Grave Robber" {
            gold += 50
            wallet.addGold(50)
            graveRobberLoot = true
        }
    }
}
