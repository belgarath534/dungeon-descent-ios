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
