import XCTest
@testable import DungeonCore

/// 12.3: Plague Doctor, Artificer, Aarakocra, Goliath and Impossible mode.
final class NewHeroesTests: XCTestCase {
    func run(_ cls: String, race: String = "Human", _ diff: GameData.Difficulty = .wanderer) -> Run {
        var r = Run(character: PlayerCharacter(name: "H", cls: cls, race: race, prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: diff))
        _ = Races.start(&r, classTraits: true, wallet: Wallet(store: MemoryStore()))
        return r
    }

    func testTheNewClassesHaveStatsAndFifteenWorkingSkills() {
        for (cls, hp) in [("PlagueDoctor", 95), ("Artificer", 100)] {
            XCTAssertEqual(GameData.classInfo(cls).maxHp, hp)
            let skills = Skills.all(for: cls)
            XCTAssertEqual(skills.count, 15, cls)
            for s in skills {
                XCTAssertNotNil(SkillTable.specs["\(cls)/\(s.effect)"], "\(cls) \(s.name) has no rule")
            }
        }
    }

    func testRacesChangeHealth() {
        let human = run("Artificer", race: "Human").maxHp
        let bird = run("Artificer", race: "Aarakocra").maxHp
        let giant = run("Artificer", race: "Goliath").maxHp
        XCTAssertLessThan(bird, human)
        XCTAssertGreaterThan(giant, human)
    }

    func testImpossible() {
        let r = run("Warrior", .impossible)
        XCTAssertEqual(r.lives, 1)
        XCTAssertEqual(GameData.Difficulty.impossible.enemyDamageMultiplier, 1.6)
        XCTAssertEqual(Races.potionHeal(r, 40), 20)
        var fight = r
        var dice = SeededDice(seed: 4)
        let foe = Combat.nextEnemy(for: fight, dice: &dice)
        Combat.begin(&fight, against: foe)
        XCTAssertEqual(fight.enemy?.maxHp, jsRound(Double(foe.maxHp) * 1.8))
        // No revives: the Seed of the Undying does nothing.
        fight.inventory.append(SkyRuins.seed)
        fight.hp = 0
        var log: [String] = []
        XCTAssertFalse(SkyRuins.seedSaves(&fight, log: &log))
    }

    func testBothNewClassesFightWithEverySkill() {
        let bots = CreationBotTests()
        for cls in ["PlagueDoctor", "Artificer"] {
            var dice = SeededDice(seed: 21)
            var r = run(cls, race: cls == "PlagueDoctor" ? "Goliath" : "Aarakocra")
            if let p = bots.fight(&r, dice: &dice, fights: 12) { XCTFail("\(cls): \(p)") }
        }
    }
}
