import Foundation

/// 12.1 THE CONDUCTOR (Anomaly 0-17): a long hall with a door at the far end
/// and something at the front conducting a lullaby. You may only move while
/// the music plays. When it stops, stand still: it listens for you. The song
/// slows and goes out of tune before it stops, but sometimes that's a
/// fake-out and it plays on.
///
/// The rules live here; the timing (how long it plays, when it stops) is
/// picked here too, and the app runs the clock.
public struct ConductorHall: Codable, Sendable, Equatable {
    /// Steps from the entrance to the door.
    public var length: Int
    public var step = 0
    /// Times it heard you move in the silence.
    public var caught = 0
    /// True while the music is stopped. Saved, so closing the app in the
    /// silence doesn't let you walk out.
    public var silent = false
    /// How deep it found you: deeper, the song is faster and the silences longer.
    public var floor: Int

    public static let catchesAllowed = 3
    public static let pushBack = 2
    /// A step this soon after the music stops still counts as in time:
    /// VoiceOver and your finger need a moment.
    public static let grace = 0.6
    /// 12.2: the least time between two steps (spamming crossed the hall in a second).
    public static let stepGap = 1.0

    public init(floor: Int) {
        self.floor = floor
        length = floor >= 8 ? 8 : 7
    }

    public var left: Int { length - step }
    /// It plays the closer song for the last 3 steps.
    public var near: Bool { left <= 3 }

    public enum Outcome: Equatable, Sendable { case moved, escaped, caught, taken }

    /// A step forward. In the silence it hears you: pushed back, and the
    /// third time it keeps you.
    public mutating func move() -> Outcome {
        if silent {
            caught += 1
            if caught >= Self.catchesAllowed { return .taken }
            step = max(0, step - Self.pushBack)
            return .caught
        }
        step += 1
        return step >= length ? .escaped : .moved
    }

    // MARK: The clock

    /// One verse: how long the music plays, whether it then drags and goes
    /// out of tune, whether it really stops after that, and how long the
    /// silence lasts.
    public struct Verse: Equatable, Sendable {
        public var play: Double
        public var drag: Bool
        public var stops: Bool
        public var silence: Double
    }

    /// Deeper floors: shorter verses and longer silences. Most stops drag
    /// first, but not all of them, and a third of the drags are fake-outs.
    public func verse(dice: inout some Dice) -> Verse {
        let deep = min(1.0, Double(max(0, floor - 3)) / 7)
        let play = Double(dice.roll(30...80)) / 10 * (1 - 0.35 * deep)
        let drag = dice.chance(0.75)
        let stops = drag ? !dice.chance(0.33) : true
        let silence = Double(dice.roll(25...45)) / 10 * (1 + 0.4 * deep)
        return Verse(play: play, drag: drag, stops: stops, silence: silence)
    }

    /// How fast the song plays: 1 normally, a bit faster deeper down.
    public var tempo: Double { 1 + min(0.25, Double(max(0, floor - 3)) * 0.03) }

    // MARK: In a run

    /// From floor 3 in any dungeon, not on a boss floor, at most once a floor,
    /// 3% of rooms.
    public static func shouldStart(_ run: Run, bossFloor: Bool, dice: inout some Dice) -> Bool {
        run.floor >= 3 && !bossFloor && !run.inCombat && run.stalker == nil && run.conductor == nil
            && run.conductorFloor != run.floor && dice.chance(0.03)
    }

    public static func start(_ run: inout Run) -> ConductorHall {
        let h = ConductorHall(floor: run.floor)
        run.conductor = h
        run.conductorFloor = run.floor
        return h
    }

    /// Heard: a quarter of your max HP, but it leaves you standing.
    public static func heard(_ run: inout Run) -> Int {
        let dmg = jsRound(Double(run.maxHp) * 0.25)
        run.hp = max(1, run.hp - dmg)
        return dmg
    }

    /// The third time: half your max HP (still leaving you standing), the
    /// gold in your pocket that floor's worth, and you wake up outside.
    public static func taken(_ run: inout Run) -> (damage: Int, gold: Int) {
        run.conductor = nil
        let dmg = jsRound(Double(run.maxHp) * 0.5)
        run.hp = max(1, run.hp - dmg)
        let gold = min(run.gold, 25 * run.floor)
        run.gold -= gold
        return (dmg, gold)
    }

    /// Through the door: gold, a piece of this dungeon's gear, and a page of
    /// its containment file.
    public static func escaped(_ run: inout Run, wallet: Wallet, dice: inout some Dice) -> (gold: Int, item: Item?) {
        let h = run.conductor
        run.conductor = nil
        let gold = 100 + 20 * run.floor - 15 * (h?.caught ?? 0)
        run.gold += gold
        wallet.addGold(gold)
        let gear = ItemTables.loot(for: run.dungeon).filter { $0.isWeapon || $0.isArmor }
        guard !gear.isEmpty else { return (gold, nil) }
        let item = gear[dice.roll(0...(gear.count - 1))]
        run.inventory.append(item)
        return (gold, item)
    }

    // MARK: Words

    public var status: String {
        "🎻 Step \(step) of \(length). \(silent ? "SILENCE — don't move." : "The music plays — move.")  Heard: \(caught) / \(Self.catchesAllowed)"
    }

    /// Anomaly 0-17's containment file: a new page each time you get through
    /// its hall, kept across characters.
    public static let files: [String] = [
        "Anomaly 0-17, \"The Conductor\". Threat Class: Unknown. It appears in a hall that was not there before. It faces away from you and conducts a lullaby no one is playing. Do not move without music.",
        "Addendum 1: It has never been seen to turn around. Every report says it knew exactly where the explorer was standing when the music stopped.",
        "Addendum 2: The lullaby slows and goes out of tune before it ends. Explorers learned to stop when it drags. Then, sometimes, it played on. It is learning too.",
        "Addendum 3: Explorers it kept were found outside the hall the next morning, unharmed but for the ears. They hum the song. They do not know the words. There are no words.",
        "Addendum 4: Recovered sheet music, one page, unsigned. The final bar is a rest that goes on forever. Someone has written in the margin: 'not yet'.",
        "Final entry: The hall has a door at each end. No one has ever used the one behind it. Do not try. Do not move without music.",
    ]
}
