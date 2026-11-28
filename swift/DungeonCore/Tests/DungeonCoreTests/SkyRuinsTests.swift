import XCTest
@testable import DungeonCore

/// 12.3: The Sky Ruins. Its data loads, its mechanics do what the design
/// says, and a bot can play every class through its fights and conquer
/// Queen Verdana without the game breaking.
final class SkyRuinsTests: XCTestCase {
    let play = makeAutoPlay()
    let bots = makeCreationBots()

    func skyRun(_ cls: String = "Warrior", race: String = "Human") -> Run {
        Run(character: PlayerCharacter(name: "Bot", cls: cls, race: race, prof: "Thief",
                                       dungeon: SkyRuins.name, difficulty: .wanderer))
    }

    func testTheDungeonIsThere() {
        XCTAssertEqual(GameData.dungeons.last, SkyRuins.name)
        let t = Bestiary.enemies(for: SkyRuins.name, difficulty: .wanderer)
        XCTAssertEqual(t.pool(forFloor: 1).count, 5)
        XCTAssertEqual(t.pool(forFloor: 5).count, 5)
        XCTAssertEqual(t.pool(forFloor: 8).count, 4)
        XCTAssertEqual(t.elites.count, 4)
        XCTAssertEqual(t.bosses.map(\.name), ["Queen Verdana"])
        XCTAssertEqual(Soundtrack.exploreTrack(dungeon: SkyRuins.name, floor: 2), "skyruins1")
        XCTAssertEqual(Soundtrack.exploreTrack(dungeon: SkyRuins.name, floor: 10), "skyruins-boss")
        XCTAssertEqual(Soundtrack.battleTrack(dungeon: SkyRuins.name), "skyruins-battle")
        XCTAssertEqual(Soundtrack.ambientKey(dungeon: SkyRuins.name, difficulty: .wanderer), "sky")
        XCTAssertEqual(Rooms.floorName(1, dungeon: SkyRuins.name), "The Landing")
    }

    func testItUnlocksAfterTheShadowWorld() {
        let store = MemoryStore()
        XCTAssertFalse(SkyRuins.unlocked(store))
        store.setItem("dd_cleared_dungeons", "[\"The Shadow World\"]")
        XCTAssertTrue(SkyRuins.unlocked(store))
    }

    func testPoisonStacksToFiveAndWearsOff() {
        var r = skyRun()
        var log: [String] = []
        for _ in 0..<7 { SkyRuins.addPoison(&r, 1, source: "a test", log: &log) }
        XCTAssertEqual(r.sky?.poison, 5)
        XCTAssertEqual(SkyRuins.poisonPerTurn(r), 10)
        r.hp = 5
        SkyRuins.tickPoison(&r, boss: false, log: &log)
        XCTAssertEqual(r.hp, 1, "Outside a boss fight poison can't take you below 1 HP")
        for _ in 0..<3 { SkyRuins.tickPoison(&r, boss: false, log: &log) }
        XCTAssertEqual(r.sky?.poison, 0, "Poison lasts 4 turns")
        r.cls = "PlagueDoctor"
        SkyRuins.addPoison(&r, 3, source: "a test", log: &log)
        XCTAssertEqual(SkyRuins.poisonPerTurn(r), 3, "The Plague Doctor takes half")
    }

    func testTheGardenGrowsEveryEightTurns() {
        var r = skyRun()
        var dice = SeededDice(seed: 3)
        r.floor = 2
        let foe = Combat.nextEnemy(for: r, dice: &dice)
        Combat.begin(&r, against: foe)
        let hp = r.enemy!.maxHp
        var log: [String] = []
        for _ in 0..<8 { _ = SkyRuins.turnStart(&r, attacking: false, log: &log) }
        XCTAssertEqual(r.sky?.gardenStage, 1)
        XCTAssertEqual(r.enemy!.maxHp, jsRound(Double(hp) * 1.1))
        _ = SkyRuins.newFloor(&r)
        XCTAssertEqual(r.sky?.gardenStage, 0)
    }

    func testVerdanaThornWallRegrowthAndBurning() {
        var r = skyRun()
        var dice = SeededDice(seed: 9)
        r.floor = 10
        let boss = Combat.nextBoss(for: r, dice: &dice)
        Combat.begin(&r, against: boss)
        var log: [String] = []
        // Down to two thirds: the thorn wall takes the next hit.
        let toWall = r.enemy!.hp - jsRound(Double(r.enemy!.maxHp) * 0.6)
        Combat.dealDamage(&r, toWall, log: &log)
        XCTAssertTrue(r.enemy!.flag("skyThornwall"))
        XCTAssertEqual(SkyRuins.attackMultiplier(r), 0.5)
        let before = r.enemy!.hp
        Combat.dealDamage(&r, 30, log: &log)
        XCTAssertEqual(r.enemy!.hp, before, "The hit goes to the thorn wall")
        XCTAssertFalse(r.enemy!.flag("skyThornwall"))
        // Below a third: she regrows 20 a turn until her roots burn.
        Combat.dealDamage(&r, r.enemy!.hp - jsRound(Double(r.enemy!.maxHp) * 0.3), log: &log)
        XCTAssertTrue(r.enemy!.flag("skyPhase3"))
        let low = r.enemy!.hp
        _ = SkyRuins.turnStart(&r, attacking: false, log: &log)
        XCTAssertEqual(r.enemy!.hp, low + 20)
        r.inventory.append(SkyRuins.rootTorch)
        let out = Inventory.use(&r, at: r.inventory.count - 1, dice: &dice)
        XCTAssertTrue(out.used)
        let burnt = r.enemy!.hp
        _ = SkyRuins.turnStart(&r, attacking: false, log: &log)
        XCTAssertEqual(r.enemy!.hp, burnt, "Burned roots don't regrow")
    }

    func testFloorNineGivesARootTorch() {
        var r = skyRun()
        r.floor = 9
        _ = SkyRuins.newFloor(&r)
        XCTAssertTrue(r.inventory.contains { $0.name == "Root Torch" })
    }

    func testSeedOfTheUndyingSavesOnce() {
        var r = skyRun()
        r.inventory.append(SkyRuins.seed)
        var log: [String] = []
        r.hp = 0
        XCTAssertTrue(SkyRuins.seedSaves(&r, log: &log))
        XCTAssertEqual(r.hp, 1)
        r.hp = 0
        XCTAssertFalse(SkyRuins.seedSaves(&r, log: &log))
    }

    func testEveryHazardHasWorkingChoices() {
        for id in ["sky-gust", "sky-edge", "sky-ivy", "sky-spore", "sky-thornwall", "sky-siren"] {
            guard let ev = Encounters.event(id) else { return XCTFail("No event \(id)") }
            for c in ev.choices.indices {
                var r = skyRun()
                r.pendingEvent = id
                var dice = SeededDice(seed: 1)
                let out = Encounters.choose(c, &r, dice: &dice, wallet: Wallet(store: MemoryStore()))
                XCTAssertFalse(out.message.isEmpty, "\(id) choice \(c) says nothing")
                XCTAssertGreaterThan(r.hp, 0)
                if id == "sky-edge" { XCTAssertTrue(out.skyFall) }
                if id == "sky-gust" && c == 1 { XCTAssertTrue(out.skyCarried) }
            }
        }
    }

    /// Every class fights through the Sky Ruins' floors with random buttons,
    /// then takes on Queen Verdana until she falls: nothing may break.
    func testEveryClassConquersTheSkyRuins() {
        var problems: [String] = []
        var conquered = 0
        for (i, c) in GameData.classes.enumerated() {
            var dice = SeededDice(seed: UInt64(100 + i))
            var r = skyRun(c.id, race: ["Human", "Goliath", "Aarakocra"][i % 3])
            r.unlockedSkills = Skills.all(for: r.cls).map(\.effect)
            for floor in 1...9 {
                r.floor = floor
                _ = SkyRuins.newFloor(&r)
                r.hp = r.maxHp; r.sp = r.maxSp
                Combat.begin(&r, against: Combat.nextEnemy(for: r, dice: &dice))
                if let p = bots.playOne(&r, dice: &dice) { problems.append("\(c.id) floor \(floor): \(p)") }
            }
            // The boss. The bot is healed every turn so the whole fight is
            // played (not by raising max HP: some boss hits are a share of it).
            r.floor = 10
            // About what a player has by floor 10 (the bot is level 1).
            r.maxHp = max(r.maxHp, 400)
            r.hp = r.maxHp; r.sp = r.maxSp
            r.inventory.append(SkyRuins.rootTorch)
            Combat.begin(&r, against: Combat.nextBoss(for: r, dice: &dice))
            var achievements: [String] = []
            var lastLog: [String] = []
            var turns = 0
            var torch = "not used"
            for turn in 0..<400 {
                guard r.inCombat, r.enemy != nil else { break }
                turns = turn
                // Burn her roots when she warns about them, as a player would.
                if r.enemy?.flag("skyWarned") == true || r.enemy?.flag("skyPhase3") == true,
                   r.enemy?.flag("skyBurned") != true, let i = r.inventory.firstIndex(where: { $0.name == "Root Torch" }) {
                    torch = Inventory.use(&r, at: i, dice: &dice).message
                }
                r.hp = r.maxHp
                r.sky?.poison = 0
                let res = Combat.takeTurn(&r, turn % 3 == 0 ? .heavy : .attack, dice: &dice)
                achievements += res.achievements
                lastLog = Array((lastLog + res.log).suffix(6))
                if let p = play.brokenState(r) { problems.append("\(c.id) vs Verdana: \(p)"); break }
            }
            if achievements.contains("skyVerdanaKills") {
                conquered += 1
                XCTAssertTrue(r.inventory.contains { $0.name == "Seed of the Undying" }, "\(c.id): no seed")
            } else if problems.count < 3 {
                let e = r.enemy
                problems.append("\(c.id) didn't beat Verdana: \(turns) turns, in combat \(r.inCombat), enemy \(e?.name ?? "none") \(e?.hp ?? -1)/\(e?.maxHp ?? -1), burned \(e?.flag("skyBurned") ?? false), phase3 \(e?.flag("skyPhase3") ?? false), torch: \(torch), achievements \(achievements), last log: \(lastLog.joined(separator: " | "))")
            }
        }
        XCTAssert(problems.isEmpty, "The Sky Ruins broke the game:\n" + problems.joined(separator: "\n"))
        XCTAssertEqual(conquered, GameData.classes.count, "Every class should be able to beat Queen Verdana")
    }
}
