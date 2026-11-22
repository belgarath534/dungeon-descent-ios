import Foundation

/// 12.0.1: Endless Descent stat points. Every level gained in a run gives one
/// point; the player spends it on +20 max HP, +2 attack or +1 defense, kept
/// on the character ("afkStats": {hp, atk, def, points} — the web version uses
/// the same object, so it syncs) and added to every later Endless run, on top
/// of the automatic +10 HP and +1 attack a level. Unspent points wait.
public enum AFKStats {
    public enum Stat: String, CaseIterable, Sendable {
        case hp, atk, def
        public var amount: Int { self == .hp ? 20 : self == .atk ? 2 : 1 }
        public var label: String {
            switch self {
            case .hp: return "❤️ +20 Max HP"
            case .atk: return "⚔️ +2 Attack"
            case .def: return "🛡 +1 Defense"
            }
        }
        public var spoken: String {
            switch self {
            case .hp: return "20 more max HP"
            case .atk: return "2 more attack"
            case .def: return "1 more defense"
            }
        }
    }

    public struct Trained: Equatable, Sendable {
        public var hp = 0, atk = 0, def = 0, points = 0
        public func count(_ s: Stat) -> Int { s == .hp ? hp : s == .atk ? atk : def }
    }

    public static func trained(_ ch: PlayerCharacter) -> Trained {
        guard case .object(let o)? = ch.extra["afkStats"] else { return Trained() }
        func n(_ k: String) -> Int { if case .number(let x)? = o[k] { return max(0, Int(x)) }; return 0 }
        return Trained(hp: n("hp"), atk: n("atk"), def: n("def"), points: n("points"))
    }

    static func write(_ t: Trained, _ ch: inout PlayerCharacter) {
        ch.extra["afkStats"] = .object(["hp": .number(Double(t.hp)), "atk": .number(Double(t.atk)),
                                        "def": .number(Double(t.def)), "points": .number(Double(t.points))])
    }

    /// The run's levels become points to spend.
    public static func earn(_ levels: Int, _ ch: inout PlayerCharacter) {
        guard levels > 0 else { return }
        var t = trained(ch)
        t.points += levels
        write(t, &ch)
    }

    /// Spends one point. False when there's none.
    @discardableResult
    public static func spend(_ s: Stat, _ ch: inout PlayerCharacter) -> Bool {
        var t = trained(ch)
        guard t.points > 0 else { return false }
        t.points -= 1
        switch s {
        case .hp: t.hp += 1
        case .atk: t.atk += 1
        case .def: t.def += 1
        }
        write(t, &ch)
        return true
    }

    /// What the trained stats add to a run.
    static func apply(_ ch: PlayerCharacter, maxHp: inout Int, atk: inout Int, def: inout Int) {
        let t = trained(ch)
        maxHp += t.hp * Stat.hp.amount
        atk += t.atk * Stat.atk.amount
        def += t.def * Stat.def.amount
    }
}
