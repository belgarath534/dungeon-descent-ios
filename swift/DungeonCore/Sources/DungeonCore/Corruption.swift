import Foundation

/// CORRUPTION MODE (chosen at character creation): every life you lose darkens
/// your soul. At 25% the dungeon whispers, at 50% the Corrupted Hunter stalks
/// you, at 75% your skills can backfire, and at 100% every run is a
/// Corruption Run: double gold and a legendary prize from the boss.
///
/// The web version only ever added corruption on one rare kind of death and
/// never acted on 50, 75 or 100; this does what its description promised.
public enum Corruption {
    /// CORRUPTION_WHISPERS
    public static let whispers = [
        "Something in the dark knows your name.",
        "The walls remember everyone who has passed through them. They remember you.",
        "You have been here before. You do not remember it. The dungeon does.",
        "The enemies are not random. They were placed here specifically for you.",
        "You are not the first. The others did not leave.",
        "Your spirit companion has noticed something following you.",
        "The floor beneath you is colder than it should be.",
        "Something has been counting your steps since you entered.",
        "The dungeon is not trying to kill you. It is trying to keep you.",
        "You should turn back. You will not turn back.",
    ]

    /// onPlayerDeathCorruption: 5% for a life lost on floors 1–3, 7% on 4–6, 10% deeper.
    public static func gain(floor: Int) -> Int { floor >= 7 ? 10 : floor >= 4 ? 7 : 5 }

    /// A life was lost. Returns the new level and what crossing a threshold says.
    public static func lifeLost(_ run: inout Run) -> (total: Int, lines: [String])? {
        guard let prev = run.corruption else { return nil }
        let now = min(100, prev + gain(floor: run.floor))
        run.corruption = now
        var lines = ["☠ Corruption increases by \(now - prev)%. Total: \(now)%."]
        lines += thresholds(prev, now)
        return (now, lines)
    }

    /// checkCorruptionThresholds
    static func thresholds(_ prev: Int, _ now: Int) -> [String] {
        var out: [String] = []
        if prev < 25 && now >= 25 { out.append("⚠ Your corruption reaches 25%. The dungeon begins to whisper.") }
        if prev < 50 && now >= 50 { out.append("⚠ Corruption 50%. Something has noticed you. The Corrupted Hunter is coming.") }
        if prev < 75 && now >= 75 { out.append("⚠ Corruption 75%. Your skills are turning against you.") }
        if prev < 100 && now >= 100 { out.append("☠ Your soul is fully corrupted. You have become something the dungeon fears. From your next run, every run is a Corruption Run.") }
        return out
    }

    /// What's in effect, said when a run starts.
    public static func status(_ run: Run) -> String? {
        guard let c = run.corruption, c > 0 else { return nil }
        if c >= 100 {
            return "☠ YOU ARE THE DUNGEON NOW. Corruption Run: enemies fear you, gold drops doubled, a legendary reward awaits at the boss. Your skills may backfire, and the Corrupted Hunter stalks you."
        }
        var s = "☠ Corruption: \(c)%."
        if c >= 25 { s += " The dungeon whispers." }
        if c >= 50 { s += " The Corrupted Hunter stalks you." }
        if c >= 75 { s += " Your skills may backfire." }
        return s
    }

    /// 25%: on some rooms, the dungeon whispers.
    public static func whisper(_ run: Run, dice: inout some Dice) -> String? {
        guard let c = run.corruption, c >= 25, dice.chance(0.15) else { return nil }
        return "The dungeon whispers: " + whispers[dice.roll(0...(whispers.count - 1))]
    }

    /// 50%: one fight in ten, the Corrupted Hunter comes instead: one of the
    /// dungeon's strongest, a third tougher, with Soul Pierce (ignores defense).
    static func hunter(for run: Run, dice: inout some Dice) -> Enemy? {
        guard let c = run.corruption, c >= 50, run.floor >= 2, dice.chance(0.10) else { return nil }
        let pool = Bestiary.enemies(for: run.dungeon, difficulty: run.difficulty).t3
        guard !pool.isEmpty else { return nil }
        let t = pool[dice.roll(0...(pool.count - 1))]
        var e = Enemy.spawn(t, floor: run.floor, playerLevel: run.level, ngPlusCount: Combat.ngCount(run),
                            endless: run.difficulty == .endless)
        e.name = "Corrupted Hunter"
        e.icon = "🏹"
        e.hp = jsRound(Double(e.hp) * 1.3)
        e.maxHp = e.hp
        e.isElite = true
        e.desc = "Soul Pierce"
        e.mechanics["corruptedHunter"] = .bool(true)
        return e
    }

    /// 75%: a skill can backfire (15%): the SP is spent, nothing happens to
    /// the enemy, and it costs you 10% of your max HP (never your last point).
    static func backfire(_ run: inout Run, skill: String, dice: inout some Dice) -> String? {
        guard let c = run.corruption, c >= 75, dice.chance(0.15) else { return nil }
        let hurt = max(1, jsRound(Double(run.maxHp) * 0.10))
        run.hp = max(1, run.hp - hurt)
        return "☠ The corruption twists \(skill) — it backfires! You take \(hurt) damage."
    }

    /// 100%: gold drops doubled.
    public static func goldMult(_ run: Run) -> Int { (run.corruption ?? 0) >= 100 ? 2 : 1 }

    /// 100%: the boss leaves a legendary weapon or armor.
    public static func bossPrize(_ run: inout Run, dice: inout some Dice) -> Item? {
        guard (run.corruption ?? 0) >= 100, let legendary = Rarity.tiers.first(where: { $0.id == "legendary" }) else { return nil }
        let item = Inventory.equipment(level: max(1, 1 + run.floor / 3), tier: legendary, dice: &dice)
        run.inventory.append(item)
        return item
    }
}
