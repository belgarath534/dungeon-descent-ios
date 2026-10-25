import Foundation

/// A daily quest from the web version's DAILY_QUESTS.
public struct DailyQuest: Decodable, Sendable {
    public let id: String
    public let desc: String
    public let type: String
    public let target: Int
    public let reward: String
    public let rewardGold: Int?
    public let rewardPotion: Bool?
}

/// Today's quest and its progress, saved under "dd_daily_quest" like the web
/// version. Everyone gets the same quest on the same day (day of the year).
public final class DailyQuests {
    private struct Save: Codable {
        var date: String
        var id: String
        var progress: Int
        var complete: Bool
    }

    private let store: GameStore
    private let calendar: Calendar
    public var now: () -> Date = Date.init

    public init(store: GameStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    /// Quest types the Swift version can track. Spirits and lore fragments
    /// aren't ported yet, so those days fall back to the next quest in the list.
    static let supported: Set<String> = ["kills", "floor", "loot", "gold", "nopotion", "crits", "boss",
                                         "elite", "hollow", "skilluse", "survive", "nodmg"]

    private var todayKey: String {
        let c = calendar.dateComponents([.year, .month, .day], from: now())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private var save: Save {
        let today = todayKey
        if let s = store.getItem("dd_daily_quest"), let d = s.data(using: .utf8),
           let saved = try? JSONDecoder().decode(Save.self, from: d), saved.date == today {
            return saved
        }
        let list = GameContent.shared.dailyQuests
        let day = calendar.ordinality(of: .day, in: .year, for: now()) ?? 1
        var i = day % list.count
        for _ in 0..<list.count where !Self.supported.contains(list[i].type) { i = (i + 1) % list.count }
        let fresh = Save(date: today, id: list[i].id, progress: 0, complete: false)
        write(fresh)
        return fresh
    }

    private func write(_ s: Save) {
        if let d = try? JSONEncoder().encode(s), let str = String(data: d, encoding: .utf8) {
            store.setItem("dd_daily_quest", str)
        }
    }

    public var quest: DailyQuest {
        let id = save.id
        return GameContent.shared.dailyQuests.first { $0.id == id } ?? GameContent.shared.dailyQuests[0]
    }

    public var progress: Int { save.progress }
    public var isComplete: Bool { save.complete }

    /// "Defeat 10 enemies in a single run. 4 of 10. Reward: 100 gold."
    public var summary: String {
        let q = quest
        return isComplete ? "\(q.desc) Complete!" : "\(q.desc) \(progress) of \(q.target). Reward: \(q.reward)."
    }

    /// Adds progress for a quest type. Returns the completed quest, once, when it finishes.
    @discardableResult
    public func report(_ type: String, _ amount: Int = 1) -> DailyQuest? {
        var s = save
        let q = quest
        guard !s.complete, q.type == type, amount > 0 else { return nil }
        s.progress = min(q.target, s.progress + amount)
        if s.progress >= q.target { s.complete = true }
        write(s)
        return s.complete ? q : nil
    }

    /// Floor quests count the floor reached, not a running total (checkFloorQuest).
    @discardableResult
    public func reachedFloor(_ floor: Int, usedPotion: Bool) -> DailyQuest? {
        var s = save
        let q = quest
        guard !s.complete, q.type == "floor" || (q.type == "nopotion" && !usedPotion) else { return nil }
        s.progress = min(q.target, max(s.progress, floor))
        if floor >= q.target { s.complete = true }
        write(s)
        return s.complete ? q : nil
    }

    /// Pays a finished quest's reward into the run (completeDailyQuestReward).
    public static func payReward(_ q: DailyQuest, _ run: inout Run, wallet: Wallet) {
        if let g = q.rewardGold, g > 0 {
            run.gold += g
            wallet.addGold(g)
        }
        if q.rewardPotion == true {
            run.inventory.append(Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "Restores 40 HP.", heal: 40))
        }
    }
}
