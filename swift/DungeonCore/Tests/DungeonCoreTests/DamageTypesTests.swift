import XCTest
@testable import DungeonCore

/// 12.4: damage types and enemy weaknesses (docs/12.4-CORRUPTION.md 1–2).
final class DamageTypesTests: XCTestCase {
    func enemy(_ name: String, boss: Bool = false) -> Enemy {
        var e = Enemy(name: name, icon: "👾", hp: 100, maxHp: 100, atk: 5...8, gold: 1...2)
        e.isBoss = boss
        return e
    }

    func testSkillsGetTheRightType() {
        XCTAssertEqual(DamageTypes.of(skillName: "Fireball", desc: "Hurl a ball of flame."), .fire)
        XCTAssertEqual(DamageTypes.of(skillName: "Frost Lance", desc: "A spear of ice."), .ice)
        XCTAssertEqual(DamageTypes.of(skillName: "Chain Lightning", desc: "Lightning jumps."), .storm)
        XCTAssertEqual(DamageTypes.of(skillName: "Smite", desc: "Holy light strikes."), .holy)
        XCTAssertEqual(DamageTypes.of(skillName: "Void Bolt", desc: "Dark energy."), .corruption)
        XCTAssertEqual(DamageTypes.of(skillName: "Toxic Flask", desc: "A flask of poison."), .poison)
        XCTAssertEqual(DamageTypes.of(skillName: "Arcane Missile", desc: "Pure mana."), .arcane)
        XCTAssertEqual(DamageTypes.of(skillName: "Power Strike", desc: "A heavy blow."), .physical)
        XCTAssertEqual(DamageTypes.of(skillName: "Soulfire", desc: "Burns the soul."), .fire)
        XCTAssertEqual(DamageTypes.of(skillName: "Lightning Step", desc: "Move fast."), .storm, "lightning is not light")
    }

    /// Every class has some non-Physical skills, and every skill gets a type.
    /// Prints the count per type and class (for balancing).
    func testEveryClassSkillHasAType() {
        var counts: [DamageType: Int] = [:]
        var report: [String] = []
        for c in GameData.classes {
            let skills = Skills.all(for: c.id)
            XCTAssertFalse(skills.isEmpty, c.id)
            let types = skills.map { DamageTypes.of($0) }
            for t in types { counts[t, default: 0] += 1 }
            report.append("\(c.id): " + zip(skills, types).map { "\($0.name)=\($1.rawValue)" }.joined(separator: ", "))
        }
        let path = ProcessInfo.processInfo.environment["DD_TYPE_REPORT"]
        if let path { try? report.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8) }
        print("Skill types:", DamageType.allCases.map { "\($0.rawValue) \(counts[$0] ?? 0)" }.joined(separator: ", "))
        XCTAssertGreaterThan(counts[.physical] ?? 0, 0)
        XCTAssertGreaterThan(counts[.fire] ?? 0, 5)
        XCTAssertGreaterThan(counts[.holy] ?? 0, 5)
        XCTAssertGreaterThan(counts[.corruption] ?? 0, 5)
    }

    func testEnemiesAreWeakOrStrong() {
        let m = { (t: DamageType, n: String, d: String) in DamageTypes.multiplier(t, against: self.enemy(n), dungeon: d) }
        XCTAssertEqual(m(.fire, "Frost Wraith", "Frosthold Abyss"), DamageTypes.weak)
        XCTAssertEqual(m(.ice, "Frost Wraith", "Frosthold Abyss"), DamageTypes.immune)
        XCTAssertEqual(m(.holy, "Frost Wraith", "Frosthold Abyss"), DamageTypes.weak, "a wraith is a spirit")
        XCTAssertEqual(m(.ice, "Cinder Imp", "The Ashbound Wastes"), DamageTypes.weak)
        XCTAssertEqual(m(.fire, "Cinder Imp", "The Ashbound Wastes"), DamageTypes.immune)
        XCTAssertEqual(m(.holy, "Brittle Skeleton", "Crypt of Malachar"), DamageTypes.weak)
        XCTAssertEqual(m(.poison, "Brittle Skeleton", "Crypt of Malachar"), DamageTypes.immune)
        XCTAssertEqual(m(.corruption, "Void Crawler", "The Shadow World"), DamageTypes.absorbs)
        XCTAssertEqual(m(.corruption, "Fallen Seraph", "The Sky Ruins"), DamageTypes.veryWeak)
        XCTAssertEqual(m(.physical, "Stone Golem", "Crypt of Malachar"), DamageTypes.resists)
        XCTAssertEqual(m(.fire, "Cursed Frost Wraith", "Frosthold Abyss"), DamageTypes.weak, "prefixes don't change it")
        XCTAssertEqual(DamageTypes.multiplier(.holy, against: enemy("Malachar the Undying", boss: true), dungeon: "Crypt of Malachar"), DamageTypes.veryWeak)
        XCTAssertEqual(DamageTypes.multiplier(.fire, against: enemy("Queen Verdana", boss: true), dungeon: "The Sky Ruins"), DamageTypes.weak)
    }

    /// No enemy anywhere is immune to more than one type, and none takes
    /// less than half from Physical.
    func testEveryEnemyCanBeBeaten() {
        for d in GameData.dungeons {
            let t = Bestiary.enemies(for: d)
            for tpl in t.pool(forFloor: 1) + t.pool(forFloor: 5) + t.pool(forFloor: 8) + t.elites + t.bosses {
                let a = DamageTypes.affinities(Enemy(name: tpl.name, icon: tpl.icon, hp: tpl.hp, maxHp: tpl.hp, atk: tpl.atk, gold: tpl.gold), dungeon: d)
                XCTAssertLessThanOrEqual(a.values.filter { $0 == 0 }.count, 1, "\(tpl.name) is immune to too much")
                XCTAssertGreaterThanOrEqual(a[.physical] ?? 1, 0.5, tpl.name)
            }
        }
    }

    func testHittingAWeaknessHurtsMore() {
        var r = Run(character: PlayerCharacter(name: "T", cls: "Elementalist", race: "Human", prof: "Thief",
                                               dungeon: "Frosthold Abyss", difficulty: .wanderer))
        var e = enemy("Frost Wraith")
        var log: [String] = []
        XCTAssertEqual(DamageTypes.apply(100, .fire, enemy: &e, run: &r, log: &log), 175)
        XCTAssertEqual(DamageTypes.apply(100, .ice, enemy: &e, run: &r, log: &log), 1, "immune still takes 1")
        XCTAssertEqual(r.learnedAffinities?["Frost Wraith"]?["fire"], 1.75)
        XCTAssertEqual(DamageTypes.describe(r.learnedAffinities?["Frost Wraith"] ?? [:]), "Weak to 🔥 Fire · Immune to ❄️ Ice")
        var v = enemy("Void Crawler")
        v.hp = 50
        XCTAssertEqual(DamageTypes.apply(100, .corruption, enemy: &v, run: &r, log: &log), 0)
        XCTAssertEqual(v.hp, 100, "it drinks in the corruption")
    }
}
