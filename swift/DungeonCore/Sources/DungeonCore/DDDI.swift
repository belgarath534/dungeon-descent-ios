import Foundation

/// The DDDI SECRET BOSS (spawnDDDIBoss, checkDDDIVictory): the Grand Overseer
/// of the Department of Dungeon Descent Incorporated, at the strength of the
/// boss he replaced (and at least the web version's 280 HP), in three phases.
/// Beating him doesn't end the run: the dungeon's real boss still waits.
public enum DDDI {
    public static let name = "Grand Overseer of the DDDI"

    public static func dress(_ b: inout Enemy) {
        b.name = name
        b.icon = "🏛️"
        b.hp = max(280, b.hp)
        b.maxHp = b.hp
        b.desc = "THE DEPARTMENT OF DUNGEON DESCENT INCORPORATED HAS ARRIVED. The Grand Overseer materializes from a cloud of paperwork. Your dungeon record shows compliance violations."
        b.phaseMsg2 = "The Grand Overseer adjusts their robes. \"Your compliance record is insufficient.\" They hit harder."
        b.phaseMsg3 = "The Grand Overseer produces a 47-page document. \"Article IV, Section 12.\" The dungeon shakes."
        b.mechanics["dddi"] = .bool(true)
    }

    public static func isOverseer(_ e: Enemy) -> Bool { e.flag("dddi") }

    /// The reward: 175 to 225 gold, +10 max HP and SP for the run (and 20 HP
    /// and 10 SP back), and the Department's grudging acknowledgement.
    public static func defeated(_ run: inout Run, dice: inout some Dice) -> Int {
        run.dddiDefeated = true
        let gold = 175 + dice.roll(0...50)
        run.gold += gold
        run.maxHp += 10
        run.hp = min(run.maxHp, run.hp + 20)
        run.maxSp += 10
        run.sp = min(run.maxSp, run.sp + 10)
        return gold
    }

    public static let victoryLine = "COMPLIANCE ACHIEVED. You have defeated the Grand Overseer of the Department of Dungeon Descent Incorporated. The Department does not acknowledge this defeat. The Department does not care. Your suspension has been reduced to 358,999,999 years."
}
