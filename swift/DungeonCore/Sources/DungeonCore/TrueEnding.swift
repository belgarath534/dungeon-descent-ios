import Foundation

/// The True Ending (checkTrueEnding, showTrueEnding): clear all eight main
/// dungeons ("dd_cleared_dungeons") and, once ("dd_true_ending_seen"), the
/// dungeon names you its master.
public enum TrueEnding {
    public static let dungeons = ["Crypt of Malachar", "The Ashbound Wastes", "Frosthold Abyss", "The Sunken Archives",
                                  "The Hollow", "The Whispering Forest", "The Infernal Descent", "The Abyssal Deep"]

    /// Each line and when it appears, in seconds.
    public static let lines: [(String, Double)] = [
        ("They said the depths could not be conquered.", 0.5),
        ("That the darkness was eternal.", 2),
        ("That no soul could survive what lay beneath.", 3.5),
        ("They were wrong.", 5.5),
        ("You descended into eight cursed dungeons.", 7.5),
        ("You faced the undead, the scorched, the frozen, the drowned,", 9),
        ("the hollow, the whispered, the infernal, and the abyssal.", 10.5),
        ("You faced every nightmare the dungeon could throw at you.", 12),
        ("And you are still standing.", 14),
    ]
    public static let titleAt = 16.0
    public static let title = "DUNGEON MASTER"
    public static let subtitle = "The dungeon has a master now. And it is you."

    public static func cleared(_ store: GameStore) -> [String] {
        guard let s = store.getItem("dd_cleared_dungeons"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return v
    }

    /// A dungeon was cleared. True when the ending should play now.
    @discardableResult
    public static func record(_ dungeon: String, store: GameStore) -> Bool {
        var c = cleared(store)
        if !c.contains(dungeon) {
            c.append(dungeon)
            if let d = try? JSONEncoder().encode(c), let s = String(data: d, encoding: .utf8) { store.setItem("dd_cleared_dungeons", s) }
        }
        return dungeons.allSatisfy(c.contains) && store.getItem("dd_true_ending_seen") == nil
    }

    public static func markSeen(_ store: GameStore) { store.setItem("dd_true_ending_seen", "1") }

    /// Developer Tools: let it play again on the next clear.
    public static func reset(_ store: GameStore) { store.removeItem("dd_true_ending_seen") }
}
