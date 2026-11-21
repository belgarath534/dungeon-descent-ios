import Foundation

/// THE MEDUSA ARC (The Hollow): a rare fight with a gaze that turns you to
/// stone. Beaten, she can be finished (raise the shield) or spared (lower it):
/// spared, she guards you until you find her father, Lord Phorcys. A run
/// that never meets her may meet him instead, searching the Hollow alone.
public enum Medusa {
    public struct Arc: Codable, Equatable, Sendable {
        public var met = false
        public var joined = false
        public var fatherFound = false
        public init() {}
    }

    public static let hollow = "The Hollow"

    /// The Hollow's special fights, before a normal enemy (enterRoom):
    /// Medusa from floor 4 (10%, once a run), or Lord Phorcys from floor 6
    /// (8%) if she hasn't been met.
    static func encounter(for run: Run, dice: inout some Dice) -> Enemy? {
        guard run.dungeon == hollow else { return nil }
        if !run.medusa.met && run.floor >= 4 && (run.devMedusa || dice.chance(0.10)) {
            let hp = 65 + run.floor * 4
            var e = Enemy(name: "Medusa", icon: "🐍", hp: hp, maxHp: hp, atk: 10...18, gold: 20...35)
            e.desc = "Her gaze can petrify you."
            e.mechanics["medusa"] = .bool(true)
            return e
        }
        if !run.medusa.met && !run.medusa.fatherFound && run.floor >= 6 && dice.chance(0.08) {
            let hp = 90 + run.floor * 5
            var e = Enemy(name: "Lord Phorcys", icon: "👴", hp: hp, maxHp: hp, atk: 14...24, gold: 25...45)
            e.isElite = true
            e.desc = "He has been searching for his daughter. He blames everyone he meets. He is strong — but broken."
            e.mechanics["lordPhorcys"] = .bool(true)
            return e
        }
        return nil
    }

    public static func isMedusa(_ e: Enemy) -> Bool { e.flag("medusa") }

    /// applyMedusaGaze: 35% of her turns. The first gaze costs 3 defense for 2
    /// turns, the second costs your next turn, the third turns you to stone.
    static func gaze(_ run: inout Run, dice: inout some Dice, log: inout [String]) -> Bool {
        guard var e = run.enemy, isMedusa(e), dice.chance(0.35) else { return false }
        let stacks = Int(e.number("gazeStacks") ?? 0) + 1
        e.mechanics["gazeStacks"] = .number(Double(stacks))
        run.enemy = e
        switch stacks {
        case 1:
            run.fight.def -= 3
            run.fight.gazeTurns = 2
            log.append("🐍 Medusa's Gaze! Partially petrified. Defense minus 3 for 2 turns.")
        case 2:
            run.frozen = true
            log.append("🐍 Medusa's Gaze! Fully petrified — you lose your next turn!")
        default:
            run.hp = 0
            log.append("🐍 Turned to stone. The Hollow has a new statue.")
        }
        return true
    }

    /// checkMedusaGazeDecay
    static func tick(_ run: inout Run, log: inout [String]) {
        guard run.fight.gazeTurns > 0 else { return }
        run.fight.gazeTurns -= 1
        if run.fight.gazeTurns == 0 {
            run.fight.def += 3
            log.append("The petrification fades. Defense restored.")
        }
    }

    /// While she's with you, she blocks one attack a fight (Serpent Guard).
    public static func walksWithYou(_ run: Run) -> Bool { run.medusa.joined && !run.medusa.fatherFound }

    /// medusaLowerShield
    public static func spare(_ run: inout Run) -> String {
        run.medusa.joined = true
        run.enemy = nil
        run.inCombat = false
        return "🐍 You lower the shield. You close your eyes. You wait. The gaze never comes. She collapses — she is just a girl. She asks you to find her father, Lord Phorcys. She will fight alongside you until you find him: Serpent Guard blocks one attack every fight."
    }

    /// checkMedusaFatherSpawn: 60% a room while she's with you, 3% less for
    /// every reunion (down to 36%), back to 60% each month.
    public static func fatherChance(_ store: GameStore, now: Date = Date()) -> Double {
        var s = save(store)
        let nowMs = now.timeIntervalSince1970 * 1000
        guard let last = s["lastReset"], last > 0 else {
            s["lastReset"] = nowMs
            write(s, store)
            return 0.60
        }
        if nowMs - last >= 30 * 86_400_000 {
            s["reunions"] = 0
            s["lastReset"] = nowMs
            write(s, store)
            return 0.60
        }
        return max(0.36, 0.60 - (s["reunions"] ?? 0) * 0.03)
    }

    /// triggerMedusaFather: the reunion, and 50 gold from a grateful father.
    public static func reunion(_ run: inout Run, store: GameStore) -> String {
        run.medusa.fatherFound = true
        run.gold += 50
        var s = save(store)
        s["reunions"] = (s["reunions"] ?? 0) + 1
        if (s["lastReset"] ?? 0) == 0 { s["lastReset"] = Date().timeIntervalSince1970 * 1000 }
        write(s, store)
        return "🐍 A figure appears at the end of the hall. An old man. He sees Medusa. His face changes. Lord Phorcys — her father. He has been searching the Hollow for years. She runs to him. He catches her. The Hollow goes quiet for a moment. \"Thank you,\" he says, and presses 50 gold into your hand. \"Take it. Please.\""
    }

    // dd_medusa: {"reunions": n, "lastReset": ms}
    static func save(_ store: GameStore) -> [String: Double] {
        guard let s = store.getItem("dd_medusa"), let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }

    static func write(_ s: [String: Double], _ store: GameStore) {
        if let d = try? JSONSerialization.data(withJSONObject: s), let str = String(data: d, encoding: .utf8) { store.setItem("dd_medusa", str) }
    }
}
