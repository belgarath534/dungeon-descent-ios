import XCTest
@testable import DungeonCore

// Expected numbers below were worked out by hand from the web version's
// formulas, so these tests catch any drift between the two versions.

final class JSCompatTests: XCTestCase {
    func testRoundMatchesJavaScript() {
        XCTAssertEqual(jsRound(2.5), 3)
        XCTAssertEqual(jsRound(-2.5), -2)
        XCTAssertEqual(jsRound(39.6), 40)
        XCTAssertEqual(jsRound(79.2), 79)
    }

    func testParseIntMatchesJavaScript() {
        XCTAssertEqual(jsParseInt("250"), 250)
        XCTAssertEqual(jsParseInt("12abc"), 12)
        XCTAssertEqual(jsParseInt("  -7"), -7)
        XCTAssertNil(jsParseInt("abc"))
        XCTAssertNil(jsParseInt(nil))
    }
}

final class WalletTests: XCTestCase {
    func testGoldAndAchievements() {
        let store = MemoryStore()
        var earned: [String] = []
        let w = Wallet(store: store) { earned.append($0) }
        w.addGold(350)
        XCTAssertEqual(w.gold, 350)
        XCTAssertEqual(store.getItem("dd_global_gold"), "350")
        XCTAssertEqual(earned, ["ach-gold-hoarder"])
        XCTAssertFalse(w.spendGold(400))
        XCTAssertTrue(w.spendGold(100))
        XCTAssertEqual(w.gold, 250)
        XCTAssertEqual(store.getItem("dd_total_gold_spent"), "100")
        XCTAssertEqual(store.getItem("dd_total_gold_ever"), "350")
    }

    func testReadsWebSaveValuesAndClampsBadOnes() {
        XCTAssertEqual(Wallet(store: MemoryStore(["dd_global_gold": "-40"])).gold, 0)
        XCTAssertEqual(Wallet(store: MemoryStore(["dd_global_gold": "oops"])).gold, 0)
        XCTAssertEqual(Wallet(store: MemoryStore(["dd_diamonds": "12"])).diamonds, 12)
    }

    func testDiamonds() {
        let w = Wallet(store: MemoryStore())
        w.addDiamonds(10)
        w.addDiamonds(-5)
        XCTAssertEqual(w.diamonds, 10)
        XCTAssertTrue(w.spendDiamonds(5))
        XCTAssertFalse(w.spendDiamonds(6))
        XCTAssertEqual(w.diamonds, 5)
    }
}

final class CharacterTests: XCTestCase {
    /// A character as the web version saves it, including fields Swift doesn't model yet.
    let webSave = """
    [{"name":"Lyra","cls":"Paladin","race":"Elf","prof":"Gravedigger","dungeon":"Crypt of Malachar",
      "difficulty":"Ironblood","floor":10,"created":1729870000000,"runMode":"classic",
      "lastSpirit":"ember-fox","corruptionMode":false,"corruption":0,"hunterMode":false,
      "hardcoreMode":false,"guidePersonality":"grim","guideEnabled":true,"earnedSpirits":["frost"],
      "levelCap":10,"completed":true,"backstory":{"id":"orphan","bonus":2},
      "deathLog":[{"floor":4,"killedBy":"Crypt Rat"}]}]
    """

    func testLoadsWebSaveAndKeepsUnknownFields() throws {
        let store = MemoryStore(["dd_chars": webSave])
        let roster = CharacterRoster(store: store)
        XCTAssertEqual(roster.characters.count, 1)
        let ch = roster.characters[0]
        XCTAssertEqual(ch.name, "Lyra")
        XCTAssertEqual(ch.difficultyLevel, .ironblood)
        XCTAssertEqual(ch.floor, 10)
        XCTAssertTrue(ch.completed)
        XCTAssertEqual(ch.extra["earnedSpirits"], .array([.string("frost")]))

        roster.save()
        let reloaded = CharacterRoster(store: store).characters[0]
        XCTAssertEqual(reloaded, ch)
        XCTAssertEqual(reloaded.extra["backstory"], .object(["id": .string("orphan"), "bonus": .number(2)]))
    }

    func testNewCharacterDefaults() {
        let classic = Character(name: "Kael", cls: "Warrior", race: "Human", prof: "Thief",
                                dungeon: "Crypt of Malachar", difficulty: .wanderer)
        XCTAssertEqual(classic.levelCap, 10)
        XCTAssertNil(classic.dungeonTier)
        let legacy = Character(name: "Kael", cls: "Warrior", race: "Human", prof: "Thief",
                               dungeon: "Crypt of Malachar", difficulty: .wanderer, runMode: "legacy")
        XCTAssertEqual(legacy.levelCap, 25)
        XCTAssertEqual(legacy.dungeonTier, 1)
    }

    func testNameRule() {
        XCTAssertFalse(Character.isValidName("A"))
        XCTAssertTrue(Character.isValidName("Al"))
        XCTAssertFalse(Character.isValidName(String(repeating: "x", count: 25)))
    }

    func testRosterLimitAndUnlocks() {
        let store = MemoryStore(["dd_chars": webSave])
        let roster = CharacterRoster(store: store)
        XCTAssertEqual(roster.unlockedDungeons(), ["Crypt of Malachar", "The Ashbound Wastes"])
        XCTAssertNotNil(store.getItem("dd_unlocks"))
        for i in 0..<4 {
            XCTAssertNotNil(roster.add(Character(name: "C\(i)", cls: "Monk", race: "Orc", prof: "Thief",
                                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)))
        }
        XCTAssertTrue(roster.isFull)
        XCTAssertNil(roster.add(Character(name: "Extra", cls: "Monk", race: "Orc", prof: "Thief",
                                          dungeon: "Crypt of Malachar", difficulty: .wanderer)))
    }

    func testDeathDeepInDungeonUnlocksNext() {
        let save = #"[{"name":"Z","cls":"Bard","dungeon":"Frosthold Abyss","floor":3,"deathLog":[{"floor":9}]}]"#
        let store = MemoryStore(["dd_chars": save, "dd_unlocks": #"{"The Ashbound Wastes":true,"Frosthold Abyss":true}"#])
        XCTAssertEqual(CharacterRoster(store: store).unlockedDungeons().last, "The Sunken Archives")
    }
}

final class RunTests: XCTestCase {
    func testStartingStats() {
        let ch = Character(name: "Brom", cls: "Sentinel", race: "Dwarf", prof: "Mercenary",
                           dungeon: "Crypt of Malachar", difficulty: .wanderer)
        let run = Run(character: ch, gold: 40)
        XCTAssertEqual(run.maxHp, 145)
        XCTAssertEqual(run.def, 7)
        XCTAssertEqual(run.atk, 5...11)
        XCTAssertEqual(run.lives, 3)
        XCTAssertEqual(run.atkBonus, 3)
        XCTAssertEqual(run.gold, 40)
        XCTAssertEqual(run.floor, 1)
    }

    func testClassWithoutOwnStatsUsesWebDefaults() {
        let ch = Character(name: "Vex", cls: "Arcanist", race: "Gnome", prof: "Herbalist",
                           dungeon: "Crypt of Malachar", difficulty: .forsaken)
        let run = Run(character: ch)
        XCTAssertEqual(run.maxHp, 100)
        XCTAssertEqual(run.atk, 6...12)
        XCTAssertEqual(run.lives, 1)
        XCTAssertEqual(run.potionMult, 2)
    }
}

final class EnemyScalingTests: XCTestCase {
    func testNormalEnemyScaling() {
        let golem = Bestiary.crypt.t3.first { $0.name == "Blood Golem" }!
        let e = Enemy.spawn(golem, floor: 7, playerLevel: 3)
        XCTAssertEqual(e.hp, 143)   // 80 × 1.54 × 1.16
        XCTAssertEqual(e.atk, 17...28)
    }

    func testBossScaling() {
        let malachar = Bestiary.crypt.bosses[0]
        let b1 = Enemy.spawnBoss(malachar, playerLevel: 1, playerMaxAtk: 16)
        XCTAssertEqual(b1.hp, 120)
        XCTAssertEqual(b1.phase1Hp, 79)
        XCTAssertEqual(b1.phase2Hp, 40)
        let b5 = Enemy.spawnBoss(malachar, playerLevel: 5, playerMaxAtk: 24)
        XCTAssertEqual(b5.hp, 192)
        XCTAssertEqual(b5.atk, 24...40)
    }

    func testTierByFloor() {
        XCTAssertEqual(Bestiary.crypt.pool(forFloor: 3).count, 8)
        XCTAssertEqual(Bestiary.crypt.pool(forFloor: 4).count, 10)
        XCTAssertEqual(Bestiary.crypt.pool(forFloor: 7).count, 9)
    }
}

final class CombatTests: XCTestCase {
    func makeRun(_ cls: String, _ diff: GameData.Difficulty = .wanderer, prof: String = "Thief") -> Run {
        Run(character: Character(name: "T", cls: cls, race: "Human", prof: prof,
                                 dungeon: "Crypt of Malachar", difficulty: diff))
    }

    var shade: Enemy { Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1) }

    func testAttackThenCounter() {
        var run = makeRun("Warrior")
        Combat.begin(&run, against: shade)
        var dice = LoadedDice(rolls: [10, 9], chances: [false])
        let r = Combat.takeTurn(&run, .attack, dice: &dice)
        XCTAssertEqual(r.playerDamage, 10)
        XCTAssertEqual(run.enemy?.hp, 14)
        // raw 9, block capped at floor(9 × 0.6) = 5, Warrior def 3 → blocks 3, takes 6
        XCTAssertEqual(r.enemyDamage, 6)
        XCTAssertEqual(run.hp, 114)
        XCTAssertEqual(r.log, ["You attack for 10 damage.",
                               "Hollow Shade strikes for 9 — you absorb 3. You take 6 damage."])
        XCTAssertEqual(r.announcement, "Hollow Shade dealt 6 damage. Your HP: 114 of 120.")
    }

    func testCrit() {
        var run = makeRun("Warrior")
        Combat.begin(&run, against: shade)
        var dice = LoadedDice(rolls: [10, 4], chances: [true])
        let r = Combat.takeTurn(&run, .attack, dice: &dice)
        XCTAssertTrue(r.crit)
        XCTAssertEqual(r.playerDamage, 18)
        XCTAssertEqual(r.log.first, "CRITICAL HIT! You strike for 18 damage!")
    }

    func testMarkedKillForcesCrit() {
        var run = makeRun("Assassin")
        run.markedKill = true
        Combat.begin(&run, against: shade)
        var dice = LoadedDice(rolls: [10, 4], chances: [false])
        let r = Combat.takeTurn(&run, .attack, dice: &dice)
        XCTAssertTrue(r.crit)
        XCTAssertFalse(run.markedKill)
    }

    func testHeavyMissAndHit() {
        var run = makeRun("Warrior")
        Combat.begin(&run, against: shade)
        var miss = LoadedDice(rolls: [10, 4], chances: [true])
        XCTAssertTrue(Combat.takeTurn(&run, .heavy, dice: &miss).missed)
        var hit = LoadedDice(rolls: [10, 4], chances: [false])
        XCTAssertEqual(Combat.takeTurn(&run, .heavy, dice: &hit).playerDamage, 17)
    }

    func testDefendWithSentinelTrait() {
        var run = makeRun("Sentinel")
        Combat.begin(&run, against: shade)
        var dice = LoadedDice(rolls: [9, 9])
        let r = Combat.takeTurn(&run, .defend, dice: &dice)
        XCTAssertEqual(r.playerDamage, 5)   // round(9 × 0.5)
        // raw 9, block capped at 5, then Sentinel takes 25% less: round(4 × 0.75) = 3
        XCTAssertEqual(r.enemyDamage, 3)
        XCTAssertEqual(run.hp, 142)
    }

    func testDifficultyAndUndeadResistance() {
        var nightmare = makeRun("Wizard", .nightmare)
        Combat.begin(&nightmare, against: shade)
        var d1 = LoadedDice(rolls: [14, 8])
        // raw round(8 × 1.75) = 14, Wizard has no defense
        XCTAssertEqual(Combat.takeTurn(&nightmare, .attack, dice: &d1).enemyDamage, 14)

        var digger = makeRun("Wizard", prof: "Gravedigger")
        Combat.begin(&digger, against: shade)
        var d2 = LoadedDice(rolls: [14, 9])
        // Hollow Shade is undead: round(9 × 0.65) = 6
        XCTAssertEqual(Combat.takeTurn(&digger, .attack, dice: &d2).enemyDamage, 6)
    }

    func testKillSkipsCounter() {
        var run = makeRun("Wizard")
        Combat.begin(&run, against: shade)
        var dice = LoadedDice(rolls: [24], chances: [true])
        let r = Combat.takeTurn(&run, .attack, dice: &dice)
        XCTAssertTrue(r.enemyDied)
        XCTAssertNil(r.enemyDamage)
        XCTAssertFalse(run.inCombat)
        XCTAssertEqual(run.kills, 1)
    }

    func testSeededFightIsRepeatable() {
        func fight(seed: UInt64) -> (Int, Int) {
            var run = makeRun("Warrior")
            var dice = SeededDice(seed: seed)
            Combat.begin(&run, against: Combat.nextEnemy(for: run, dice: &dice))
            while run.inCombat { _ = Combat.takeTurn(&run, .attack, dice: &dice) }
            return (run.hp, run.kills)
        }
        XCTAssertEqual(fight(seed: 42).0, fight(seed: 42).0)
        XCTAssertEqual(fight(seed: 7).1, 1)
    }
}
