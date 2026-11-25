import Foundation

/// 12.2: two more rare rooms, in any dungeon (like the Magic Chamber), and
/// the two items they give.
///
/// - The Wishing Well: toss in 25 gold for a wish (+3 attack this run, +15
///   max HP, or a Wishing Coin), or drink from it (SP restored, +15 HP).
/// - The Forgotten Music Room: play the piano (a healing song, a battle
///   song for 5 turns, or something hears you and comes), or take the
///   Sheet Music, a lullaby that puts an enemy to sleep for 2 turns.
public enum RareRooms {
    public static let wellId = "wishing-well"
    public static let musicId = "music-room"
    public static let wishCost = 25

    static let events: [Encounters.Event] = [
        Encounters.Event(
            id: wellId, title: "🪙 The Wishing Well",
            text: "An old stone well sits in the middle of the room. Coins glint far below, and when you lean close you can hear the water whispering wishes back.",
            choices: ["Toss in \(wishCost) gold and make a wish", "Drink from the well", "Walk away"], weight: 1, dungeons: nil),
        Encounters.Event(
            id: musicId, title: "🎼 The Forgotten Music Room",
            text: "Dust covers an old piano. A single sheet of music sits on its stand. The keys look like they still remember a song.",
            choices: ["Play the piano", "Take the sheet music", "Leave quietly"], weight: 1, dungeons: nil),
    ]

    public static let wishingCoin = Item(id: "wishing-coin", name: "Wishing Coin", icon: "🪙", type: "wishing-coin",
                                         desc: "A coin the well gave back. Make a wish: full HP and 20 SP.")
    public static let sheetMusic = Item(id: "sheet-music", name: "Sheet Music", icon: "🎼", type: "sheet-music",
                                        desc: "A lullaby. Use it in a fight to put a non-boss enemy to sleep for 2 turns.")

    static func choose(_ id: String, _ choice: Int, _ run: inout Run, dice: inout some Dice, wallet: Wallet) -> Encounters.Outcome? {
        typealias Outcome = Encounters.Outcome
        switch (id, choice) {
        case (wellId, 0):
            guard run.gold >= wishCost, wallet.spendGold(wishCost) else {
                var o = Outcome(message: "You search your pockets. You don't have \(wishCost) gold. The well waits.")
                o.retry = true
                return o
            }
            run.gold -= wishCost
            switch dice.roll(0...2) {
            case 0:
                run.atkBonus += 3
                return Outcome(message: "The coin falls a long way. Then a warm wind rises out of the well. Your wish is heard: plus 3 attack for the rest of this run.")
            case 1:
                run.maxHp += 15
                run.hp = min(run.maxHp, run.hp + 15)
                return Outcome(message: "The coin falls a long way. The water hums, and you feel sturdier. Your wish is heard: plus 15 max HP for this run.")
            default:
                run.inventory.append(wishingCoin)
                return Outcome(message: "The coin falls a long way, and then something flies back up and lands in your hand: a different coin, glowing faintly. You got a Wishing Coin.")
            }
        case (wellId, 1):
            run.sp = run.maxSp
            run.hp = min(run.maxHp, run.hp + 15)
            return Outcome(message: "The water is cold and tastes of old stone. Your mind clears. SP fully restored, and plus 15 HP.")
        case (wellId, _):
            return Outcome(message: "You leave the well to its whispering.")
        case (musicId, 0):
            switch dice.roll(0...2) {
            case 0:
                let heal = max(1, run.maxHp * 3 / 10)
                run.hp = min(run.maxHp, run.hp + heal)
                return Outcome(message: "You play a slow, gentle song. The room seems to breathe out. You heal \(heal) HP.")
            case 1:
                run.tempAtk = 6
                run.tempAtkTurns = 5
                return Outcome(message: "You play something fast and fierce. Your blood answers. Plus 6 attack for 5 turns.")
            default:
                var o = Outcome(message: "You play a haunting melody. Halfway through, something in the dark starts humming along. It's coming.")
                o.enemy = Combat.nextEnemy(for: run, dice: &dice)
                return o
            }
        case (musicId, 1):
            run.inventory.append(sheetMusic)
            return Outcome(message: "You fold the sheet music carefully and put it away. It's a lullaby. You got Sheet Music.")
        case (musicId, _):
            return Outcome(message: "You leave the piano to its silence.")
        default:
            return nil
        }
    }

    /// The two items, from the inventory.
    static func use(_ run: inout Run, _ item: Item) -> Inventory.Outcome? {
        switch item.type {
        case "wishing-coin":
            run.hp = run.maxHp
            run.sp = min(run.maxSp, run.sp + 20)
            return Inventory.Outcome(message: "🪙 You make a wish on the coin. Light runs through you. HP fully restored, plus 20 SP.")
        case "sheet-music":
            guard run.inCombat, var e = run.enemy else {
                return Inventory.Outcome(message: "Save the lullaby for a fight.", used: false)
            }
            guard !e.isBoss else { return Inventory.Outcome(message: "The boss doesn't listen to lullabies.", used: false) }
            e.stunTurns = max(e.stunTurns, 2)
            run.enemy = e
            return Inventory.Outcome(message: "🎼 You hum the lullaby. \(e.name)'s eyes grow heavy. It falls asleep for 2 turns.")
        default:
            return nil
        }
    }
}
