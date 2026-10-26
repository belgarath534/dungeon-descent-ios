import Foundation

/// An achievement from the web version's ACHIEVEMENTS list, with its check turned
/// into data by extract-game-data.js.
public struct Achievement: Decodable, Sendable, Identifiable {
    public struct Condition: Decodable, Sendable {
        var stat: String?
        var key: String?
        var listKey: String?
        var equalsKey: String?
        var value: String?
        var gold: Int?
        var trophies: Int?
        var min: Double?
    }

    public let id: String
    public let name: String
    public let icon: String
    public let desc: String
    public let hint: String
    public let gold: Int
    public let trophies: Int
    /// Game Center achievement ID ("DD_FIRST_BLOOD"), when there is one.
    public let gcId: String?
    let condition: Condition
}

/// What happened in the game, for achievements and stats.
public enum GameEvent: Sendable {
    case enemyKilled(Enemy, run: Run)
    case levelReached(Int)
    case floorReached(Int)
    case floorCleared(tookNoDamage: Bool)
    case runWon(Run, diedThisRun: Bool, seconds: TimeInterval)
    case died
    case julioMet
    case elixirUsed
    case dailyQuestCompleted
}

/// Achievements, trophies and lifetime stats, saved under the web version's keys
/// ("dd_ach_stats", "dd_achievements", "dd_trophies", "dd_global_stats").
public final class AchievementBook {
    private let store: GameStore
    private let wallet: Wallet
    /// Called with achievements as they unlock (for the popup and Game Center).
    public var onUnlock: ([Achievement]) -> Void = { _ in }

    public init(store: GameStore, wallet: Wallet) {
        self.store = store
        self.wallet = wallet
    }

    public static var all: [Achievement] { GameContent.shared.achievements }

    // MARK: Saved state

    // Stats and unlocks are read from the save once and kept in memory; every
    // change is written straight back.
    private lazy var statsCache: [String: JSONValue] = decode("dd_ach_stats") ?? [:]
    private lazy var unlockedCache: [String] = decode("dd_achievements") ?? []

    public var stats: [String: JSONValue] {
        get { statsCache }
        set { statsCache = newValue; encode(newValue, "dd_ach_stats") }
    }

    public var unlockedIDs: [String] {
        get { unlockedCache }
        set { unlockedCache = newValue; encode(newValue, "dd_achievements") }
    }

    /// Re-reads stats and unlocks from the save (after importing one).
    public func reload() {
        statsCache = decode("dd_ach_stats") ?? [:]
        unlockedCache = decode("dd_achievements") ?? []
    }

    private var rewardedIDs: [String] {
        get { decode("dd_ach_rewarded") ?? [] }
        set { encode(newValue, "dd_ach_rewarded") }
    }

    public var trophies: Int { jsParseInt(store.getItem("dd_trophies")) ?? 0 }

    public var globalStats: [String: JSONValue] {
        get { decode("dd_global_stats") ?? [:] }
        set { encode(newValue, "dd_global_stats") }
    }

    public func stat(_ key: String) -> Double {
        switch stats[key] {
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        default: return 0
        }
    }

    // MARK: Updating

    public func increment(_ key: String, by n: Double = 1) {
        var s = stats
        s[key] = .number(stat(key) + n)
        stats = s
    }

    public func setMax(_ key: String, _ value: Double) {
        guard value > stat(key) else { return }
        var s = stats
        s[key] = .number(value)
        stats = s
    }

    /// Sets a once-only flag. Returns true the first time.
    @discardableResult
    public func markOnce(_ key: String) -> Bool {
        if stats[key] == .bool(true) { return false }
        var s = stats
        s[key] = .bool(true)
        stats = s
        return true
    }

    /// setGlobalStatMax: keeps the highest value seen.
    public func setGlobalMax(_ key: String, _ value: Double) {
        var g = globalStats
        if case .number(let n)? = g[key], n >= value { return }
        g[key] = .number(value)
        globalStats = g
    }

    public func trackGlobal(_ key: String, _ amount: Double = 1) {
        var g = globalStats
        if case .number(let n)? = g[key] { g[key] = .number(n + amount) } else { g[key] = .number(amount) }
        globalStats = g
    }

    /// Records what happened, updates stats the way the web version does, and
    /// unlocks whatever is now earned.
    public func record(_ event: GameEvent) {
        switch event {
        case .enemyKilled(let e, let run):
            // The web version added 2 per kill (incrementAchievementStat ran twice).
            increment("totalKills")
            trackGlobal("totalKills")
            if e.isElite { increment("eliteKills"); trackGlobal("eliteKills") }
            setMax("bestGoldRun", Double(run.gold))
            setMax("maxFloorReached", Double(run.floor))
            if e.isBoss {
                if markOnce("boss_" + e.name.split(separator: " ").joined(separator: "_")) { increment("uniqueBossKills") }
                if run.difficulty == .nightmare { increment("nightmareBossKills") }
            }
        case .levelReached(let level):
            setMax("maxLevel", Double(level))
        case .floorReached(let floor):
            setMax("maxFloorReached", Double(floor))
            trackGlobal("totalFloors")
        case .floorCleared(let clean):
            if clean { increment("noDmgFloors") }
        case .runWon(let run, let died, let seconds):
            increment("dungeonsComplete")
            trackGlobal("runsCompleted")
            switch run.difficulty {
            case .ironblood: increment("ironbloodWins")
            case .condemned: increment("condemnedWins")
            case .forsaken: increment("forsakenWins")
            case .nightmare: increment("nightmareWins")
            default: break
            }
            let completeKey: [String: String] = [
                "Crypt of Malachar": "cryptComplete", "The Ashbound Wastes": "ashboundComplete",
                "Frosthold Abyss": "frostholdComplete", "The Sunken Archives": "sunkenComplete",
                "The Hollow": "hollowComplete", "The Whispering Forest": "whisperComplete",
                "The Infernal Descent": "infernalComplete", "The Abyssal Deep": "abyssalComplete",
            ]
            if let k = completeKey[run.dungeon] { increment(k) }
            if run.dungeon == "The Abyssal Deep" {
                markOnce("abyssalBossDefeated")
                if run.hardcore { markOnce("abyssalHardcoreWin") }
            }
            if run.ngPlus {
                increment("ngPlusComplete")
                setMax("ngPlusMaxCount", Double(run.ngPlusCount ?? 1))
            }
            if !died { increment("flawlessRuns") }
            if seconds < 600 { increment("speedRuns") }
            var won: [String] = decode("dd_won_classes") ?? []
            if !won.contains(run.cls) {
                won.append(run.cls)
                encode(won, "dd_won_classes")
                setMax("uniqueClassesWon", Double(won.count))
            }
        case .died:
            increment("totalDeaths")
            trackGlobal("totalDeaths")
        case .julioMet:
            increment("julioFound")
        case .elixirUsed:
            increment("elixirsUsed")
        case .dailyQuestCompleted:
            increment("dailyQuestsComplete")
        }
        check()
    }

    /// Unlocks every achievement whose condition is now met, paying its gold and trophies.
    @discardableResult
    public func check() -> [Achievement] {
        var unlocked = unlockedIDs
        let have = Set(unlocked)
        let fresh = Self.all.filter { !have.contains($0.id) && isMet($0) }
        guard !fresh.isEmpty else { return [] }
        unlocked += fresh.map(\.id)
        unlockedIDs = unlocked
        reward(fresh)
        onUnlock(fresh)
        return fresh
    }

    /// Unlocks one achievement directly (the web version's awardAchievement).
    public func award(_ id: String) {
        guard !unlockedIDs.contains(id), let a = Self.all.first(where: { $0.id == id }) else { return }
        unlockedIDs = unlockedIDs + [id]
        reward([a])
        onUnlock([a])
    }

    /// Pays out achievements unlocked without their reward, such as ones in an
    /// imported web save (retroactiveAchievementRewards).
    public func payOutstandingRewards() {
        let owed = Self.all.filter { unlockedIDs.contains($0.id) && !rewardedIDs.contains($0.id) }
        reward(owed)
    }

    private func reward(_ list: [Achievement]) {
        var rewarded = rewardedIDs
        let due = list.filter { !rewarded.contains($0.id) }
        guard !due.isEmpty else { return }
        rewarded += due.map(\.id)
        rewardedIDs = rewarded
        store.setItem("dd_trophies", String(trophies + due.reduce(0) { $0 + $1.trophies }))
        wallet.addGold(due.reduce(0) { $0 + $1.gold })
    }

    func isMet(_ a: Achievement) -> Bool {
        let c = a.condition
        let min = c.min ?? 1
        if let s = c.stat { return stat(s) >= min }
        if let k = c.key { return Double(jsParseInt(store.getItem(k)) ?? 0) >= min }
        if let k = c.listKey {
            let list: [JSONValue] = decode(k) ?? []
            return Double(list.count) >= min
        }
        if let k = c.equalsKey { return store.getItem(k) == c.value }
        if let g = c.gold { return wallet.gold >= g }
        if let t = c.trophies { return trophies >= t }
        return false
    }

    // MARK: JSON helpers

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let s = store.getItem(key), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        if let d = try? JSONEncoder().encode(value), let s = String(data: d, encoding: .utf8) { store.setItem(key, s) }
    }
}
