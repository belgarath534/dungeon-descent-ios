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
    public var sp = 20
    public var maxSp = 20
    public var kills = 0

    public var potionMult: Double
    public var undeadRes: Bool
    public var ngPlus = false
    public var ngPlusCount: Int? = nil

    public var inCombat = false
    public var defending = false
    public var markedKill = false
    public var enemy: Enemy? = nil

    public var isDead: Bool { hp <= 0 }

    /// Starts a run for a character, like initDungeon().
    public init(character ch: Character, gold: Int = 0) {
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
        potionMult = ch.prof == "Herbalist" ? 2 : 1
        undeadRes = ch.prof == "Gravedigger"
        // Mercenary's starting blade. (The web version also sets 15 starting
        // gold, but then overwrites it with the wallet balance a few lines
        // later, so it never actually reaches the player.)
        if ch.prof == "Mercenary" { atkBonus += 3 }
        self.gold = max(0, gold)
        ngPlus = ch.ngPlusActive
        if case .number(let n)? = ch.extra["ngPlusCount"] { ngPlusCount = Int(n) }
    }
}
