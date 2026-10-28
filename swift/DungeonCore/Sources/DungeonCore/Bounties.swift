import Foundation

/// THE BOUNTY BOARD: three bounties a day (five refreshes), one active at a
/// time, paid in gold and trophies when done. Saved in "dd_bounty_data" in the
/// web version's shape, so a web save carries over.
public enum Bounties {
    public enum Kind: String, Sendable { case killType = "kill_type", killElite = "kill_elite", killBoss = "kill_boss", reachFloor = "reach_floor", killCount = "kill_count" }

    public struct Bounty: Sendable, Equatable, Identifiable {
        public let id, title, desc, dungeon: String
        public let kind: Kind
        public let target: String?
        public let count, gold, trophies: Int
        public let icon: String

        /// getBountyProgressLabel
        public var progressLabel: String {
            switch kind {
            case .killType: return "\(target ?? "")s killed"
            case .killElite: return "elite enemies defeated"
            case .killBoss: return "bosses defeated"
            case .reachFloor: return "floors reached"
            case .killCount: return "enemies killed"
            }
        }

        var anyDungeon: Bool { dungeon == "Any dungeon" }
    }

    private static func b(_ id: String, _ title: String, _ desc: String, _ dungeon: String, _ kind: Kind,
                          _ target: String? = nil, _ count: Int, _ gold: Int, _ trophies: Int, _ icon: String) -> Bounty {
        Bounty(id: id, title: title, desc: desc, dungeon: dungeon, kind: kind, target: target, count: count, gold: gold, trophies: trophies, icon: icon)
    }

    /// BOUNTY_TEMPLATES
    public static let all: [Bounty] = [
        b("kill-crypt-shades", "Shade Purge", "Slay 5 Hollow Shades in The Crypt.", "Crypt of Malachar", .killType, "Hollow Shade", 5, 150, 1, "💀"),
        b("kill-crypt-wraiths", "Wraith Hunter", "Slay 3 Wailing Wraiths in The Crypt.", "Crypt of Malachar", .killType, "Wailing Wraith", 3, 200, 1, "👻"),
        b("kill-crypt-skeletons", "Bone Collector", "Slay 5 Brittle Skeletons in The Crypt.", "Crypt of Malachar", .killType, "Brittle Skeleton", 5, 150, 1, "🦴"),
        b("kill-ash-wraiths", "Cinder Wraith Hunt", "Slay 4 Cinder Wraiths in the Ashbound Wastes.", "The Ashbound Wastes", .killType, "Cinder Wraith", 4, 200, 1, "🔥"),
        b("kill-ash-husks", "Scorched Remains", "Slay 5 Scorched Husks in the Ashbound Wastes.", "The Ashbound Wastes", .killType, "Scorched Husk", 5, 175, 1, "🔥"),
        b("kill-frost-shades", "Frost Shade Slayer", "Slay 4 Frost Shades in Frosthold.", "Frosthold Abyss", .killType, "Frost Shade", 4, 175, 1, "❄️"),
        b("kill-frost-wraiths", "Blizzard Hunter", "Slay 3 Blizzard Wraiths in Frosthold.", "Frosthold Abyss", .killType, "Blizzard Wraith", 3, 200, 1, "❄️"),
        b("kill-sunken-archivists", "The Drowned", "Slay 4 Drowned Archivists in the Sunken Archives.", "The Sunken Archives", .killType, "Drowned Archivist", 4, 200, 1, "💧"),
        b("kill-sunken-ink", "Ink Purge", "Slay 3 Ink Wraiths in the Sunken Archives.", "The Sunken Archives", .killType, "Ink Wraith", 3, 225, 1, "💧"),
        b("kill-hollow-bride", "The Hollow Bride", "Slay 3 Hollow Brides in The Hollow.", "The Hollow", .killType, "Hollow Bride", 3, 250, 2, "🕯️"),
        b("kill-hollow-portraits", "Burn the Portraits", "Slay 4 Portraits in The Hollow.", "The Hollow", .killType, "The Portrait", 4, 200, 1, "🕯️"),
        b("kill-whisper-wolves", "Cursed Wolf Pack", "Slay 4 Cursed Wolves in the Whispering Forest.", "The Whispering Forest", .killType, "Cursed Wolf", 4, 225, 1, "🌲"),
        b("kill-whisper-roots", "Root Purge", "Slay 5 Root Crawlers in the Whispering Forest.", "The Whispering Forest", .killType, "Root Crawler", 5, 175, 1, "🌲"),
        b("kill-infernal-wisps", "Void Wisp Purge", "Slay 5 Void Wisps in The Infernal Descent.", "The Infernal Descent", .killType, "Void Wisp", 5, 275, 2, "😈"),
        b("kill-infernal-wraiths", "Void Wraith Hunter", "Slay 3 Void Wraiths in The Infernal Descent.", "The Infernal Descent", .killType, "Void Wraith", 3, 300, 2, "😈"),
        b("kill-abyssal-eels", "Eel Hunter", "Slay 3 Abyssal Eels in The Abyssal Deep.", "The Abyssal Deep", .killType, "Abyssal Eel", 3, 250, 2, "🌊"),
        b("kill-abyssal-tide", "Tide Wraith Slayer", "Slay 4 Tide Wraiths in The Abyssal Deep.", "The Abyssal Deep", .killType, "Tide Wraith", 4, 225, 2, "🌊"),

        b("elite-crypt", "Elite Hunter", "Defeat an Elite enemy in The Crypt.", "Crypt of Malachar", .killElite, nil, 1, 300, 2, "★"),
        b("elite-ash", "Ashbound Champion", "Defeat an Elite enemy in the Ashbound Wastes.", "The Ashbound Wastes", .killElite, nil, 1, 350, 2, "★"),
        b("elite-frost", "Frost Giant", "Defeat an Elite enemy in Frosthold.", "Frosthold Abyss", .killElite, nil, 1, 350, 2, "★"),
        b("elite-abyssal", "Deep Terror", "Defeat an Elite enemy in The Abyssal Deep.", "The Abyssal Deep", .killElite, nil, 1, 500, 3, "★"),
        b("elite-infernal", "Infernal Champion", "Defeat an Elite enemy in The Infernal Descent.", "The Infernal Descent", .killElite, nil, 1, 500, 3, "★"),

        b("boss-crypt", "Crypt Cleansed", "Defeat the boss of The Crypt.", "Crypt of Malachar", .killBoss, nil, 1, 400, 3, "👑"),
        b("boss-ash", "Ash Lord Slain", "Defeat the boss of the Ashbound Wastes.", "The Ashbound Wastes", .killBoss, nil, 1, 450, 3, "👑"),
        b("boss-frost", "Winter Ended", "Defeat the boss of Frosthold.", "Frosthold Abyss", .killBoss, nil, 1, 450, 3, "👑"),
        b("boss-sunken", "Archives Sealed", "Defeat the boss of the Sunken Archives.", "The Sunken Archives", .killBoss, nil, 1, 500, 3, "👑"),
        b("boss-hollow", "Darkness Purged", "Defeat the boss of The Hollow.", "The Hollow", .killBoss, nil, 1, 500, 3, "👑"),
        b("boss-infernal", "Infernal Sealed", "Defeat the boss of The Infernal Descent.", "The Infernal Descent", .killBoss, nil, 1, 700, 5, "👑"),
        b("boss-abyssal", "The Deep Calmed", "Defeat the boss of The Abyssal Deep.", "The Abyssal Deep", .killBoss, nil, 1, 700, 5, "👑"),

        b("floor-5-any", "Halfway There", "Reach floor 5 in any dungeon without dying.", "Any dungeon", .reachFloor, nil, 5, 200, 1, "🗺️"),
        b("floor-8-any", "The Long Road", "Reach floor 8 in any dungeon without dying.", "Any dungeon", .reachFloor, nil, 8, 350, 2, "🗺️"),
        b("floor-10-any", "Full Clear", "Reach floor 10 in any dungeon without dying.", "Any dungeon", .reachFloor, nil, 10, 500, 3, "🗺️"),

        b("kills-10-any", "Blood and Gold", "Defeat 10 enemies in a single run.", "Any dungeon", .killCount, nil, 10, 150, 1, "⚔️"),
        b("kills-20-any", "Relentless", "Defeat 20 enemies in a single run.", "Any dungeon", .killCount, nil, 20, 250, 2, "⚔️"),
        b("kills-30-any", "Slaughter", "Defeat 30 enemies in a single run.", "Any dungeon", .killCount, nil, 30, 400, 3, "⚔️"),
    ]

    public static func bounty(_ id: String) -> Bounty? { all.first { $0.id == id } }

    public static let refreshesPerDay = 5

    /// new Date().toDateString(), e.g. "Wed Oct 28 2026", the web version's day key.
    public static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM dd yyyy"
        return f.string(from: date)
    }

    // MARK: Saved data

    private static let key = "dd_bounty_data"

    private static func load(_ store: GameStore) -> [String: JSONValue] {
        guard let s = store.getItem(key), let d = s.data(using: .utf8),
              case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: d) else { return [:] }
        return o
    }

    private static func save(_ o: [String: JSONValue], _ store: GameStore) {
        if let d = try? JSONEncoder().encode(JSONValue.object(o)), let s = String(data: d, encoding: .utf8) { store.setItem(key, s) }
    }

    private static func strings(_ v: JSONValue?) -> [String] {
        guard case .array(let a)? = v else { return [] }
        return a.compactMap { if case .string(let s) = $0 { return s }; return nil }
    }

    private static func int(_ v: JSONValue?) -> Int? { if case .number(let n)? = v { return Int(n) }; return nil }

    /// The active bounty: the web version saved the whole template; its id is enough.
    public static func active(_ store: GameStore) -> Bounty? {
        guard case .object(let o)? = load(store)["activeBounty"], case .string(let id)? = o["id"] else { return nil }
        return bounty(id)
    }

    public static func progress(_ store: GameStore) -> Int { int(load(store)["bountyProgress"]) ?? 0 }

    /// getBountyRefreshes
    public static func refreshesLeft(_ store: GameStore, now: Date = Date()) -> Int {
        let d = load(store)
        guard d["refreshDate"] == .string(dayKey(now)) else { return refreshesPerDay }
        return int(d["refreshesLeft"]) ?? refreshesPerDay
    }

    /// generateBounties: three not active and not already done (all of them
    /// again once fewer than three are left).
    static func generate(_ d: [String: JSONValue], dice: inout some Dice) -> [String] {
        let activeID: String? = { if case .object(let o)? = d["activeBounty"], case .string(let s)? = o["id"] { return s }; return nil }()
        let done = Set(strings(d["completedBounties"]))
        var pool = all.filter { $0.id != activeID && !done.contains($0.id) }
        if pool.count < 3 { pool = all }
        var picked: [String] = []
        while picked.count < 3 && !pool.isEmpty { picked.append(pool.remove(at: dice.roll(0...(pool.count - 1))).id) }
        return picked
    }

    /// renderBountyBoard: today's three, made fresh each day.
    public static func today(_ store: GameStore, now: Date = Date(), dice: inout some Dice) -> [Bounty] {
        var d = load(store)
        let day = dayKey(now)
        if d["bountyDate"] != .string(day) || d["todayBounties"] == nil {
            d["todayBounties"] = .array(generate(d, dice: &dice).map { .string($0) })
            d["bountyDate"] = .string(day)
            save(d, store)
        }
        return strings(d["todayBounties"]).compactMap(bounty)
    }

    /// refreshBounties
    public static func refresh(_ store: GameStore, now: Date = Date(), dice: inout some Dice) -> Bool {
        let left = refreshesLeft(store, now: now)
        guard left > 0 else { return false }
        var d = load(store)
        d["refreshDate"] = .string(dayKey(now))
        d["refreshesLeft"] = .number(Double(left - 1))
        d["todayBounties"] = .array(generate(d, dice: &dice).map { .string($0) })
        d["bountyDate"] = .string(dayKey(now))
        save(d, store)
        return true
    }

    /// registerBounty
    public static func register(_ id: String, store: GameStore) -> Bounty? {
        guard let b = bounty(id), active(store) == nil else { return nil }
        var d = load(store)
        d["activeBounty"] = .object([
            "id": .string(b.id), "title": .string(b.title), "desc": .string(b.desc), "dungeon": .string(b.dungeon),
            "type": .string(b.kind.rawValue), "target": b.target.map { .string($0) } ?? .null,
            "count": .number(Double(b.count)), "gold": .number(Double(b.gold)),
            "trophies": .number(Double(b.trophies)), "icon": .string(b.icon),
        ])
        d["bountyProgress"] = .number(0)
        d["bountyRunKills"] = .number(0)
        save(d, store)
        return b
    }

    /// abandonBounty
    public static func abandon(_ store: GameStore) {
        var d = load(store)
        d["activeBounty"] = .null
        d["bountyProgress"] = .number(0)
        save(d, store)
    }

    // MARK: Progress

    public enum Event: Sendable {
        /// A new run began: "in a single run" counts start again.
        case runStarted
        case kill(name: String, elite: Bool, boss: Bool, dungeon: String)
        case floor(Int, dungeon: String, diedThisRun: Bool)
    }

    /// updateBountyProgress. Returns the bounty when this finished it; the
    /// caller pays it with `complete`.
    public static func record(_ e: Event, store: GameStore) -> Bounty? {
        guard let b = active(store) else { return nil }
        var d = load(store)
        var p = int(d["bountyProgress"]) ?? 0
        let before = p
        func here(_ dungeon: String) -> Bool { b.anyDungeon || dungeon == b.dungeon }
        switch e {
        case .runStarted:
            if b.kind == .killCount { p = 0 }
        case .kill(let name, let elite, let boss, let dungeon):
            switch b.kind {
            case .killCount: p += 1
            case .killType:
                if here(dungeon), let t = b.target, name.lowercased().contains(t.lowercased()) { p += 1 }
            case .killElite: if elite && here(dungeon) { p += 1 }
            case .killBoss: if boss && here(dungeon) { p += 1 }
            case .reachFloor: break
            }
        case .floor(let n, let dungeon, let died):
            if b.kind == .reachFloor && n >= b.count && !died && here(dungeon) { p = b.count }
        }
        guard p != before else { return nil }
        d["bountyProgress"] = .number(Double(p))
        save(d, store)
        return p >= b.count ? b : nil
    }

    /// completeBounty: gold and trophies, and it won't be offered again until
    /// the list runs short.
    public static func complete(_ b: Bounty, store: GameStore, wallet: Wallet) {
        wallet.addGold(b.gold)
        store.setItem("dd_trophies", String((jsParseInt(store.getItem("dd_trophies")) ?? 0) + b.trophies))
        var d = load(store)
        d["completedBounties"] = .array((strings(d["completedBounties"]) + [b.id]).map { .string($0) })
        d["activeBounty"] = .null
        d["bountyProgress"] = .number(0)
        d["bountyComplete"] = .bool(false)
        save(d, store)
    }

    /// The dungeon banner (updateDungeonBountyBanner).
    public static func banner(_ store: GameStore) -> String? {
        guard let b = active(store) else { return nil }
        return "📋 \(b.title): \(progress(store))/\(b.count) \(b.progressLabel)"
    }
}
