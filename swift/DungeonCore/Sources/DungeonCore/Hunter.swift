import Foundation

/// HUNTER MODE: something follows you through the dungeon, a room closer every
/// time you move or finish a fight. At two rooms you choose: fight it or
/// sprint away. If it reaches you, you lose a life.
public enum Hunter {
    public struct State: Codable, Equatable, Sendable {
        /// Rooms behind you.
        public var dist = 10
        /// 2 from floor 2: it found your trail and moves faster.
        public var phase = 1
        /// Turns taken, for phase 2's extra step every third turn.
        public var turns = 0
        public init() {}
    }

    public enum Step: Equatable, Sendable {
        /// It came closer; the line to speak.
        case closer(Int, String)
        /// Two rooms or less, and you're not in a fight: fight or run.
        case choose(Int, String)
        /// It reached you.
        case caught
    }

    /// hunterAnnounce's lines.
    public static func line(_ dist: Int) -> String {
        switch dist {
        case 8...: return "🏹 The hunter is far behind. \(dist) rooms away."
        case 7: return "🏹 You hear distant footsteps. The hunter is 7 rooms away."
        case 6: return "🏹 The hunter draws closer. 6 rooms away."
        case 5: return "🏹 You can hear breathing in the dark. 5 rooms away."
        case 4: return "🏹 The hunter is close. 4 rooms away. Keep moving."
        case 3: return "🏹 THREE rooms away. You need to move. NOW."
        case 2: return "🏹 TWO rooms. It can almost smell you. Fight or run."
        default: return "🏹 ONE room. It is right behind you. FIGHT OR RUN — NOW."
        }
    }

    /// hunterTurn: one room closer. (The web version's faster second phase
    /// still moved one room a turn; here it takes an extra step every third turn.)
    public static func advance(_ run: inout Run) -> Step? {
        guard var h = run.hunter else { return nil }
        h.turns += 1
        var steps = 1
        if h.phase == 2 && h.turns % 3 == 0 { steps = 2 }
        h.dist = max(0, h.dist - steps)
        run.hunter = h
        if h.dist <= 0 { return .caught }
        if h.dist <= 2 && !run.inCombat { return .choose(h.dist, line(h.dist)) }
        return .closer(h.dist, line(h.dist))
    }

    /// advanceFloor: it falls 3 rooms behind on the stairs (at most 10), and
    /// from floor 2 it's on your trail.
    public static func newFloor(_ run: inout Run) -> String? {
        guard var h = run.hunter else { return nil }
        var said = ""
        if run.floor >= 2 && h.phase == 1 {
            h.phase = 2
            said = "🏹 The hunter has found your trail. It is moving faster now. "
        }
        h.dist = min(10, h.dist + 3)
        run.hunter = h
        return said + "🏹 New floor. The hunter resets — now \(h.dist) rooms behind you."
    }

    /// hunterRun: you buy one more turn; it's right behind you.
    public static func sprint(_ run: inout Run) -> String {
        run.hunter?.dist = 1
        return "🏃 You sprint away! The hunter is ONE room behind you. Do NOT stop moving."
    }

    /// hunterFight: The Hunter, scaled to your level. It's a boss: no fleeing.
    public static func enemy(level: Int) -> Enemy {
        let hp = 60 + level * 20
        var e = Enemy(name: "The Hunter", icon: "🏹", hp: hp, maxHp: hp,
                      atk: (8 + level * 3)...(14 + level * 4), gold: (50 + level * 15)...(50 + level * 15))
        e.isBoss = true
        e.mechanics["hunter"] = .bool(true)
        return e
    }

    public static func isHunter(_ e: Enemy) -> Bool { e.mechanics["hunter"] == .bool(true) }

    /// hunterCatch: a life lost and it circles back to 8 rooms, or the run ends.
    /// Returns false when that was your last life.
    public static func caught(_ run: inout Run) -> Bool {
        run.inCombat = false
        run.enemy = nil
        run.foes = []
        guard run.lives > 1 else {
            run.lives = 0
            run.hunter = nil
            return false
        }
        run.lives -= 1
        run.hunter?.dist = 8
        return true
    }

    /// hunterSlain: Hunter Mode ends for the run, with its trophy, 200 XP and
    /// 100 gold on top (plus 30 XP and 15 gold a level).
    public static func slain(_ run: inout Run) -> (xp: Int, gold: Int) {
        run.hunter = nil
        run.inventory.append(Item(name: "Hunter's Trophy", icon: "🏹", type: "material",
                                  desc: "You killed the hunter. Proof that you are something the dungeon fears.", cost: 200))
        return (200 + run.level * 30, 100 + run.level * 15)
    }

    /// The heartbeat's pace once it's 5 rooms or closer, in seconds between beats.
    public static func heartbeat(_ dist: Int) -> Double? {
        dist > 5 ? nil : dist <= 1 ? 0.4 : dist <= 2 ? 0.6 : dist <= 3 ? 0.9 : 1.2
    }
}
