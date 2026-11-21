import Foundation

/// Boss riddles (BOSS_RIDDLES, rollBossRiddle, showBossRiddle,
/// answerBossRiddle): once a boss fight, 22% of your turns against a boss
/// still standing, it stops and asks a riddle. 30 seconds to choose one of
/// three answers: right heals 59 HP, wrong (or too slow) makes its attack 25%
/// stronger. The web version always listed the right answer first; Swift
/// shuffles them.
public enum BossRiddles {
    public struct Riddle: Codable, Equatable, Sendable {
        public let question: String
        /// In the order shown.
        public let answers: [String]
        public let correct: Int
    }

    static let all: [(q: String, a: [String])] = [
        ("I have cities, but no houses live there. I have mountains, but no trees grow there. I have water, but no fish swim there. What am I?", ["A map", "A dream", "A mirror"]),
        ("The more you take, the more you leave behind. What am I?", ["Footsteps", "Memories", "Gold"]),
        ("I speak without a mouth and hear without ears. I have no body, but I come alive with wind. What am I?", ["An echo", "A shadow", "A flame"]),
        ("I have hands but cannot clap. I have a face but no eyes. I tell you something important, but I never speak. What am I?", ["A clock", "A statue", "A corpse"]),
        ("What can run but never walks, has a mouth but never talks, has a head but never weeps, has a bed but never sleeps?", ["A river", "A shadow", "The wind"]),
        ("I am always hungry and must always be fed. The finger I touch will soon turn red. What am I?", ["Fire", "Poison", "A blade"]),
        ("The man who makes it does not need it. The man who buys it does not use it. The man who uses it does not know it. What is it?", ["A coffin", "A weapon", "A crown"]),
        ("What has roots as nobody sees, is taller than trees, up, up, up it goes, and yet never grows?", ["A mountain", "A dungeon", "A grave"]),
        ("I am not alive, but I grow. I have no lungs, but I need air. I have no mouth, but water kills me. What am I?", ["Fire", "Darkness", "Stone"]),
        ("What gets stronger the more you take away from it?", ["A hole", "A wound", "A shadow"]),
        ("I have no eyes, no ears, no mouth — yet I see everything that enters this place. What am I?", ["The dungeon", "The dark", "The door"]),
        ("Alive without breath, cold as death, never thirsty, ever drinking. What am I?", ["A fish", "A ghost", "The hollow"]),
    ]

    public static let seconds = 30
    public static let heal = 59

    /// After your turn: maybe a riddle (rollBossRiddle).
    public static func roll(_ run: inout Run, dice: inout some Dice) -> Riddle? {
        guard run.inCombat, let e = run.enemy, e.isBoss, !e.isDead, !run.fight.riddleAsked, dice.chance(0.22) else { return nil }
        run.fight.riddleAsked = true
        let r = all[dice.roll(0...(all.count - 1))]
        // Shuffle the three answers; the first in the table is the right one.
        var order = [0, 1, 2]
        for i in stride(from: 2, to: 0, by: -1) { order.swapAt(i, dice.roll(0...i)) }
        return Riddle(question: r.q, answers: order.map { r.a[$0] }, correct: order.firstIndex(of: 0)!)
    }

    /// The line the boss speaks (showBossRiddle).
    public static func spoken(_ r: Riddle) -> String {
        "The boss pauses. It speaks. \(r.question) " + r.answers.enumerated().map { "Answer \($0.offset + 1): \($0.element)." }.joined(separator: " ")
            + " You have \(seconds) seconds."
    }

    /// answerBossRiddle: nil for running out of time.
    public static func answer(_ run: inout Run, _ r: Riddle, choice: Int?) -> (right: Bool, message: String) {
        if choice == r.correct {
            run.hp = min(run.maxHp, run.hp + heal)
            return (true, "✓ Correct. The boss is silent. You feel stronger. +\(heal) HP.")
        }
        if var e = run.enemy {
            let lo = jsRound(Double(e.atk.lowerBound) * 1.25), hi = jsRound(Double(e.atk.upperBound) * 1.25)
            e.atk = lo...max(lo, hi)
            run.enemy = e
        }
        return (false, (choice == nil ? "Time is up. " : "") + "✗ Wrong. The boss grows furious. Its attack increased by 25%.")
    }
}
