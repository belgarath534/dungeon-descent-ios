import Foundation

/// The Independence Tournament (JULY4_TOURNAMENT, dd_july4_tourney): during
/// the Fourth of July event your first run sets a personal target (500 + 100
/// a level + up to 500, to the nearest 50). Every kill scores 25; reaching the
/// target is first place: 500 gold and 5 trophies. The web version restarted
/// it after every win, so it could be won again each run; Swift gives it once
/// a year, as it says.
public enum IndependenceTournament {
    static let key = "dd_july4_tourney"

    public struct State: Codable, Equatable, Sendable {
        public var active = false
        public var score = 0
        public var target = 0
        public var completed = false
        public var year: Int?
    }

    public static func state(_ store: GameStore) -> State {
        guard let s = store.getItem(key), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode(State.self, from: d) else { return State() }
        return v
    }

    static func save(_ s: State, _ store: GameStore) {
        if let d = try? JSONEncoder().encode(s), let str = String(data: d, encoding: .utf8) { store.setItem(key, str) }
    }

    static func year(_ date: Date) -> Int { Calendar(identifier: .gregorian).component(.year, from: date) }

    /// At the start of a run. Returns the announcement when it starts.
    public static func start(level: Int, store: GameStore, dice: inout some Dice, now: Date = Date()) -> String? {
        guard Events.active(on: now) == "july4" else { return nil }
        var s = state(store)
        let y = year(now)
        if s.year == y && (s.active || s.completed) { return nil }
        let raw = 500 + max(1, level) * 100 + dice.roll(0...499)
        s = State(active: true, score: 0, target: jsRound(Double(raw) / 50) * 50, completed: false, year: y)
        save(s, store)
        return "🎆 Independence Tournament started. Your target score is \(s.target) points. Earn points by defeating enemies."
    }

    /// A kill: 25 points, and first place at the target.
    public static func kill(store: GameStore, wallet: Wallet, now: Date = Date()) -> String? {
        var s = state(store)
        guard s.active, s.year == year(now), Events.active(on: now) == "july4" else { return nil }
        s.score += 25
        guard s.score >= s.target else { save(s, store); return nil }
        s.active = false
        s.completed = true
        save(s, store)
        wallet.addGold(500)
        store.setItem("dd_trophies", String((jsParseInt(store.getItem("dd_trophies")) ?? 0) + 5))
        return "🏆 First place! You reached your target score of \(s.target). 500 gold and 5 trophies awarded."
    }
}
