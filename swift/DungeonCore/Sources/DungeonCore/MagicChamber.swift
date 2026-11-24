import Foundation

/// 12.1: The Magic Chamber, a rare room in any dungeon (asked for by a player
/// on the Discord). A unicorn waits inside. Approach it and the first time it
/// joins you for good as a minion: Starlight, who fights beside you and heals
/// you a little every round. After that it blesses you each time you find it.
public enum MagicChamber {
    public static let id = "magic-chamber"
    public static let minionId = "unicorn"
    public static let name = "Starlight the Unicorn"
    /// Starlight's horn heals you this much after each of its attacks.
    public static let heal = 3

    static let event = Encounters.Event(
        id: id, title: "✨ The Magic Chamber",
        text: "A hidden chamber glows with soft, shifting light, like moonlight on water. In the middle stands a unicorn, white as starlight, its horn faintly humming. It looks at you as if it has been waiting.",
        choices: ["Approach the unicorn", "Leave it in peace"], weight: 1, dungeons: nil)

    public static func isUnicorn(_ m: Minion?) -> Bool { m?.id == minionId }

    static func choose(_ choice: Int, _ run: inout Run, store: GameStore?) -> Encounters.Outcome {
        guard choice == 0 else {
            run.hp = min(run.maxHp, run.hp + 10)
            return Encounters.Outcome(message: "You leave the unicorn in peace. It bows its head as you go, and the light follows you a little way. Plus 10 HP.")
        }
        run.hp = run.maxHp
        run.sp = run.maxSp
        guard let store else {
            return Encounters.Outcome(message: "The unicorn touches its horn to your shoulder. Warmth floods through you. HP and SP fully restored.")
        }
        var list = Home.minions(store)
        if list.contains(where: { $0.id == minionId }) {
            return Encounters.Outcome(message: "Starlight's light is in this room. It was here before you, waiting. It touches its horn to your shoulder. HP and SP fully restored.")
        }
        guard list.count < Home.maxMinions else {
            return Encounters.Outcome(message: "The unicorn touches its horn to your shoulder. HP and SP fully restored. It looks at your crowded Home and does not follow. Free a minion's place and it may come with you next time.")
        }
        list.append(Minion(id: minionId, name: name, icon: "🦄", atk: 10, tier: "rare",
                           capturedOn: (Date().timeIntervalSince1970 * 1000).rounded()))
        Home.saveMinions(list, store)
        var out = Encounters.Outcome(message: "You step closer. The unicorn lowers its head and touches its horn to your shoulder. Warmth floods through you. HP and SP fully restored. Then it follows you out. 🦄 Starlight the Unicorn has joined you as a minion! Choose it in your Home under Minions. It fights beside you, and its horn heals you every round.")
        out.stat = "unicornFound"
        return out
    }
}
