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

    /// Deleting a character from the list puts it in The Graveyard first
    /// ("dd_graveyard", newest first, 50 kept), like confirmDelete().
    public func bury(at index: Int, date: Date = Date()) {
        guard characters.indices.contains(index) else { return }
        let ch = characters[index]
        let deaths = ch.deaths
        var journal = ""
        switch ch.extra["journal"] {
        case .array(let a)?:
            if case .object(let o)? = a.first, case .string(let t)? = o["text"] { journal = t }
        case .string(let t)?: journal = t
        case .object(let o)?: if case .string(let t)? = o["text"] { journal = t }
        default: break
        }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let entry: JSONValue = .object([
            "name": .string(ch.name),
            "cls": .string(ch.cls),
            "race": .string(ch.race),
            "prof": .string(ch.prof),
            "dungeon": .string(ch.dungeon),
            "difficulty": .string(ch.difficulty),
            "level": .number(Double(ch.persistLevel ?? 1)),
            "deaths": .number(Double(deaths.count)),
            "topFloor": .number(Double(deaths.first?.floor ?? 0)),
            "killedBy": .string(deaths.first?.killedBy ?? "unknown causes"),
            "journal": .string(journal),
            "date": .string("\(c.month ?? 1)/\(c.day ?? 1)/\(c.year ?? 2026)"),
        ])
        var list: [JSONValue] = []
        if let raw = store.getItem("dd_graveyard"), let d = raw.data(using: .utf8),
           let old = try? JSONDecoder().decode([JSONValue].self, from: d) { list = old }
        list.insert(entry, at: 0)
        if let d = try? JSONEncoder().encode(Array(list.prefix(50))), let out = String(data: d, encoding: .utf8) {
            store.setItem("dd_graveyard", out)
        }
        remove(at: index)
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

extension PlayerCharacter {
    /// After a victory: go on to the next dungeon, keeping level and XP
    /// (continueJourney). Returns false after the last dungeon.
    public mutating func continueJourney(level: Int, xp: Int) -> Bool {
        guard let i = GameData.dungeons.firstIndex(of: dungeon), i < GameData.dungeons.count - 1 else { return false }
        dungeon = GameData.dungeons[i + 1]
        floor = 1
        completed = false
        extra["midRunSave"] = nil
        extra["carryLevel"] = .number(Double(level))
        extra["carryXp"] = .number(Double(xp))
        return true
    }

    /// After a victory: replay the dungeon with stronger enemies (startNGPlus).
    public mutating func startNewGamePlus() {
        floor = 1
        completed = false
        ngPlusActive = true
        extra["ngPlus"] = .bool(true)
        var count = 0.0
        if case .number(let n)? = extra["ngPlusCount"] { count = n }
        extra["ngPlusCount"] = .number(count + 1)
        extra["midRunSave"] = nil
        extra["carryLevel"] = nil
        extra["carryXp"] = nil
    }

    public var ngPlusCount: Int {
        if case .number(let n)? = extra["ngPlusCount"] { return Int(n) }
        return 0
    }

    /// Adds a death to the character's "deathLog", newest first, with the same
    /// fields as the web version's logDeath(); the last 5 are kept.
    public mutating func logDeath(floor: Int, killedBy: String, run: Run? = nil, date: Date = Date()) {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let flavor = [
            "Crypt of Malachar": "The Crypt is silent again. As if you were never there.",
            "The Ashbound Wastes": "The ash settles. The fire does not notice.",
            "Frosthold Abyss": "The cold closes over the gap you left. Perfectly.",
            "The Sunken Archives": "The water was always still. Now it is still again.",
            "Nightmare": "The nightmare continues. You simply stopped being in it.",
        ]
        let where_ = run?.dungeon ?? dungeon
        var o: [String: JSONValue] = [
            "floor": .number(Double(floor)),
            "killedBy": .string(killedBy),
            "date": .string("\(c.month ?? 1)/\(c.day ?? 1)/\(c.year ?? 2026)"),
            "time": .string("\(c.hour ?? 0):" + String(format: "%02d", c.minute ?? 0)),
            "dungeon": .string(where_),
            "diff": .string(run?.difficulty.rawValue ?? difficulty),
            "flavor": .string(flavor[where_] ?? "The dungeon continues without you."),
            "spirit": .string("None"),
            "bestDmg": .number(0),
        ]
        if let r = run {
            o["level"] = .number(Double(r.level))
            o["kills"] = .number(Double(r.kills))
            o["gold"] = .number(Double(r.gold))
            o["skillsUnlocked"] = .number(Double(r.unlockedSkills.count))
        }
        var log: [JSONValue] = []
        if case .array(let old)? = extra["deathLog"] { log = old }
        log.insert(.object(o), at: 0)
        extra["deathLog"] = .array(Array(log.prefix(5)))
    }

    /// The deaths in "deathLog", oldest last.
    public var deaths: [Death] {
        guard case .array(let entries)? = extra["deathLog"] else { return [] }
        return entries.compactMap { e in
            guard case .object(let o) = e else { return nil }
            func str(_ k: String) -> String { if case .string(let v)? = o[k] { return v }; if case .number(let n)? = o[k] { return String(Int(n)) }; return "" }
            func num(_ k: String) -> Int { if case .number(let n)? = o[k] { return Int(n) }; return jsParseInt(str(k)) ?? 0 }
            return Death(floor: num("floor"), killedBy: str("killedBy"), date: str("date"), dungeon: str("dungeon"),
                         diff: str("diff"), level: num("level"), kills: num("kills"), gold: num("gold"),
                         bestDmg: num("bestDmg"), flavor: str("flavor"))
        }
    }

    public struct Death: Equatable, Sendable {
        public var floor: Int
        public var killedBy: String
        public var date: String
        public var dungeon: String
        public var diff: String
        public var level: Int
        public var kills: Int
        public var gold: Int
        public var bestDmg: Int
        public var flavor: String
    }

    /// Endless best floor, " · ⬇ Floor 12 (Endless)" (getEndlessBestStr).
    public var endlessBestText: String {
        if case .number(let n)? = extra["endlessBest"], n >= 1 { return " · ⬇ Floor \(Int(n)) (Endless)" }
        return ""
    }

    public var spiritsEarned: Int {
        if case .array(let a)? = extra["earnedSpirits"] { return a.count }
        return 0
    }

    public var ngPlus: Bool {
        if case .bool(let b)? = extra["ngPlus"] { return b }
        return false
    }
}
