import Foundation

/// What a room holds, rolled the way enterRoom() does: a fight first, then
/// loot (28%), otherwise a special event or an empty room.
public enum Rooms {
    public enum Outcome: String, Codable, Equatable, Sendable { case fight, loot, event }

    public static func combatChance(_ d: GameData.Difficulty) -> Double {
        switch d {
        case .nightmare: return 0.60
        case .forsaken: return 0.55
        case .condemned: return 0.48
        default: return 0.40
        }
    }

    /// The next room: one a Scroll of Reveal already showed, or a fresh roll.
    public static func next(_ run: inout Run, dice: inout some Dice) -> Outcome {
        if !run.upcomingRooms.isEmpty { return run.upcomingRooms.removeFirst() }
        return roll(run.difficulty, dice: &dice)
    }

    /// How many rooms a new floor has (advanceFloor): floor 10 is just the boss.
    public static func roomsNeeded(floor: Int, difficulty: GameData.Difficulty, bossFloor: Int = 10, dice: inout some Dice) -> Int {
        if floor == bossFloor && difficulty != .endless { return 1 }
        if floor <= 3 { return 5 + dice.roll(0...3) }
        if floor <= 6 { return 7 + dice.roll(0...4) }
        return 9 + dice.roll(0...6)
    }

    /// A room description fitting the depth: the first third of the list on
    /// floors 1–3, the middle third on 4–6, the rest deeper (enterRoom).
    public static func description(for run: Run, dice: inout some Dice) -> String {
        let descs = GameContent.shared.dungeon(run.dungeon).rooms
        guard !descs.isEmpty else { return "" }
        let bucket = run.floor <= 3 ? 0 : run.floor <= 6 ? 1 : 2
        let size = max(1, descs.count / 3)
        let start = min(bucket * size, descs.count - 1)
        let end = bucket == 2 ? descs.count : min(start + size, descs.count)
        let pool = Array(descs[start..<max(start + 1, end)])
        return pool[dice.roll(0...(pool.count - 1))]
    }

    /// The floor's name, cycling through the dungeon's list like the web version.
    public static func floorName(_ floor: Int, dungeon: String) -> String {
        let names = GameContent.shared.dungeon(dungeon).floors
        guard names.count > 1 else { return "Floor \(floor)" }
        let n = names[((max(floor, 1) - 1) % (names.count - 1)) + 1]
        return n.isEmpty ? "Chamber" : n
    }

    /// Same odds as the web version's single roll against
    /// `combatChance` and `combatChance + 0.28`.
    public static func roll(_ d: GameData.Difficulty, dice: inout some Dice) -> Outcome {
        let fight = combatChance(d)
        if dice.chance(fight) { return .fight }
        return dice.chance(0.28 / (1 - fight)) ? .loot : .event
    }
}
