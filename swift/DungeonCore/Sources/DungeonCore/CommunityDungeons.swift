import Foundation

/// 12.1 COMMUNITY DUNGEONS: a player builds a dungeon on top of one of the
/// game's own (its rooms, loot and strength), names it, picks up to four
/// community enemies that roam it, one of them (or none) as the floor 10
/// boss, one special rule and its music. Others play it like a Challenge:
/// it never moves a character's own progress or unlocks dungeons.
///
/// Community enemies take the place of the dungeon's own enemies at the
/// same strength (only the name, look and story change), and the boss is
/// the base dungeon's boss under the chosen name, so a dungeon can't be
/// made trivially easy.
public enum CommunityDungeons {
    public struct Dungeon: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var desc: String
        public var creator: String
        /// The game dungeon it's built on.
        public var base: String
        /// Community enemy ids that roam it (up to `maxEnemies`).
        public var enemies: [String]
        /// A community enemy id for the floor 10 boss; nil keeps the base boss.
        public var boss: String?
        /// A run modifier id, always on in this dungeon; nil for none.
        public var rule: String?
        /// A music track name for its floors; nil keeps the base dungeon's.
        public var music: String?
        public var likes = 0
        public var plays = 0
        public var clears = 0
        public var createdAt: Double = 0
        public var approved = true

        public init(id: String, name: String, desc: String, creator: String, base: String,
                    enemies: [String], boss: String?, rule: String?, music: String?) {
            self.id = id; self.name = name; self.desc = desc; self.creator = creator; self.base = base
            self.enemies = enemies; self.boss = boss; self.rule = rule; self.music = music
        }

        /// What the list reads for it.
        public var summary: String {
            "\(name), by \(creator). Built on \(base). \(plays) play\(plays == 1 ? "" : "s"), \(clears) clear\(clears == 1 ? "" : "s"), \(likes) like\(likes == 1 ? "" : "s")."
        }
    }

    public static let maxEnemies = 4
    public static let nameLimit = 30
    public static let descLimit = 160
    /// How often a fight is one of its community enemies.
    public static let enemyShare = 0.45

    /// Name, description and creator checks (the same rules as enemies),
    /// plus the base dungeon and the enemy count.
    public static func problem(_ d: Dungeon, known: [String]) -> String? {
        if let p = CommunityEnemies.problem(name: d.name, desc: d.desc, creator: d.creator) { return p }
        if d.name.count > nameLimit { return "The name can be up to \(nameLimit) letters." }
        if d.desc.count > descLimit { return "The description can be up to \(descLimit) letters." }
        if !GameData.dungeons.contains(d.base) { return "Choose a dungeon to build on." }
        if d.enemies.count > maxEnemies { return "Choose up to \(maxEnemies) enemies." }
        if d.enemies.isEmpty { return "Choose at least one enemy to roam your dungeon." }
        if let b = d.boss, !known.contains(b) { return "Choose the boss from the enemies list." }
        if let r = d.rule, RunModifiers.modifier(r) == nil { return "Choose a rule from the list." }
        return nil
    }

    // MARK: In a run

    /// The run starts in the base dungeon with the rule on.
    public static func start(_ run: inout Run, _ d: Dungeon) {
        run.communityDungeon = d
        run.dungeon = d.base
    }

    /// The community enemies this dungeon uses that are still around
    /// (approved, not blocked: the app's loaded pool).
    static func roster(_ d: Dungeon) -> [CommunityEnemies.Entry] {
        d.enemies.compactMap { id in CommunityEnemies.pool.first { $0.id == id } }
    }

    /// A normal enemy of the base dungeon wearing a community enemy's name,
    /// look and story, in `enemyShare` of fights.
    static func dress(_ e: inout Enemy, for run: Run, dice: inout some Dice) {
        guard let d = run.communityDungeon else { return }
        let list = roster(d)
        guard !list.isEmpty, dice.chance(enemyShare) else { return }
        wear(&e, list[dice.roll(0...(list.count - 1))])
    }

    /// The base dungeon's boss as the chosen community enemy.
    static func dressBoss(_ b: inout Enemy, for run: Run) {
        guard let id = run.communityDungeon?.boss, let ce = CommunityEnemies.pool.first(where: { $0.id == id }) else { return }
        wear(&b, ce)
    }

    static func wear(_ e: inout Enemy, _ ce: CommunityEnemies.Entry) {
        e.name = ce.name
        e.icon = ce.icon.isEmpty ? "👤" : ce.icon
        e.desc = ce.desc
        e.mechanics["communityId"] = .string(ce.id)
        e.mechanics["creator"] = .string(ce.creator)
    }

    /// Its floors' music, when the creator chose one.
    public static func music(_ run: Run) -> String? { run.communityDungeon?.music }
}
