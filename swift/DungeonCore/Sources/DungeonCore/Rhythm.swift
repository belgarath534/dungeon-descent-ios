import Foundation

/// The Abyssal Deep's phase 4 (triggerRhythmGame, evaluateRhythm,
/// rhythmResult): the abyss beats three times, 0.8 seconds apart, and you
/// tap three times to match, each gap within 0.42 seconds, before 5 seconds
/// run out. Answering gives +40% attack and +30% defense for 2 turns;
/// hesitating makes the boss 30% stronger. The web version set the reward
/// but nothing read it; Swift gives it.
public enum Rhythm {
    public static let beats = 3
    public static let interval = 0.8
    public static let window = 0.42
    public static let tapTime = 5.0

    /// Tap times in seconds, in order.
    public static func matches(_ taps: [Double]) -> Bool {
        guard taps.count == beats else { return false }
        return zip(taps, taps.dropFirst()).allSatisfy { abs(($1 - $0) - interval) <= window }
    }

    /// rhythmResult. Returns what happened.
    public static func resolve(_ run: inout Run, won: Bool) -> String {
        run.fight.rhythmDue = false
        if won {
            let atk = jsRound(Double(max(1, run.atk.upperBound + run.totalAtkBonus)) * 0.4)
            let def = jsRound(Double(max(5, run.totalDef)) * 0.3)
            run.fight.buffAtk = atk
            run.fight.buffDef = def
            run.fight.buffTurns = 2
            return "🌊 You answered the call! +40% ATK and +30% DEF for 2 turns."
        }
        if var e = run.enemy {
            let lo = jsRound(Double(e.atk.lowerBound) * 1.3), hi = jsRound(Double(e.atk.upperBound) * 1.3)
            e.atk = lo...max(lo, hi)
            run.enemy = e
        }
        return "💀 You failed the call. The Leviathan enrages — its attacks are now 30% stronger!"
    }
}
