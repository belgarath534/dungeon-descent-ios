import Foundation

/// 12.1: Insane Mode's sanity bar (initInsaneMode, drainSanity, the Distorted,
/// the Sanity Drainer and the Insanity Potion on the web). Sanity starts at
/// 100, drains while you explore and every time you're hit, and at zero the
/// dungeon takes your mind and the run ends.
public enum Sanity {
    public static let tickSeconds = 10.0
    public static let distortedName = "The Distorted"
    public static let drainerName = "The Sanity Drainer"

    public static func active(_ run: Run) -> Bool { run.difficulty == .insane }

    /// Current sanity, 0–100 (a run saved before 12.1 starts full).
    public static func value(_ run: Run) -> Int { run.sanity ?? 100 }

    public static let startLine = "Insane Mode active. Sanity bar at 100 percent. Keep it above zero or the dungeon claims your mind."
    public static let lostLine = "The sanity bar reached zero. The dungeon did not kill you. It absorbed you. You woke up at the entrance with no memory of what happened below. The dungeon kept what it took."
    public static let killedBy = "the void (sanity 0%)"

    static let distortedMessages = [
        "Someone is watching you.", "Be careful.", "You have been defeated.", "Run.", "Watch.",
        "The sanity engulfs you.", "You cannot escape.", "We are all you can see.",
        "Be careful. Be careful. Be careful.", "It knows you are here.", "Do not look at it.",
        "You were warned.", "The walls remember everything.", "Turn back.", "It is behind you.",
        "You cannot win this.", "The dungeon is inside you now.",
    ]

    /// Lowers sanity; returns the warnings to read. At zero the player's HP
    /// drops to 0 too, so the usual death flow ends the run.
    @discardableResult
    public static func drain(_ run: inout Run, _ amount: Int) -> [String] {
        guard active(run), amount > 0, run.hp > 0 else { return [] }
        let prev = value(run)
        let now = max(0, prev - amount)
        run.sanity = now
        var out: [String] = []
        if now <= 0 {
            run.hp = 0
            out.append("🕳️ Sanity zero. " + lostLine)
            return out
        }
        for (m, line) in [(50, "Something is watching you."), (25, "The room feels wrong."), (10, "Critical. The dungeon is becoming unstable.")]
        where prev > m && now <= m {
            out.append("⚠ Warning. Sanity at \(m) percent. \(line)")
        }
        if prev > 5 && now <= 5 { out.append("⚠ CRITICAL. Sanity at 5 percent. You are almost gone.") }
        if out.isEmpty && amount > 8 { out.append("Sanity dropping. \(now) percent remaining.") }
        return out
    }

    public static func restore(_ run: inout Run, _ amount: Int) {
        guard active(run) else { return }
        run.sanity = min(100, value(run) + amount)
    }

    /// Every hit you take: 2, 4 or 8 sanity depending on how hard.
    public static func hit(_ run: inout Run, taken: Int) -> [String] {
        guard taken > 0 else { return [] }
        return drain(&run, taken > 15 ? 8 : taken > 8 ? 4 : 2)
    }

    // MARK: Insane Mode's own enemies

    /// enterRoom: 8% The Distorted, else 6% The Sanity Drainer.
    public static func encounter(for run: Run, dice: inout some Dice) -> Enemy? {
        guard active(run) else { return nil }
        if dice.chance(0.08) {
            let hp = 35 + run.floor * 2
            var e = Enemy(name: distortedName, icon: "▓", hp: hp, maxHp: hp, atk: 0...0, gold: 10...20)
            e.desc = "A psychological enemy. It does not deal HP damage. It drains your sanity."
            e.mechanics["distorted"] = .bool(true)
            return e
        }
        if dice.chance(0.06) {
            let hp = 45 + run.floor * 3
            var e = Enemy(name: drainerName, icon: "🕳️", hp: hp, maxHp: hp, atk: 8...15, gold: 15...30)
            e.desc = "A special Insane Mode enemy. It drains your sanity with every hit. Defeat it to earn an Insanity Potion."
            e.mechanics["sanityDrainer"] = .bool(true)
            return e
        }
        return nil
    }

    /// The fight's opening lines (and the Drainer's first 10 sanity).
    public static func begin(_ run: inout Run, _ e: Enemy, log: inout [String]) {
        if e.flag("distorted") {
            log.append("Something is in the room. It has been here longer than the room has.")
            log.append("The Distorted. It does not deal HP damage. It drains your sanity. Every time it acts, messages will interrupt. Stay focused and defeat it.")
        } else if e.flag("sanityDrainer") {
            log.append("The air in the room changes. Something is here that should not be here. It looks at you and you feel something leave.")
            log += drain(&run, 10)
            log.append("The Sanity Drainer. Defeat it to earn an Insanity Potion. It drains your sanity with every hit.")
        }
    }

    /// distortedTurn: 3 to 6 messages, each draining 3 sanity, and no HP damage.
    public static func distortedTurn(_ run: inout Run, dice: inout some Dice, log: inout [String]) {
        let count = dice.roll(3...6)
        for _ in 0..<count {
            log.append(distortedMessages[dice.roll(0...(distortedMessages.count - 1))])
            log += drain(&run, 3)
            if run.hp <= 0 { return }
        }
        log.append("The messages stop. Your turn returns.")
    }

    /// The Sanity Drainer's drop.
    public static func onKill(_ run: inout Run, _ e: Enemy, log: inout [String]) {
        guard e.flag("sanityDrainer") else { return }
        run.inventory.append(potion)
        log.append("🔴 The Sanity Drainer dropped an Insanity Potion! It is now in your inventory. Its effect is unknown.")
    }

    public static let potion = Item(id: "insanity-potion", name: "Insanity Potion", icon: "🔴", type: "insanity",
                                    desc: "A potion of unknown effect. It could restore your sanity completely. Or drain it.")

    /// useInsanityPotion: 50% clarity (sanity to 100), else 30–49 drained.
    public static func drink(_ run: inout Run, dice: inout some Dice) -> String {
        guard active(run) else { return "The Insanity Potion does nothing. Your mind is already your own." }
        if dice.chance(0.5) {
            run.sanity = 100
            return "Insanity Potion — Clarity! Complete clarity. Sanity fully restored to 100 percent."
        }
        let d = dice.roll(30...49)
        let warn = drain(&run, d)
        return "Insanity Potion — Wrong effect! The dungeon is louder now. Sanity drained by \(d) percent. " + warn.joined(separator: " ")
    }
}
