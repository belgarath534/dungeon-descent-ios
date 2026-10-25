import Foundation

/// The state of one dungeon run (the web version's `DS` object).
/// Only the fields the ported systems use are here so far; more get added as
/// each system moves over.
public struct Run: Sendable {
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

    public var isDead: Bool { hp <= 0 }

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
