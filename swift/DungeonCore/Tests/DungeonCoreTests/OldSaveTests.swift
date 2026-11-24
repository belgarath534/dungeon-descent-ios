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

final class NewFoesTests: XCTestCase {
    func run(_ dungeon: String, floor: Int = 4) -> Run {
        var r = Run(character: PlayerCharacter(name: "N", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: dungeon, difficulty: .wanderer))
        r.floor = floor
        r.spirit = nil
        return r
    }

    func spawn(_ dungeon: String) -> Run {
        var r = run(dungeon)
        var d = LoadedDice(rolls: [0, 0], chances: [true])
        let e = NewFoes.encounter(for: r, dice: &d)!
        _ = Combat.begin(&r, against: e)
        return r
    }

    func testOnlyInTheirDungeonFromFloorThree() {
        var d = LoadedDice(chances: [true])
        XCTAssertNil(NewFoes.encounter(for: run("Crypt of Malachar", floor: 2), dice: &d))
        d = LoadedDice(chances: [true])
        XCTAssertEqual(NewFoes.encounter(for: run("Crypt of Malachar"), dice: &d)?.name, NewFoes.counter)
        d = LoadedDice(chances: [true])
        XCTAssertEqual(NewFoes.encounter(for: run("The Hollow"), dice: &d)?.name, NewFoes.liar)
        d = LoadedDice(chances: [true])
        XCTAssertEqual(NewFoes.encounter(for: run("The Sunken Archives"), dice: &d)?.name, NewFoes.bellChoir)
        d = LoadedDice(chances: [true])
        XCTAssertEqual(NewFoes.encounter(for: run("The Shadow World"), dice: &d)?.name, NewFoes.silent)
        d = LoadedDice(chances: [true])
        XCTAssertNil(NewFoes.encounter(for: run("Frosthold Abyss"), dice: &d))
    }

    func testCountingThingHitsTripleAtZeroAndDefendResets() {
        var r = spawn("Crypt of Malachar")
        var d = LoadedDice()
        var log: [String] = []
        var hits: [Int] = []
        for _ in 0..<6 {
            r.hp = r.maxHp
            hits.append(Combat.enemyTurn(&r, dice: &d, options: .init(), log: &log))
        }
        XCTAssertTrue(log.contains("🔢 Five…"))
        XCTAssertTrue(log.contains("🔢 ZERO. It strikes with everything it has!"))
        XCTAssertGreaterThan(hits[5], hits[4] * 2)
        r.defending = true
        log = []
        _ = Combat.enemyTurn(&r, dice: &d, options: .init(), log: &log)
        XCTAssertEqual(r.enemy?.number("count"), 5)
    }

    func testBellHealSkipsTheAttack() {
        var r = spawn("The Sunken Archives")
        var e = r.enemy!
        e.hp = 10
        e.mechanics["bellNext"] = .string("heal")
        r.enemy = e
        let hp = r.hp
        var d = LoadedDice()
        var log: [String] = []
        XCTAssertEqual(Combat.enemyTurn(&r, dice: &d, options: .init(), log: &log), 0)
        XCTAssertEqual(r.hp, hp)
        XCTAssertGreaterThan(r.enemy!.hp, 10)
        XCTAssertTrue(log.contains { $0.hasPrefix("🔔") && $0.contains("rings") })
    }

    func testLiarAndSilentChangeOnlyWhatYouHear() {
        let liar = spawn("The Hollow")
        var d = LoadedDice(chances: [true, true])
        let said = NewFoes.announcement(liar.enemy!, run: liar, taken: 9, playerDamage: 5, log: [], dice: &d)!
        XCTAssertTrue(said.hasPrefix("The Liar misses you completely!"))
        XCTAssertTrue(said.hasSuffix("Your HP: \(liar.hp) of \(liar.maxHp)."))
        let silent = spawn("The Shadow World")
        d = LoadedDice()
        XCTAssertEqual(NewFoes.announcement(silent.enemy!, run: silent, taken: 7, playerDamage: 0, log: [], dice: &d),
                       "Silence. Your HP: \(silent.hp) of \(silent.maxHp).")
    }
}

final class WayToNewRoomTests: XCTestCase {
    func testPointsTowardTheNearestUnvisitedRoom() {
        var d = SeededDice(seed: 7)
        var g = RoomGraph(roomsNeeded: 8, dice: &d)
        // Walk through new rooms until we're standing somewhere visited, then check the hint.
        var steps = 0
        while g.unvisited > 0 && steps < 200 {
            guard let way = g.wayToNew() else { XCTFail("No way to a new room with \(g.unvisited) left"); return }
            XCTAssertTrue(g.here.has(way))
            _ = g.move(way)
            steps += 1
        }
        XCTAssertEqual(g.unvisited, 0)
        XCTAssertNil(g.wayToNew())
        XCTAssertEqual(g.wayToNewText, "")
    }
}

final class MagicChamberTests: XCTestCase {
    final class Mem: GameStore {
        var d: [String: String] = [:]
        func getItem(_ key: String) -> String? { d[key] }
        func setItem(_ key: String, _ value: String) { d[key] = value }
        func removeItem(_ key: String) { d[key] = nil }
        func setItems(_ items: [String: String]) { items.forEach { d[$0] = $1 } }
    }

    func testUnicornJoinsOnceAndHealsInFights() {
        let store = Mem()
        var r = Run(character: PlayerCharacter(name: "U", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.hp = 5
        r.pendingEvent = MagicChamber.id
        var d = LoadedDice()
        let out = Encounters.choose(0, &r, dice: &d, wallet: Wallet(store: store), store: store)
        XCTAssertTrue(out.message.contains("Starlight the Unicorn has joined you"))
        XCTAssertEqual(r.hp, r.maxHp)
        XCTAssertEqual(Home.minions(store).filter { $0.id == MagicChamber.minionId }.count, 1)
        r.pendingEvent = MagicChamber.id
        let again = Encounters.choose(0, &r, dice: &d, wallet: Wallet(store: store), store: store)
        XCTAssertFalse(again.message.contains("has joined"))
        XCTAssertEqual(Home.minions(store).filter { $0.id == MagicChamber.minionId }.count, 1)

        r.minion = Home.minions(store).first { $0.id == MagicChamber.minionId }
        _ = Combat.begin(&r, against: Enemy(name: "Dummy", icon: "x", hp: 100, maxHp: 100, atk: 1...1, gold: 1...1))
        r.hp = 10
        var log: [String] = []
        Combat.minionAttack(&r, dice: &d, log: &log)
        XCTAssertEqual(r.hp, 10 + MagicChamber.heal)
        XCTAssertTrue(log.contains { $0.contains("Starlight's horn glows") })
    }
}
