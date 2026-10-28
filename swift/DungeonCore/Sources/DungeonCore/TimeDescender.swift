import Foundation

/// THE TIME DESCENDER: a rare two-phase fight (floor 6+, 15%, once a run).
/// Beat the Descender and The Clock begins: it strikes three times, 5 seconds
/// apart, while you can only brace, then pauses for one precise strike.
/// The first win drops Chrono Armor, which stops the clock for good.
public enum TimeDescender {
    static func encounter(for run: Run, dice: inout some Dice) -> Enemy? {
        guard !run.timeDescenderMet, run.floor >= 6, dice.chance(0.15) else { return nil }
        let hp = 70 + run.floor * 4
        var e = Enemy(name: "The Time Descender", icon: "⏳", hp: hp, maxHp: hp, atk: 14...24, gold: 0...0)
        e.desc = "Unbound by the dungeon's usual rules. Defeat it to force its second phase, The Clock."
        e.mechanics["timeDescender"] = .bool(true)
        return e
    }

    public static func isDescender(_ e: Enemy) -> Bool { e.flag("timeDescender") }
    public static func isClock(_ e: Enemy) -> Bool { e.flag("clock") }

    /// timeDescenderPhaseTwo
    public static var clock: Enemy {
        var e = Enemy(name: "The Clock", icon: "🕰️", hp: 79, maxHp: 79, atk: 18...28, gold: 0...0)
        e.desc = "Your actions are locked while it ticks. One window to strike per cycle."
        e.mechanics["timeDescender"] = .bool(true)
        e.mechanics["clock"] = .bool(true)
        return e
    }

    public static func hasChronoArmor(_ run: Run) -> Bool { run.inventory.contains { $0.type == "chronoarmor" } }

    /// One tick of the clock: 18–28, half while bracing.
    public static func tick(_ run: inout Run, dice: inout some Dice) -> Int {
        var d = dice.roll(18...28)
        if run.defending { d = max(1, jsRound(Double(d) * 0.5)) }
        run.hp = max(0, run.hp - d)
        return d
    }

    /// timeDescenderClockHit: your strike in the window. A heavy strike hits
    /// 60% harder but misses 30% of the time. Defend braces for the next cycle.
    public static func strike(_ run: inout Run, heavy: Bool, defend: Bool, dice: inout some Dice) -> String {
        guard var e = run.enemy else { return "" }
        run.defending = defend
        if defend { return "You brace yourself for the next cycle." }
        if heavy && dice.chance(0.30) { return "Miss! Your heavy strike missed the clock. It resumes." }
        let bonus = run.totalAtkBonus
        var d = dice.roll((bonus + 8)...(bonus + 18))
        if heavy { d = jsRound(Double(d) * 1.6) }
        e.hp = max(0, e.hp - d)
        run.enemy = e
        return "You strike the clock for \(d). Clock HP: \(e.hp) of \(e.maxHp)."
    }

    /// timeDescenderVictory: 80–140 gold and 120 XP; the first win ever
    /// (dd_time_descender) leaves Chrono Armor.
    public static func victory(_ run: inout Run, store: GameStore, dice: inout some Dice) -> (gold: Int, armor: Bool) {
        let gold = dice.roll(80...140)
        run.gold += gold
        run.enemy = nil
        run.inCombat = false
        _ = Progression.gainXP(&run, 120)
        let first = !(store.getItem("dd_time_descender") ?? "").contains("\"defeated\":true")
        if first {
            store.setItem("dd_time_descender", "{\"defeated\":true}")
            run.inventory.append(Item(name: "Chrono Armor", icon: "⏳", type: "chronoarmor",
                                      desc: "Legendary. Negates the Time Descender clock cycle in all future encounters."))
        }
        return (gold, first)
    }
}
