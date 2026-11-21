import Foundation

/// The Whispering Forest's corruption (CORRUPTION SYSTEM, startCorruptionSystem):
/// a meter that creeps up 1% every 8 seconds you spend exploring and jumps
/// when The Shade hits you. At 100% the forest takes a life. A Music Box,
/// left on the path every third floor, clears it; potions push it back.
/// It's kept with the run, so leaving the app doesn't reset it.
public enum WhisperingForest {
    public static let name = "The Whispering Forest"
    public static let tickSeconds = 8.0
    /// How much a healing potion pushes the meter back.
    public static let potionCleanse = 10

    public static func here(_ run: Run) -> Bool { run.dungeon == name }

    /// addCorruption: the warnings at 50, 75 and 90, and at 100 the forest
    /// takes you (HP to 0). Then the meter empties: the web version left it
    /// full, so after a revive the next tick killed you again.
    public static func corrupt(_ run: inout Run, _ amount: Int) -> [String] {
        guard here(run), amount > 0 else { return [] }
        let prev = run.forestCorruption
        let now = min(100, prev + amount)
        run.forestCorruption = now
        var out: [String] = []
        if now >= 100 {
            run.hp = 0
            run.forestCorruption = 0
            out.append("🌲 Fully corrupted. The corruption consumes you. The forest claims another soul.")
        } else if prev < 90 && now >= 90 {
            out.append("🌲 WARNING. Corruption at 90 percent. You are almost lost.")
        } else if prev < 75 && now >= 75 {
            out.append("🌲 Danger. Corruption at 75 percent. Find the Music Box or use a potion.")
        } else if prev < 50 && now >= 50 {
            out.append("🌲 Warning. Corruption at 50 percent.")
        }
        return out
    }

    /// Every third floor (3, 6 and 9) a Music Box waits on the path.
    public static func onFloor(_ run: inout Run) -> String? {
        guard here(run), run.floor % 3 == 0, run.floor < 10 else { return nil }
        run.inventory.append(musicBox)
        return "🎵 A Music Box was left on the path. It is in your inventory. Use it to clear corruption."
    }

    public static let musicBox: Item = {
        var i = Item(name: "Music Box", icon: "🎵", type: "keyitem",
                     desc: "A small music box. In the Whispering Forest, its melody purges all corruption. Use it from your inventory.")
        i.extra["isWhisperMusicBox"] = .bool(true)
        return i
    }()

    public static func isMusicBox(_ i: Item) -> Bool { i.extra["isWhisperMusicBox"] == .bool(true) }

    // MARK: The Shade

    /// spawnTheShade: 8% of fights from floor 9, in any dungeon.
    static func shade(for run: Run, dice: inout some Dice) -> Enemy? {
        guard run.floor >= 9, dice.chance(0.08) else { return nil }
        var e = Enemy(name: "The Shade", icon: "🌑", hp: 289, maxHp: 289, atk: 18...28, gold: 40...70)
        e.desc = "Something darker than darkness. Sometimes strikes three times."
        e.mechanics["shade"] = .bool(true)
        return e
    }

    /// applyShadeSpecialHit: 30% of its attacks land three times (100% + 60% + 40%).
    static func shadeTriple(_ run: inout Run, dice: inout some Dice, log: inout [String]) -> Bool {
        guard var e = run.enemy, e.flag("shade") else { return false }
        let triple = dice.chance(0.30)
        e.mechanics["shadeTriple"] = .bool(triple)
        run.enemy = e
        if triple { log.append("🌑 The Shade strikes THREE times!") }
        return triple
    }

    /// In the forest, The Shade's hits corrupt: 12%, or 20% for a triple strike.
    static func afterAttack(_ run: inout Run, log: inout [String]) {
        guard let e = run.enemy, e.flag("shade"), here(run) else { return }
        let n = e.mechanics["shadeTriple"] == .bool(true) ? 20 : 12
        log.append("🌲 +\(n)% corruption.")
        log += corrupt(&run, n)
    }
}
