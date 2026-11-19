import Foundation

/// THE BATTLE PASS (12.0): an 8-week season of 50 tiers, earned by playing
/// (never bought). Everything you do gives Pass XP; five weekly quests give a
/// lot more; every 500 XP is a tier, and each tier's reward is paid as you
/// reach it. A new season starts every 8 weeks (from Monday 23 November 2026,
/// UTC) and the tiers start over. The web version (js/30-battle-pass.js)
/// follows the same rules and saves under the same keys, so the pass travels
/// with the cloud save.
public enum BattlePass {
    public static let tiers = 50
    public static let xpPerTier = 500
    public static let questXP = 250
    static let seasonDays = 56.0
    /// Monday 23 November 2026, 00:00 UTC.
    static let firstSeason: TimeInterval = 1_795_392_000

    // MARK: Seasons

    public struct Season: Equatable, Sendable {
        public let number: Int
        public let start: Date
        public let end: Date
        public var key: String { "dd_pass_s\(number)" }
        public func daysLeft(_ now: Date = Date()) -> Int { max(0, Int((end.timeIntervalSince(now) / 86400).rounded(.up))) }
    }

    public static func season(_ now: Date = Date()) -> Season {
        let span = seasonDays * 86400
        let n = max(0, Int(floor((now.timeIntervalSince1970 - firstSeason) / span)))
        let start = Date(timeIntervalSince1970: firstSeason + Double(n) * span)
        return Season(number: n + 1, start: start, end: start.addingTimeInterval(span))
    }

    // MARK: What earns XP

    public enum Event: Equatable, Sendable {
        case kill(elite: Bool, boss: Bool)
        case floor
        case dungeonCleared
        case worldBossStrike
        case weeklyLadderRun
        case endlessFloor
        case spireFloor
        case dailyQuest
    }

    public static func xp(_ e: Event) -> Int {
        switch e {
        case .kill(_, let boss) where boss: return 60
        case .kill(let elite, _): return elite ? 15 : 5
        case .floor: return 10
        case .dungeonCleared: return 150
        case .worldBossStrike: return 10
        case .weeklyLadderRun: return 100
        case .endlessFloor: return 2
        case .spireFloor: return 5
        case .dailyQuest: return 50
        }
    }

    // MARK: Weekly quests

    public struct Quest: Equatable, Sendable {
        public let id: String
        public let text: String
        public let target: Int
        /// The event that moves it on.
        func counts(_ e: Event) -> Bool {
            switch (id, e) {
            case ("kills", .kill): return true
            case ("elites", .kill(let elite, _)): return elite
            case ("bosses", .kill(_, let boss)): return boss
            case ("floors", .floor): return true
            case ("clears", .dungeonCleared): return true
            case ("worldboss", .worldBossStrike): return true
            case ("weekly", .weeklyLadderRun): return true
            case ("endless", .endlessFloor): return true
            case ("spire", .spireFloor): return true
            default: return false
            }
        }
    }

    public static let questPool: [Quest] = [
        Quest(id: "kills", text: "Defeat 60 enemies", target: 60),
        Quest(id: "elites", text: "Defeat 8 elite enemies", target: 8),
        Quest(id: "bosses", text: "Defeat 3 bosses", target: 3),
        Quest(id: "floors", text: "Reach 25 new floors in dungeon runs", target: 25),
        Quest(id: "clears", text: "Clear 2 dungeons", target: 2),
        Quest(id: "worldboss", text: "Strike the World Boss 15 times", target: 15),
        Quest(id: "weekly", text: "Finish a Weekly Ladder run", target: 1),
        Quest(id: "endless", text: "Descend 50 floors in Endless Descent", target: 50),
        Quest(id: "spire", text: "Climb 15 floors of The Spire", target: 15),
    ]

    /// This ISO week's five quests, the same for every player.
    public static func quests(_ now: Date = Date()) -> (week: String, quests: [Quest]) {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let y = c.yearForWeekOfYear ?? 2026, w = c.weekOfYear ?? 1
        var pool = questPool, picked: [Quest] = []
        var s = y * 100 + w + 9_000_000
        while picked.count < 5 && !pool.isEmpty {
            let i = Int(Challenges.seeded(s) * Double(pool.count)) % pool.count
            picked.append(pool.remove(at: i))
            s += 1
        }
        return (String(format: "%d-W%02d", y, w), picked)
    }

    // MARK: Rewards

    public enum Reward: Equatable, Sendable {
        case gold(Int)
        case coinsAndFragments(coins: Int, fragments: Int)
        case title(String)

        public var text: String {
            switch self {
            case .gold(let g): return "\(g) gold"
            case .coinsAndFragments(let c, let f): return "\(c) Mystery Coins and \(f) Soul Fragments"
            case .title(let t): return "the title \(t)"
            }
        }
    }

    /// Every 5th tier: Mystery Coins and Soul Fragments; tier 25 and 50: a
    /// title (with the coins); the rest: gold, more the higher you go.
    public static func reward(tier t: Int, season: Int) -> [Reward] {
        switch t {
        case 50: return [.title("S\(season)Legend"), .coinsAndFragments(coins: 10, fragments: 5)]
        case 25: return [.title("S\(season)Veteran"), .coinsAndFragments(coins: 5, fragments: 3)]
        case _ where t % 5 == 0: return [.coinsAndFragments(coins: 3, fragments: 2)]
        default: return [.gold(150 + 25 * t)]
        }
    }

    // MARK: Progress

    public struct Progress: Codable, Equatable, Sendable {
        public var xp = 0
        /// Tiers already paid.
        public var paid = 0
        public var week = ""
        public var quest: [String: Int] = [:]
        public var questsDone: [String] = []
        public init() {}
        public var tier: Int { min(BattlePass.tiers, xp / BattlePass.xpPerTier) }
        public var xpIntoTier: Int { tier >= BattlePass.tiers ? BattlePass.xpPerTier : xp % BattlePass.xpPerTier }
    }

    public static func load(_ store: GameStore, now: Date = Date()) -> Progress {
        let s = season(now)
        var p = Progress()
        if let raw = store.getItem(s.key), let d = raw.data(using: .utf8),
           let v = try? JSONDecoder().decode(Progress.self, from: d) { p = v }
        let wk = quests(now).week
        if p.week != wk { p.week = wk; p.quest = [:]; p.questsDone = [] }
        return p
    }

    static func save(_ p: Progress, _ store: GameStore, now: Date) {
        if let d = try? JSONEncoder().encode(p), let s = String(data: d, encoding: .utf8) {
            store.setItem(season(now).key, s)
        }
    }

    /// What one event earned: the lines to show and say (quest done, new tier).
    public struct Outcome: Equatable, Sendable {
        public var xp = 0
        public var lines: [String] = []
        public var newTier = false
        public var questDone = false
        public init() {}
    }

    /// Records something that happened: Pass XP, quest progress and any
    /// tier rewards, paid into the store.
    @discardableResult
    public static func record(_ e: Event, store: GameStore, now: Date = Date()) -> Outcome {
        var p = load(store, now: now)
        var out = Outcome()
        var gained = xp(e)
        for q in quests(now).quests where q.counts(e) && !p.questsDone.contains(q.id) {
            let v = (p.quest[q.id] ?? 0) + 1
            p.quest[q.id] = v
            if v >= q.target {
                p.questsDone.append(q.id)
                gained += questXP
                out.questDone = true
                out.lines.append("📜 Weekly quest complete: \(q.text)! +\(questXP) Pass XP.")
            }
        }
        p.xp += gained
        out.xp = gained
        let s = season(now).number
        while p.paid < p.tier {
            p.paid += 1
            let rewards = reward(tier: p.paid, season: s)
            for r in rewards { pay(r, store: store) }
            out.newTier = true
            out.lines.append("🏆 Battle Pass tier \(p.paid)! You earn " + rewards.map(\.text).joined(separator: " and ") + ".")
        }
        save(p, store, now: now)
        return out
    }

    static func pay(_ r: Reward, store: GameStore) {
        switch r {
        case .gold(let g):
            Wallet(store: store).addGold(g)
        case .coinsAndFragments(let c, let f):
            Spire.addCoins(c, store: store)
            store.setItem("dd_soul_fragments", String(CustomSpirits.fragments(store) + f))
        case .title(let t):
            var titles: [String] = []
            if let s = store.getItem("dd_unlocked_titles"), let d = s.data(using: .utf8),
               let v = try? JSONDecoder().decode([String].self, from: d) { titles = v }
            if !titles.contains(t) { titles.append(t) }
            if let d = try? JSONEncoder().encode(titles), let s = String(data: d, encoding: .utf8) {
                store.setItem("dd_unlocked_titles", s)
            }
        }
    }

    /// "Season 1, tier 12 of 50: 300 of 500 XP to the next. 41 days left."
    public static func status(_ store: GameStore, now: Date = Date()) -> String {
        let s = season(now), p = load(store, now: now)
        let next = p.tier >= tiers ? "Every tier is yours." : "\(p.xpIntoTier) of \(xpPerTier) XP to the next."
        return "Season \(s.number), tier \(p.tier) of \(tiers). \(next) \(s.daysLeft(now)) days left."
    }
}
