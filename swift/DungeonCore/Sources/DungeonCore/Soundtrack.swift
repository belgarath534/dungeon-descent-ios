import Foundation

/// Music, ambience and sound-effect names, from the web version's TRACK_FILES,
/// AMBIENT_FILES and DUNGEON_ENEMY_SFX / DUNGEON_BOSS_SFX.
public struct AudioTables: Decodable, Sendable {
    public let tracks: [String: String]
    public let ambient: [String: String]
    public let enemySfx: [String: String]
    public let bossSfx: [String: String]
}

/// Which music and sounds play where (exploTrackForFloor, battleTrack, getAmbientKey).
public enum Soundtrack {
    static var tables: AudioTables { GameContent.shared.audio }

    /// File name in the audio folder for a music track name ("floor1" → "music-floor1.mp3").
    public static func file(forTrack name: String) -> String? { tables.tracks[name] }

    /// getMenuTrack: the menu plays the holiday's music on Halloween, Friday
    /// the 13th, Christmas and the game's birthday.
    public static func menuTrack(event: String? = Events.active()) -> String {
        switch event {
        case "halloween", "friday13": return "menu-halloween"
        case "christmas": return "menu-christmas"
        case "birthday": return "menu-birthday"
        default: return "menu"
        }
    }

    public static func file(forAmbient key: String) -> String? { tables.ambient[key] }

    private static let prefixes: [String: String] = [
        "The Ashbound Wastes": "ash", "Frosthold Abyss": "frost", "The Sunken Archives": "sunken",
        "The Hollow": "hollow", "The Whispering Forest": "whisper", "The Abyssal Deep": "abyssal",
        "The Infernal Descent": "infernal", "The Shadow World": "shadow",
    ]

    /// Exploration music by depth: three tracks per dungeon and a boss track on floor 10.
    public static func exploreTrack(dungeon: String, floor: Int) -> String {
        if let p = prefixes[dungeon] {
            if floor >= 10 { return "\(p)-boss" }
            // The Hollow uses its first track throughout (its second was a broken upload).
            if p == "hollow" { return "hollow1" }
            return floor <= 3 ? "\(p)1" : floor <= 6 ? "\(p)2" : "\(p)3"
        }
        switch floor {
        case ...1: return "floor1"
        case 2...4: return "floor2"
        case 5...6: return "floor3"
        case 7...9: return "floor4"
        default: return "boss"
        }
    }

    public static func battleTrack(dungeon: String) -> String {
        prefixes[dungeon].map { "\($0)-battle" } ?? "battle"
    }

    public static func bossTrack(dungeon: String) -> String {
        exploreTrack(dungeon: dungeon, floor: 10)
    }

    public static func ambientKey(dungeon: String, difficulty: GameData.Difficulty) -> String {
        if difficulty == .nightmare { return "nightmare" }
        switch dungeon {
        case "The Ashbound Wastes": return "ashbound"
        case "Frosthold Abyss": return "frosthold"
        case "The Sunken Archives": return "sunken"
        case "The Hollow": return "hollow"
        case "The Whispering Forest": return "whisper"
        case "The Infernal Descent": return "infernal"
        case "The Abyssal Deep": return "abyssal"
        case "The Shadow World": return "shadow"
        default: return "crypt"
        }
    }

    /// The sound an enemy makes when it appears, themed by dungeon.
    public static func enemyCue(dungeon: String, boss: Bool) -> String {
        (boss ? tables.bossSfx[dungeon] : tables.enemySfx[dungeon]) ?? (boss ? "sfx-boss-undead" : "sfx-enemy-undead")
    }
}
