import Foundation

/// The Community Enemy Creator (EC_STAT_RANGES, ecRollStats, ecSubmit,
/// getCommunityEnemy, communityEnemyToFightData): players build an enemy,
/// it joins the shared "community_enemies" pool, and 12% of ordinary rooms
/// bring one out, announced with its creator's name.
public enum CommunityEnemies {
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case common, uncommon, rare, elite, boss

        public var label: String {
            switch self {
            case .common: return "Common Enemy — floors 1-5, low stats"
            case .uncommon: return "Uncommon Enemy — floors 3-7, medium stats"
            case .rare: return "Rare Enemy — floors 6-9, high stats"
            case .elite: return "Elite Enemy — floor 10 guardian, boss-tier stats"
            case .boss: return "Boss — can replace the dungeon boss"
            }
        }

        var ranges: (hp: ClosedRange<Int>, atk: ClosedRange<Int>, def: ClosedRange<Int>) {
            switch self {
            case .common: return (20...60, 3...8, 0...2)
            case .uncommon: return (50...110, 7...15, 1...4)
            case .rare: return (90...180, 13...24, 3...7)
            case .elite: return (160...300, 20...38, 5...12)
            case .boss: return (280...600, 30...55, 8...18)
            }
        }

        public var icon: String {
            switch self {
            case .common: return "👤"
            case .uncommon: return "⚠️"
            case .rare, .boss: return "💀"
            case .elite: return "👁️"
            }
        }
    }

    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var desc: String
        public var type: String
        /// A dungeon's name, or "all".
        public var dungeon: String
        public var music: String?
        public var creator: String
        public var icon: String
        public var hp: Int
        public var atk: Int
        public var def: Int
        public var kills: Int

        public init(id: String = "", name: String, desc: String, type: String, dungeon: String, music: String?,
                    creator: String, icon: String, hp: Int, atk: Int, def: Int, kills: Int = 0) {
            self.id = id; self.name = name; self.desc = desc; self.type = type; self.dungeon = dungeon
            self.music = music; self.creator = creator; self.icon = icon; self.hp = hp; self.atk = atk; self.def = def
            self.kills = kills
        }
    }

    /// The dungeons a creator can pick (the Shadow World is left out, as on the web).
    public static let dungeons = ["all"] + GameData.dungeons.filter { $0 != "The Shadow World" }

    /// ecRollStats.
    public static func roll(_ kind: Kind, dice: inout some Dice) -> (hp: Int, atk: Int, def: Int) {
        let r = kind.ranges
        return (dice.roll(r.hp), dice.roll(r.atk), dice.roll(r.def))
    }

    static let badWords: Set<String> = ["fuck", "shit", "ass", "bitch", "cunt", "dick", "cock", "pussy", "nigger", "nigga", "faggot",
                                        "fag", "retard", "whore", "slut", "bastard", "damn", "hell", "piss", "crap", "asshole",
                                        "motherfucker", "bullshit"]

    /// ecContainsBadWord, by whole word. (The web version also matched inside
    /// words, so "Hellhound", "Shellback" and "Assassin" were refused.)
    public static func hasBadWord(_ text: String) -> Bool {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.contains { badWords.contains(String($0)) }
    }

    /// ecSubmit's checks: the problem, or nil.
    public static func problem(name: String, desc: String, creator: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines), d = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = creator.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return "Please give your enemy a name." }
        if d.isEmpty { return "Please add a description." }
        if c.isEmpty { return "Please enter your creator name." }
        if n.count < 2 { return "Enemy name is too short." }
        if c.count < 2 { return "Creator name is too short." }
        if hasBadWord(n) || hasBadWord(d) || hasBadWord(c) { return "Your submission contains inappropriate content. Please revise and try again." }
        return nil
    }

    /// The pool the dungeon draws from: loaded by the app, with blocked
    /// creators and hidden enemies already left out.
    nonisolated(unsafe) public static var pool: [Entry] = []

    /// getCommunityEnemy: 12% of ordinary rooms.
    static func spawn(for run: Run, dice: inout some Dice) -> Enemy? {
        let eligible = pool.filter { $0.dungeon == "all" || $0.dungeon == run.dungeon }
        guard !eligible.isEmpty, dice.chance(0.12) else { return nil }
        return fight(eligible[dice.roll(0...(eligible.count - 1))])
    }

    /// communityEnemyToFightData.
    public static func fight(_ ce: Entry) -> Enemy {
        let hp = max(1, ce.hp)
        let lo = max(1, Int(Double(ce.atk) * 0.8)), hi = Int(Double(ce.atk) * 1.2)
        var e = Enemy(name: ce.name, icon: ce.icon.isEmpty ? "👤" : ce.icon, hp: hp, maxHp: hp, atk: lo...max(lo, hi),
                      gold: (hp / 4)...(hp / 4))
        e.desc = ce.desc
        e.mechanics["communityId"] = .string(ce.id)
        e.mechanics["creator"] = .string(ce.creator)
        if let m = ce.music, !m.isEmpty { e.mechanics["music"] = .string(m) }
        return e
    }

    public static func id(_ e: Enemy) -> String? {
        if case .string(let s)? = e.mechanics["communityId"], !s.isEmpty { return s }
        return nil
    }

    /// "A creature stirs — X, unleashed by Y."
    public static func announcement(_ e: Enemy) -> String? {
        guard e.mechanics["communityId"] != nil, case .string(let c)? = e.mechanics["creator"] else { return nil }
        return "A creature stirs — \(e.name), unleashed by \(c)."
    }

    public static func music(_ e: Enemy) -> String? {
        if case .string(let m)? = e.mechanics["music"] { return m }
        return nil
    }
}
