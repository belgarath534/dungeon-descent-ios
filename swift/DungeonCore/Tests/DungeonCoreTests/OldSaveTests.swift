import XCTest
@testable import DungeonCore

final class OldSaveTests: XCTestCase {
    /// A run saved by 12.0 (before the 12.1 fields) still loads.
    func testRunWithoutNewFieldsLoads() throws {
        let r = Run(character: PlayerCharacter(name: "O", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as! [String: Any]
        for k in ["conductor", "conductorFloor", "communityDungeon"] { obj.removeValue(forKey: k) }
        let back = try JSONDecoder().decode(Run.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(back.conductorFloor)
        XCTAssertNil(back.conductor)
        XCTAssertNil(back.communityDungeon)
    }
}

final class SkillBookTests: XCTestCase {
    func testMoveSkillSwapsOrder() {
        var r = Run(character: PlayerCharacter(name: "S", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        let ids = Skills.all(for: "Warrior").prefix(3).map(\.effect)
        r.unlockedSkills = ids
        XCTAssertNil(Skills.move(&r, effect: ids[0], by: -1))
        XCTAssertEqual(Skills.move(&r, effect: ids[0], by: 1), 1)
        XCTAssertEqual(r.unlockedSkills, [ids[1], ids[0], ids[2]])
        XCTAssertNil(Skills.move(&r, effect: ids[2], by: 1))
        XCTAssertEqual(Skills.unlocked(r).map(\.effect), [ids[1], ids[0], ids[2]])
    }
}

final class SanityTests: XCTestCase {
    func run(_ d: GameData.Difficulty) -> Run {
        Run(character: PlayerCharacter(name: "I", cls: "Warrior", race: "Human", prof: "Thief",
                                       dungeon: "Crypt of Malachar", difficulty: d))
    }

    func testOnlyInsaneHasSanity() {
        var r = run(.wanderer)
        XCTAssertTrue(Sanity.drain(&r, 50).isEmpty)
        XCTAssertNil(r.sanity)
        var d = SystemDice()
        XCTAssertNil(Sanity.encounter(for: r, dice: &d))
    }

    func testDrainWarnsAndZeroEndsTheRun() {
        var r = run(.insane)
        XCTAssertEqual(Sanity.value(r), 100)
        XCTAssertTrue(Sanity.drain(&r, 55).first?.contains("50 percent") == true)
        XCTAssertEqual(r.sanity, 45)
        XCTAssertEqual(Sanity.hit(&r, taken: 20).count, 0)
        XCTAssertEqual(r.sanity, 37)
        Sanity.restore(&r, 100)
        XCTAssertEqual(r.sanity, 100)
        _ = Sanity.drain(&r, 100)
        XCTAssertEqual(r.hp, 0)
        r.inventory.append(Item(name: "Phoenix Feather", icon: "🪶", type: "phoenix-feather", desc: ""))
        XCTAssertEqual(Progression.handleDeath(&r), .runOver)
    }

    func testDistortedDrainsSanityNotHp() {
        var r = run(.insane)
        var d = LoadedDice(rolls: [3, 0, 1, 2], chances: [true])
        let e = Sanity.encounter(for: r, dice: &d)!
        XCTAssertEqual(e.name, Sanity.distortedName)
        _ = Combat.begin(&r, against: e)
        let hp = r.hp
        var log: [String] = []
        XCTAssertEqual(Combat.enemyTurn(&r, dice: &d, options: .init(), log: &log), 0)
        XCTAssertEqual(r.hp, hp)
        XCTAssertEqual(r.sanity, 91)
    }

    func testDrainerDropsThePotion() {
        var r = run(.insane)
        var d = LoadedDice(chances: [false, true])
        let e = Sanity.encounter(for: r, dice: &d)!
        XCTAssertEqual(e.name, Sanity.drainerName)
        _ = Combat.begin(&r, against: e)
        XCTAssertEqual(r.sanity, 90)
        var log: [String] = []
        Sanity.onKill(&r, e, log: &log)
        let i = r.inventory.firstIndex { $0.type == "insanity" }!
        var c = LoadedDice(chances: [true])
        r.sanity = 20
        let out = Inventory.use(&r, at: i, dice: &c)
        XCTAssertTrue(out.message.contains("Clarity"))
        XCTAssertEqual(r.sanity, 100)
    }
}

final class EndlessExclusiveTests: XCTestCase {
    func testFloorTwentyEndlessSpawnsOne() {
        var r = Run(character: PlayerCharacter(name: "E", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .endless))
        r.floor = 19
        var d = LoadedDice(rolls: [0], chances: [true])
        XCTAssertNil(EndlessExclusive.encounter(for: r, dice: &d))
        r.floor = 20
        d = LoadedDice(rolls: [0], chances: [true])
        let e = EndlessExclusive.encounter(for: r, dice: &d)
        XCTAssertEqual(e?.name, "The Hydra")
        XCTAssertEqual(e?.hp, Int((95 * 2.14).rounded()))
        XCTAssertEqual(e?.gold, 28...36)
    }
}

final class HolidayFoeTests: XCTestCase {
    func fight(_ flags: [String: JSONValue], name: String = "Foe") -> Run {
        var r = Run(character: PlayerCharacter(name: "H", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        var e = Enemy(name: name, icon: "x", hp: 50, maxHp: 50, atk: 10...10, gold: 1...1)
        e.mechanics = flags
        _ = Combat.begin(&r, against: e)
        r.gold = 25
        return r
    }

    func testLeprechaunStealsGoldNotHp() {
        var r = fight(["stealsGold": .bool(true)], name: "The Leprechaun")
        let hp = r.hp
        var d = LoadedDice()
        var log: [String] = []
        XCTAssertEqual(Combat.enemyTurn(&r, dice: &d, options: .init(), log: &log), 0)
        XCTAssertEqual(r.hp, hp)
        XCTAssertEqual(r.gold, 15)
        XCTAssertEqual(r.fight.stolenGold, 10)
    }

    func testFootballKick() {
        var r = fight(["footballKick": .bool(true)], name: "O Craque")
        let hp = r.hp
        var d = LoadedDice(rolls: [4])
        var log: [String] = []
        _ = Combat.enemyTurn(&r, dice: &d, options: .init(), log: &log)
        XCTAssertEqual(r.hp, hp - 14)
    }

    func testCupidDropsLovePotion() {
        var r = fight(["dropsLovePotion": .bool(true)], name: "The Cupid")
        var log: [String] = []
        HolidayFoes.onKill(&r, r.enemy!, log: &log)
        XCTAssertEqual(r.inventory.last?.name, "Love Potion")
    }
}

final class ChooseDungeonTests: XCTestCase {
    func testTravelNormalAndNewGamePlus() {
        var ch = PlayerCharacter(name: "T", cls: "Warrior", race: "Human", prof: "Thief",
                                 dungeon: "The Abyssal Deep", difficulty: .wanderer)
        ch.completed = true
        ch.travel(to: "Crypt of Malachar", newGamePlus: true, level: 9, xp: 50)
        XCTAssertEqual(ch.dungeon, "Crypt of Malachar")
        XCTAssertTrue(ch.ngPlusActive)
        XCTAssertEqual(ch.ngPlusCount, 1)
        XCTAssertEqual(Run(character: ch).ngPlus, true)
        ch.travel(to: "The Hollow", newGamePlus: false, level: 9, xp: 50)
        XCTAssertEqual(ch.dungeon, "The Hollow")
        XCTAssertFalse(ch.ngPlusActive)
        XCTAssertFalse(ch.completed)
        let r = Run(character: ch)
        XCTAssertFalse(r.ngPlus)
        XCTAssertEqual(r.level, 9)
    }
}
