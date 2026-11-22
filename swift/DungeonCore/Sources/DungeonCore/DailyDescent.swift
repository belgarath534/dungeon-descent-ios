import Foundation

/// Daily Descent, the daily login reward (DAILY_REWARDS, initDailyDescentBadge,
/// checkDailyDescent, claimDailyDescent). A 30-day cycle of gold and a bonus;
/// every finished cycle adds 50 gold to each day after. Saved in
/// "dd_daily_descent" in the web version's shape, so a streak carries over.
public enum DailyDescent {
    public enum Bonus: Equatable, Sendable {
        case potion(name: String, icon: String, heal: Int)
        case elixir(name: String, icon: String, healPct: Double)
        case fragments(Int)
        case coins(Int)
        case monthly(coins: Int, fragments: Int)
    }

    public struct Reward: Equatable, Sendable {
        public var day: Int
        public var gold: Int
        public var icon: String
        public var name: String
        public var desc: String
        public var bonus: Bonus?

        /// The chips under the reward ("💰 25g", "✨ 5 Soul Fragments" …).
        public var parts: [String] {
            var p = ["💰 \(gold)g"]
            switch bonus {
            case .potion(let n, let i, _), .elixir(let n, let i, _): p.append("\(i) \(n)")
            case .fragments(let n): p.append("✨ \(n) Soul Fragments")
            case .coins(let n): p.append("🪙 \(n) Mystery Coin\(n == 1 ? "" : "s")")
            case .monthly(let c, let f): p += ["🪙 \(c) Mystery Coins", "✨ \(f) Soul Fragments"]
            case nil: break
            }
            return p
        }
    }

    static func r(_ gold: Int, _ icon: String, _ name: String, _ desc: String, _ bonus: Bonus? = nil) -> Reward {
        Reward(day: 0, gold: gold, icon: icon, name: name, desc: desc, bonus: bonus)
    }
    static let health = Bonus.potion(name: "Health Potion", icon: "🧪", heal: 40)
    static let greater = Bonus.potion(name: "Greater Potion", icon: "💊", heal: 80)

    public static let cycle: [Reward] = [
        r(25, "💰", "25 Gold", "A small offering from the dungeon. Every descent begins here."),
        r(40, "🧪", "40 Gold + Health Potion", "The dungeon remembers you returned. It rewards consistency.", health),
        r(55, "✨", "55 Gold + 5 Soul Fragments", "Three days. The dungeon is starting to respect you.", .fragments(5)),
        r(70, "✨", "70 Gold + 8 Soul Fragments", "A soul fragment stirs. Something down here is rooting for you.", .fragments(8)),
        r(90, "🪙", "90 Gold + Mystery Coin", "Five days. The merchant left something for you at the entrance.", .coins(1)),
        r(110, "💊", "110 Gold + Greater Potion", "Six days without stopping. The dungeon yields more than usual.", greater),
        r(130, "🌋", "130 Gold + Volcanic Elixir", "A full week. The vendor sends a Volcanic Elixir down with the delivery.", .elixir(name: "Volcanic Elixir", icon: "🌋", healPct: 0.65)),
        r(150, "✨", "150 Gold + 10 Soul Fragments", "Eight days. The fragments are starting to add up.", .fragments(10)),
        r(170, "🧪", "170 Gold + Health Potion", "Nine days. The dungeon keeps a tab, and you are owed.", health),
        r(190, "🪙", "190 Gold + Mystery Coin", "Ten days. A milestone most never reach.", .coins(1)),
        r(210, "🌑", "210 Gold + Void Elixir", "The vendor has heard of your streak and sends a Void Elixir.", .elixir(name: "Void Elixir", icon: "🌑", healPct: 0.65)),
        r(230, "✨", "230 Gold + 12 Soul Fragments", "Twelve days. Your resolve is starting to show.", .fragments(12)),
        r(250, "💊", "250 Gold + Greater Potion", "Thirteen days. Unlucky for the dungeon, not for you.", greater),
        r(270, "🪙", "270 Gold + 2 Mystery Coins", "Two full weeks. The merchant is impressed.", .coins(2)),
        r(300, "🌿", "300 Gold + Sylvan Elixir", "Halfway through the month. The vendor sends a Sylvan Elixir.", .elixir(name: "Sylvan Elixir", icon: "🌿", healPct: 0.60)),
        r(320, "✨", "320 Gold + 15 Soul Fragments", "Sixteen days. The fragments hum with stored power.", .fragments(15)),
        r(340, "🧪", "340 Gold + Health Potion", "Seventeen days. Still here. Still descending.", health),
        r(360, "🪙", "360 Gold + Mystery Coin", "Eighteen days. The dungeon has stopped being surprised.", .coins(1)),
        r(380, "🩶", "380 Gold + Hollow Elixir", "The vendor sends a Hollow Elixir. Left behind by someone who no longer needs it.", .elixir(name: "Hollow Elixir", icon: "🩶", healPct: 0.55)),
        r(400, "✨", "400 Gold + 18 Soul Fragments", "Twenty days. A number that means something.", .fragments(18)),
        r(420, "💊", "420 Gold + Greater Potion", "Three weeks. The dungeon has run out of ways to test you.", greater),
        r(440, "🪙", "440 Gold + 2 Mystery Coins", "Twenty-two days. Close now.", .coins(2)),
        r(460, "🔱", "460 Gold + Hellfire Elixir", "The vendor sends a Hellfire Elixir, distilled from infernal flame.", .elixir(name: "Hellfire Elixir", icon: "🔱", healPct: 0.65)),
        r(480, "✨", "480 Gold + 20 Soul Fragments", "Twenty-four days. Almost a month.", .fragments(20)),
        r(500, "⭐", "500 Gold + Superior Potion", "Twenty-five days. The dungeon brews something stronger for you.", .potion(name: "Superior Potion", icon: "⭐", heal: 120)),
        r(520, "🪙", "520 Gold + 2 Mystery Coins", "Twenty-six days. The merchant no longer asks your name.", .coins(2)),
        r(540, "🌑", "540 Gold + Shadow Elixir", "The vendor sends a Shadow Elixir, brewed from the dark between worlds.", .elixir(name: "Shadow Elixir", icon: "🌑", healPct: 0.65)),
        r(560, "✨", "560 Gold + 25 Soul Fragments", "Four full weeks. The fragments could almost speak.", .fragments(25)),
        r(580, "🪙", "580 Gold + 3 Mystery Coins", "Twenty-nine days. One more.", .coins(3)),
        r(700, "👑", "700 Gold + 5 Mystery Coins + 50 Soul Fragments", "A full month. The dungeon bows. This reward will not come again until you have earned it again.", .monthly(coins: 5, fragments: 50)),
    ]

    /// getDailyRewardForDay: the reward for a streak day, +50 gold per finished cycle.
    public static func reward(forDay day: Int) -> Reward {
        let d = max(1, day)
        var out = cycle[(d - 1) % 30]
        out.gold += ((d - 1) / 30) * 50
        out.day = d
        return out
    }

    /// The saved streak ({ streak, lastClaim: "2026-10-30" style "Y-M-D", totalDays }).
    public struct State: Equatable, Sendable {
        public var streak = 0
        public var lastClaim: String?
        public var totalDays = 0
    }

    public static func state(_ store: GameStore) -> State {
        guard let s = store.getItem("dd_daily_descent"), let d = s.data(using: .utf8),
              case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: d) else { return State() }
        var st = State()
        if case .number(let n)? = o["streak"] { st.streak = Int(n) }
        if case .string(let c)? = o["lastClaim"] { st.lastClaim = c }
        if case .number(let n)? = o["totalDays"] { st.totalDays = Int(n) }
        return st
    }

    static func save(_ st: State, _ store: GameStore) {
        let o: [String: JSONValue] = ["streak": .number(Double(st.streak)),
                                      "lastClaim": st.lastClaim.map { .string($0) } ?? .null,
                                      "totalDays": .number(Double(st.totalDays))]
        if let d = try? JSONEncoder().encode(JSONValue.object(o)), let s = String(data: d, encoding: .utf8) {
            store.setItem("dd_daily_descent", s)
        }
    }

    /// Today as the web version writes it: year-month-day without leading zeros.
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func date(_ key: String, calendar: Calendar) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    public struct Status: Equatable, Sendable {
        /// Today's reward is already taken.
        public var claimed: Bool
        /// The streak as it stands (after a missed day, 0).
        public var streak: Int
        /// The day the next claim counts as, and its reward.
        public var next: Reward
    }

    /// Where the streak stands right now. Missing a whole day starts it over.
    /// (The web version parsed dates like "2026-10-5", which Safari can't read
    /// when the month or day is one digit, so on iPhone those claims never broke.)
    public static func status(_ store: GameStore, now: Date = Date(), calendar: Calendar = .current) -> Status {
        var st = state(store)
        let today = key(now, calendar: calendar)
        if st.lastClaim == today {
            return Status(claimed: true, streak: st.streak, next: reward(forDay: st.streak + 1))
        }
        if let last = st.lastClaim.flatMap({ date($0, calendar: calendar) }),
           let days = calendar.dateComponents([.day], from: last, to: calendar.startOfDay(for: now)).day, days > 1 {
            st.streak = 0
        }
        return Status(claimed: false, streak: st.streak, next: reward(forDay: st.streak + 1))
    }

    /// Claims today's reward: gold to the wallet, potions and elixirs to your
    /// saved items, Mystery Coins and Soul Fragments to their counters.
    /// Returns nil if today's is already claimed.
    @discardableResult
    public static func claim(store: GameStore, wallet: Wallet, now: Date = Date(), calendar: Calendar = .current) -> Reward? {
        let s = status(store, now: now, calendar: calendar)
        guard !s.claimed else { return nil }
        let reward = s.next
        wallet.addGold(reward.gold)
        let inv = GlobalInventory(store: store)
        func fragments(_ n: Int) {
            store.setItem("dd_soul_fragments", String((jsParseInt(store.getItem("dd_soul_fragments")) ?? 0) + n))
        }
        switch reward.bonus {
        case .potion(let n, let i, let heal):
            inv.add(Item(name: n, icon: i, type: "potion", desc: "Daily Descent reward.", heal: heal))
        case .elixir(let n, let i, let pct):
            inv.add(Item(name: n, icon: i, type: "elixir", desc: "Daily Descent reward.", healPct: pct))
        case .fragments(let n): fragments(n)
        case .coins(let n): Spire.addCoins(n, store: store)
        case .monthly(let c, let f): Spire.addCoins(c, store: store); fragments(f)
        case nil: break
        }
        var st = state(store)
        st.streak = reward.day
        st.lastClaim = key(now, calendar: calendar)
        st.totalDays += 1
        save(st, store)
        return reward
    }
}
