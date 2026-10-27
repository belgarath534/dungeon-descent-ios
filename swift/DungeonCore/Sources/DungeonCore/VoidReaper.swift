import Foundation

/// THE VOID REAPER: a world boss every player fights together. It sleeps for
/// 1–3 weeks, wakes for 24 hours with 50,000 shared HP, and each strike takes
/// 500 from it (600 for a heavy). If it isn't stopped, every dungeon is
/// cursed for 24 hours: enemies 50% stronger. The shared state lives in the
/// web version's Realtime Database at "void_reaper"; this is its rules.
public enum VoidReaper {
    public static let globalHp = 50_000
    public static let playerDamage = 500
    public static let windowHours = 24.0
    public static let punishHours = 24.0
    public static let strBonus = 0.59
    public static let goldReward = 2000
    public static let coinReward = 50

    /// The shared record (times in milliseconds, like the web version).
    public struct State: Equatable, Sendable {
        public var countdownStart = 0.0
        public var targetWakeDate = 0.0
        public var currentHp = globalHp
        public var totalHp = globalHp
        public var awake = false
        public var defeated = false
        public var punishmentUntil = 0.0
        public var killCount = 0
        public var lastKiller: String? = nil
        public var awakenedAt = 0.0
        public var windowExpiredAt = 0.0
        /// The countdownStart of the last cycle that ended in a kill, so
        /// everyone who struck in it can collect (new in Swift; the web
        /// version paid only the killing blow).
        public var lastDefeatedCycle = 0.0

        public init() {}

        public init(_ d: [String: Any]) {
            func num(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
            countdownStart = num("countdownStart")
            targetWakeDate = num("targetWakeDate")
            currentHp = d["currentHp"] == nil ? globalHp : Int(num("currentHp"))
            totalHp = d["totalHp"] == nil ? globalHp : max(1, Int(num("totalHp")))
            awake = d["awake"] as? Bool ?? false
            defeated = d["defeated"] as? Bool ?? false
            punishmentUntil = num("punishmentUntil")
            killCount = Int(num("killCount"))
            lastKiller = d["lastKiller"] as? String
            awakenedAt = num("awakenedAt")
            windowExpiredAt = num("windowExpiredAt")
            lastDefeatedCycle = num("lastDefeatedCycle")
        }

        // getVRState
        public func pct(now: Double) -> Int {
            if awake { return 100 }
            guard countdownStart > 0, targetWakeDate > countdownStart else { return 0 }
            return min(99, Int(((now - countdownStart) / (targetWakeDate - countdownStart) * 100).rounded(.down)))
        }

        public func windowExpired(now: Double) -> Bool {
            awake && awakenedAt > 0 && now - awakenedAt > windowHours * 3_600_000 && !defeated
        }

        public func isAwake(now: Double) -> Bool { awake && !defeated && !windowExpired(now: now) }

        public func hoursLeft(now: Double) -> Int {
            guard awakenedAt > 0 else { return 0 }
            return max(0, Int(((windowHours * 3_600_000 - (now - awakenedAt)) / 3_600_000).rounded(.up)))
        }

        public func daysLeft(now: Double) -> Int {
            targetWakeDate > 0 ? max(0, Int(((targetWakeDate - now) / 86_400_000).rounded(.up))) : 0
        }

        public func cursed(now: Double) -> Bool { punishmentUntil > now }

        /// Phase from the shared HP: 1 above 66%, 2 above 33%, then 3.
        public var phase: Int {
            let p = Double(currentHp) / Double(totalHp) * 100
            return p > 66 ? 1 : p > 33 ? 2 : 3
        }
    }

    /// vrCheckServerTransitions: what any client should write next.
    public enum Transition: Equatable, Sendable { case none, restart, wake, expire }

    public static func transition(_ s: State, now: Double) -> Transition {
        if s.defeated { return .restart }
        if !s.awake && s.targetWakeDate > 0 && now >= s.targetWakeDate { return .wake }
        if s.windowExpired(now: now) { return .expire }
        return .none
    }

    /// vrRestartCycle / vrSeedState: sleep 7 to 20 days.
    public static func restartFields(now: Double, dice: inout some Dice) -> [String: Any] {
        let days = 7 + dice.roll(0...13)
        return ["countdownStart": now, "targetWakeDate": now + Double(days) * 86_400_000,
                "currentHp": globalHp, "totalHp": globalHp, "awake": false, "defeated": false,
                "awakenedAt": 0, "windowExpiredAt": 0, "killCount": 0, "lastKiller": NSNull()]
    }

    /// A strike on the shared boss.
    public static func globalDamage(heavy: Bool) -> Int { heavy ? jsRound(Double(playerDamage) * 1.2) : playerDamage }

    // MARK: Your own fight (local HP, for the tension)

    public struct Fight: Equatable, Sendable {
        public var name: String
        public var hp: Int
        public var maxHp: Int
        public var atkBonus: Int
        public var potions = 3
        public var struck = false

        /// startVRFight: class HP + 20, and +59% of your saved attack bonus + 8.
        public init(_ ch: PlayerCharacter) {
            name = ch.name
            maxHp = GameData.classInfo(ch.cls).maxHp + 20
            hp = maxHp
            var bonus = 0
            if case .number(let n)? = ch.extra["atkBonus"] { bonus = Int(n) }
            atkBonus = jsRound(Double(bonus) * (1 + strBonus)) + 8
        }

        public var dead: Bool { hp <= 0 }
    }

    public enum Swing: String, Sendable { case attack, heavy, defend }

    /// vrAttack's answer: the Reaper strikes back, harder in later phases;
    /// defending takes 35% of it.
    public static func counter(_ f: inout Fight, _ swing: Swing, phase: Int, dice: inout some Dice) -> Int {
        var hit = dice.roll(18...32)
        if phase == 2 { hit = jsRound(Double(hit) * 1.25) }
        if phase == 3 { hit = jsRound(Double(hit) * 1.5) }
        if swing == .defend { hit = jsRound(Double(hit) * 0.35) }
        f.hp = max(0, f.hp - hit)
        return hit
    }

    /// vrHeal: 35% of max HP, and the Reaper strikes while you drink.
    public static func heal(_ f: inout Fight, phase: Int, dice: inout some Dice) -> (healed: Int, hit: Int)? {
        guard f.potions > 0 else { return nil }
        let h = jsRound(Double(f.maxHp) * 0.35)
        f.hp = min(f.maxHp, f.hp + h)
        f.potions -= 1
        var hit = dice.roll(14...24)
        if phase == 2 { hit = jsRound(Double(hit) * 1.15) }
        if phase == 3 { hit = jsRound(Double(hit) * 1.30) }
        f.hp = max(0, f.hp - hit)
        return (h, hit)
    }
}
