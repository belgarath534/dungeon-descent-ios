import Foundation

/// The game's data tables, loaded once from gamedata.json. That file is made
/// from the web version by swift/tools/extract-game-data.js.
public final class GameContent: Decodable, @unchecked Sendable {
    public struct Dungeon: Decodable, Sendable {
        public let enemies: DungeonEnemies
        public let loot: [Item]
        public let shop: [Item]
        public let rooms: [String]
        public let floors: [String]
    }

    public let dungeons: [String: Dungeon]
    public let nightmareEnemies: DungeonEnemies?
    public let traps: [String: [Trap]]
    public let classSkills: [String: [Skill]]
    public let startingSkills: [String: String]
    public let audio: AudioTables
    public let enemySpecials: [String: EnemySpecial]
    public let achievements: [Achievement]
    public let dailyQuests: [DailyQuest]

    public static let shared: GameContent = {
        guard let url = Bundle.module.url(forResource: "gamedata", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("gamedata.json is missing from the DungeonCore bundle")
        }
        do {
            return try JSONDecoder().decode(GameContent.self, from: data)
        } catch {
            fatalError("gamedata.json could not be read: \(error)")
        }
    }()

    /// A dungeon's tables, or the Crypt's for an unknown name.
    public func dungeon(_ name: String) -> Dungeon {
        dungeons[name] ?? dungeons[GameData.dungeons[0]]!
    }
}
