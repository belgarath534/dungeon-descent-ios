import Foundation

/// THE CHIMERA (CHIMERA SYSTEM): one beast of three parts, each attacking and
/// targeted on its own (Swift's ambush fight). The Lion Head hits hard, the
/// Goat Body regrows 8 HP a turn, the Serpent Tail poisons 8 a turn. In the
/// Whispering Forest it's The Corrupted Chimera: the Maw corrupts, the
/// Thornbound reflects a quarter of your damage, the Hollow Shell hits.
/// 17% of fights from floor 5, and always on your first visit to the
/// Whispering Forest's floor 9.
public enum Chimera {
    static func part(_ name: String, _ icon: String, _ hp: Int, _ atk: ClosedRange<Int>, _ desc: String,
                     _ extra: [String: JSONValue] = [:]) -> Enemy {
        var e = Enemy(name: name, icon: icon, hp: hp, maxHp: hp, atk: atk, gold: 0...0)
        e.desc = desc
        e.mechanics = extra
        e.mechanics["chimeraPart"] = .bool(true)
        return e
    }

    public static func spawn(_ run: Run, store: GameStore, dice: inout some Dice) -> [Enemy]? {
        let forest = run.dungeon == WhisperingForest.name
        let first = forest && run.floor == 9 && store.getItem("dd_whisper_chimera_seen") == nil
        guard first || (run.floor >= 5 && dice.chance(0.17)) else { return nil }
        if first { store.setItem("dd_whisper_chimera_seen", "1") }
        if forest {
            return [part("The Corrupted Maw", "🌑", 80, 14...22, "Corrupts on every hit.", ["chimeraCorrupt": .number(15), "corrupted": .bool(true)]),
                    part("The Thornbound", "🌿", 65, 10...18, "Reflects 25% damage back.", ["reflectPct": .number(0.25), "corrupted": .bool(true)]),
                    part("The Hollow Shell", "💀", 50, 8...14, "A shell that should be empty.", ["corrupted": .bool(true)])]
        }
        return [part("Lion Head", "🦁", 45, 10...18, "Strikes with crushing force."),
                part("Goat Body", "🐐", 35, 6...12, "Regenerates 8 HP per turn.", ["regenPerTurn": .number(8)]),
                part("Serpent Tail", "🐍", 25, 5...10, "Poisons you every turn.", ["poisonsPlayer": .number(8)])]
    }

    public static func name(_ parts: [Enemy]) -> String {
        parts.first?.flag("corrupted") == true ? "The Corrupted Chimera" : "The Chimera"
    }

    public static func isPart(_ e: Enemy) -> Bool { e.flag("chimeraPart") }

    /// chimeraEnemyTurn, per part before it strikes.
    static func beforeAttack(_ run: inout Run, log: inout [String]) {
        guard var e = run.enemy, isPart(e) else { return }
        if let r = e.number("regenPerTurn"), e.hp < e.maxHp {
            e.hp = min(e.maxHp, e.hp + Int(r))
            run.enemy = e
            log.append("\(e.name) regenerates \(Int(r)) HP.")
        }
        if let p = e.number("poisonsPlayer") {
            run.hp = max(0, run.hp - Int(p))
            log.append("\(e.name) poisons for \(Int(p)).")
        }
        if let c = e.number("chimeraCorrupt") {
            let lines = WhisperingForest.corrupt(&run, Int(c))
            if WhisperingForest.here(run) { log.append("+\(Int(c))% corruption.") }
            log += lines
        }
    }

    /// The Thornbound reflects a quarter of what you deal it.
    static func reflect(_ run: inout Run, _ dmg: Int, log: inout [String]) {
        guard let e = run.enemy, let p = e.number("reflectPct"), dmg > 0 else { return }
        let back = jsRound(Double(dmg) * p)
        run.hp = max(0, run.hp - back)
        log.append("\(e.name) reflects \(back) damage!")
    }

    /// chimeraVictory: the whole beast pays when its last part falls.
    public static func victory(_ run: inout Run, corrupted: Bool, dice: inout some Dice) -> (gold: Int, xp: Int) {
        let gold = corrupted ? dice.roll(30...49) : dice.roll(15...24)
        run.gold += gold
        return (gold, 120)
    }
}
