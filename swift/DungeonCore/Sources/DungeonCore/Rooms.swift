import Foundation

/// What a room holds, rolled the way enterRoom() does: a fight first, then
/// loot (28%), otherwise a special event or an empty room.
public enum Rooms {
    public enum Outcome: Equatable, Sendable { case fight, loot, event }

    public static func combatChance(_ d: GameData.Difficulty) -> Double {
        switch d {
        case .nightmare: return 0.60
        case .forsaken: return 0.55
        case .condemned: return 0.48
        default: return 0.40
        }
    }

    /// Same odds as the web version's single roll against
    /// `combatChance` and `combatChance + 0.28`.
    public static func roll(_ d: GameData.Difficulty, dice: inout some Dice) -> Outcome {
        let fight = combatChance(d)
        if dice.chance(fight) { return .fight }
        return dice.chance(0.28 / (1 - fight)) ? .loot : .event
    }
}
