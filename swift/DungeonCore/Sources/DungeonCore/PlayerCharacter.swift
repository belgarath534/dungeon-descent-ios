import Foundation

/// A saved character, in the same JSON shape as the web version's `CHARS` entries.
/// Fields the Swift version doesn't use yet are kept in `extra` and written back
/// untouched, so a web save survives a round trip through the Swift app.
public struct PlayerCharacter: Equatable, Sendable {
    public var name: String
    public var cls: String
    public var race: String
    public var prof: String
    public var dungeon: String
    public var difficulty: String
    public var floor: Int
    /// Milliseconds since 1970, as JavaScript's Date.now().
    public var created: Double
    public var runMode: String
    public var lastSpirit: String?
    public var corruptionMode: Bool
    public var corruption: Int
    public var hunterMode: Bool
    public var hardcoreMode: Bool
    public var guidePersonality: String
    public var guideEnabled: Bool
    public var levelCap: Int
    public var dungeonTier: Int?
    public var persistLevel: Int?
    public var completed: Bool
    public var ngPlusActive: Bool
    /// Every other field from the save, kept as-is.
    public var extra: [String: JSONValue]

    public var difficultyLevel: GameData.Difficulty { GameData.Difficulty(rawValue: difficulty) ?? .wanderer }

    /// Same defaults as the web version's finalizeChar().
    public init(name: String, cls: String, race: String, prof: String, dungeon: String,
                difficulty: GameData.Difficulty, runMode: String = "classic", spirit: String? = nil,
                corruptionMode: Bool = false, hunterMode: Bool = false, hardcoreMode: Bool = false,
                guidePersonality: String = "encouraging", created: Date = Date()) {
        self.name = name
        self.cls = cls
        self.race = race
        self.prof = prof
        self.dungeon = dungeon
        self.difficulty = difficulty.rawValue
        self.floor = 0
        self.created = (created.timeIntervalSince1970 * 1000).rounded()
        self.runMode = runMode
        self.lastSpirit = spirit
        self.corruptionMode = corruptionMode
        self.corruption = 0
        self.hunterMode = hunterMode
        self.hardcoreMode = hardcoreMode
        self.guidePersonality = guidePersonality
        self.guideEnabled = true
        let legacy = runMode == "legacy"
        self.dungeonTier = legacy ? 1 : nil
        self.persistLevel = legacy ? 1 : nil
        self.levelCap = legacy ? 25 : 10
        self.completed = false
        self.ngPlusActive = false
        self.extra = ["earnedSpirits": .array([])]
    }

    /// Name rule from character creation: 2 to 24 characters.
    public static func isValidName(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces).count
        return n >= 2 && n <= 24
    }
}

extension PlayerCharacter: Codable {
    private static let knownKeys: Set<String> = [
        "name", "cls", "race", "prof", "dungeon", "difficulty", "floor", "created", "runMode",
        "lastSpirit", "corruptionMode", "corruption", "hunterMode", "hardcoreMode",
        "guidePersonality", "guideEnabled", "levelCap", "dungeonTier", "persistLevel",
        "completed", "ngPlusActive",
    ]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        // Old saves can be missing fields or hold odd types; read leniently.
        func str(_ k: String, _ d: String = "") -> String { (try? c.decode(String.self, forKey: AnyKey(k))) ?? d }
        func num(_ k: String) -> Double? { try? c.decode(Double.self, forKey: AnyKey(k)) }
        func bool(_ k: String, _ d: Bool = false) -> Bool { (try? c.decode(Bool.self, forKey: AnyKey(k))) ?? d }

        name = str("name")
        cls = str("cls")
        race = str("race")
        prof = str("prof")
        dungeon = str("dungeon", GameData.dungeons[0])
        difficulty = str("difficulty", "Wanderer")
        floor = Int(num("floor") ?? 0)
        created = num("created") ?? 0
        runMode = str("runMode", "classic")
        lastSpirit = try? c.decode(String.self, forKey: AnyKey("lastSpirit"))
        corruptionMode = bool("corruptionMode")
        corruption = Int(num("corruption") ?? 0)
        hunterMode = bool("hunterMode")
        hardcoreMode = bool("hardcoreMode")
        guidePersonality = str("guidePersonality", "encouraging")
        guideEnabled = bool("guideEnabled", true)
        levelCap = Int(num("levelCap") ?? 10)
        dungeonTier = num("dungeonTier").map { Int($0) }
        persistLevel = num("persistLevel").map { Int($0) }
        completed = bool("completed")
        ngPlusActive = bool("ngPlusActive")

        var rest: [String: JSONValue] = [:]
        for key in c.allKeys where !Self.knownKeys.contains(key.stringValue) {
            rest[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
        }
        extra = rest
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (k, v) in extra { try c.encode(v, forKey: AnyKey(k)) }
        try c.encode(name, forKey: AnyKey("name"))
        try c.encode(cls, forKey: AnyKey("cls"))
        try c.encode(race, forKey: AnyKey("race"))
        try c.encode(prof, forKey: AnyKey("prof"))
        try c.encode(dungeon, forKey: AnyKey("dungeon"))
        try c.encode(difficulty, forKey: AnyKey("difficulty"))
        try c.encode(floor, forKey: AnyKey("floor"))
        try c.encode(created, forKey: AnyKey("created"))
        try c.encode(runMode, forKey: AnyKey("runMode"))
        try c.encode(lastSpirit, forKey: AnyKey("lastSpirit"))
        try c.encode(corruptionMode, forKey: AnyKey("corruptionMode"))
        try c.encode(corruption, forKey: AnyKey("corruption"))
        try c.encode(hunterMode, forKey: AnyKey("hunterMode"))
        try c.encode(hardcoreMode, forKey: AnyKey("hardcoreMode"))
        try c.encode(guidePersonality, forKey: AnyKey("guidePersonality"))
        try c.encode(guideEnabled, forKey: AnyKey("guideEnabled"))
        try c.encode(levelCap, forKey: AnyKey("levelCap"))
        try c.encodeIfPresent(dungeonTier, forKey: AnyKey("dungeonTier"))
        try c.encodeIfPresent(persistLevel, forKey: AnyKey("persistLevel"))
        if completed { try c.encode(true, forKey: AnyKey("completed")) }
        if ngPlusActive { try c.encode(true, forKey: AnyKey("ngPlusActive")) }
    }
}

/// Loads and saves the character list under "dd_chars", like saveChars() does.
public final class CharacterRoster {
    private let store: GameStore
    public private(set) var characters: [PlayerCharacter]

    public init(store: GameStore) {
        self.store = store
        if let raw = store.getItem(StoreKey.chars), let data = raw.data(using: .utf8),
           let list = try? JSONDecoder().decode([PlayerCharacter].self, from: data) {
            characters = list
        } else {
            characters = []
        }
    }

    public var isFull: Bool { characters.count >= GameData.maxCharacters }

    /// Adds a character and saves. Returns its index, or nil if all slots are used.
    @discardableResult
    public func add(_ ch: PlayerCharacter) -> Int? {
        guard !isFull else { return nil }
        characters.append(ch)
        save()
        return characters.count - 1
    }

    public func update(_ index: Int, _ change: (inout PlayerCharacter) -> Void) {
        guard characters.indices.contains(index) else { return }
        change(&characters[index])
        save()
    }

    public func remove(at index: Int) {
        guard characters.indices.contains(index) else { return }
        characters.remove(at: index)
        save()
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(characters),
              let json = String(data: data, encoding: .utf8) else { return }
        store.setItem(StoreKey.chars, json)
    }

    /// Dungeons this player can pick. Mirrors getUnlockedDungeons() plus
    /// repairDungeonUnlocks(): finishing a dungeon (completed, reached floor 10,
    /// or died on floor 9 or deeper) unlocks the next one.
    public func unlockedDungeons() -> [String] {
        var unlocks = (store.getItem(StoreKey.unlocks).flatMap { $0.data(using: .utf8) })
            .flatMap { try? JSONDecoder().decode([String: JSONValue].self, from: $0) } ?? [:]
        func isUnlocked(_ d: String) -> Bool {
            switch unlocks[d] {
            case .bool(true): return true
            case .number(let n): return n != 0
            case .string(let s): return !s.isEmpty
            case .array, .object: return true
            default: return false
            }
        }
        var changed = false
        for ch in characters where ch.finishedDungeon {
            if let i = GameData.dungeons.firstIndex(of: ch.dungeon), i < GameData.dungeons.count - 1 {
                let next = GameData.dungeons[i + 1]
                if !isUnlocked(next) { unlocks[next] = .bool(true); changed = true }
            }
        }
        if changed, let data = try? JSONEncoder().encode(unlocks), let s = String(data: data, encoding: .utf8) {
            store.setItem(StoreKey.unlocks, s)
        }
        return GameData.dungeons.enumerated().filter { $0.offset == 0 || isUnlocked($0.element) }.map(\.element)
    }
}

extension PlayerCharacter {
    /// The completion check repairDungeonUnlocks() uses.
    var finishedDungeon: Bool {
        if completed || floor >= 10 { return true }
        guard case .array(let log)? = extra["deathLog"] else { return false }
        return log.contains {
            if case .object(let entry) = $0, case .number(let f)? = entry["floor"] { return f >= 9 }
            return false
        }
    }
}
