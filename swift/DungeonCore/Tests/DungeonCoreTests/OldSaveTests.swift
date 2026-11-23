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
