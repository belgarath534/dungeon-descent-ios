import Foundation

/// 12.1: four new enemies, each built around listening.
///
/// - The Liar (The Hollow): half its hits are announced wrong. Your HP never lies.
/// - The Bell Choir (The Sunken Archives): a bell before each move; low, middle
///   and high mean strike, heal or flee, shuffled every fight.
/// - The Counting Thing (Crypt of Malachar): counts down every turn and hits for
///   triple at zero. Defending resets the count.
/// - The Silent One (The Shadow World): no music, and its hits aren't announced
///   unless you hit it that turn.
///
/// Each is a rare spawn (5% of fights from floor 3) in its own dungeon, scaled
/// like the dungeon's other enemies.
public enum NewFoes {
    struct Def {
        let flag: String
        let dungeon: String
        let template: EnemyTemplate
    }

    public static let liar = "The Liar"
    public static let bellChoir = "The Bell Choir"
    public static let counter = "The Counting Thing"
    public static let silent = "The Silent One"

    static let defs: [Def] = [
        Def(flag: "liar", dungeon: "The Hollow",
            template: EnemyTemplate(name: liar, icon: "🎭", hp: 40, atk: 8...14, gold: 12...22,
                                    desc: "It smiles while it talks. Half of what it says about the fight is a lie. Your HP never lies.")),
        Def(flag: "bells", dungeon: "The Sunken Archives",
            template: EnemyTemplate(name: bellChoir, icon: "🔔", hp: 50, atk: 7...12, gold: 15...25,
                                    desc: "Three drowned bells ring before it moves. Low, middle and high: one means a crushing strike, one means it heals, one means it runs. Learn which, every fight.")),
        Def(flag: "counting", dungeon: "Crypt of Malachar",
            template: EnemyTemplate(name: counter, icon: "🔢", hp: 45, atk: 7...12, gold: 12...22,
                                    desc: "It counts down out loud. At zero it strikes with everything it has. Defending makes it lose count.")),
        Def(flag: "silent", dungeon: "The Shadow World",
            template: EnemyTemplate(name: silent, icon: "🤫", hp: 38, atk: 6...11, gold: 15...25,
                                    desc: "It makes no sound at all. The music stops. You only learn it hit you by checking your HP, unless you strike it, and it cries out.")),
    ]

    public static func isSilent(_ e: Enemy?) -> Bool { e?.flag("silent") == true }

    /// One of these four: what VoiceOver hears is built here, so the count,
    /// the bells and the Liar's lies are always read (short combat lines too).
    public static func isNew(_ e: Enemy?) -> Bool {
        guard let e else { return false }
        return ["liar", "bells", "counting", "silent"].contains { e.flag($0) }
    }

    /// 5% of normal fights from floor 3 in the enemy's own dungeon.
    public static func encounter(for run: Run, dice: inout some Dice) -> Enemy? {
        guard run.floor >= 3, run.communityDungeon == nil,
              let d = defs.first(where: { $0.dungeon == run.dungeon }), dice.chance(0.05) else { return nil }
        var e = Enemy.spawn(d.template, floor: run.floor, playerLevel: run.level,
                            ngPlusCount: Combat.ngCount(run), endless: run.difficulty == .endless)
        e.desc = d.template.desc
        e.mechanics[d.flag] = .bool(true)
        if d.flag == "counting" { e.mechanics["count"] = .number(6) }
        if d.flag == "bells" {
            var moves = ["strike", "heal", "flee"]
            for i in stride(from: moves.count - 1, to: 0, by: -1) { moves.swapAt(i, dice.roll(0...i)) }
            e.mechanics["bellMap"] = .string(moves.joined(separator: ","))
        }
        return e
    }

    // MARK: The fight

    static let pitches = ["low", "middle", "high"]

    static func bellMap(_ e: Enemy) -> [String] {
        if case .string(let s)? = e.mechanics["bellMap"] { return s.components(separatedBy: ",") }
        return ["strike", "heal", "flee"]
    }

    static func nextMove(_ e: Enemy) -> String? {
        if case .string(let s)? = e.mechanics["bellNext"] { return s }
        return nil
    }

    /// Picks the Bell Choir's next move and rings its bell.
    static func ring(_ e: inout Enemy, dice: inout some Dice, log: inout [String]) {
        // It only runs once it's been fighting a while.
        let roll = dice.roll(1...100)
        let move = roll <= 55 ? "strike" : roll <= 85 || e.turnsTaken < 2 ? "heal" : "flee"
        e.mechanics["bellNext"] = .string(move)
        let pitch = pitches[bellMap(e).firstIndex(of: move) ?? 0]
        log.append("🔔 A \(pitch) bell rings.")
    }

    static func begin(_ run: inout Run, _ enemy: Enemy, log: inout [String]) {
        guard var e = run.enemy else { return }
        if e.flag("liar") {
            log.append("🎭 It smiles. Nothing it says about this fight can be trusted. Your HP never lies.")
        } else if e.flag("bells") {
            log.append("🔔 Three drowned bells hang in the dark. Low, middle and high. Each one means something different, and the meaning changes every fight.")
            var d = SystemDice()
            ring(&e, dice: &d, log: &log)
            run.enemy = e
        } else if e.flag("counting") {
            log.append("🔢 It starts counting, slowly, out loud. When it reaches zero it strikes with everything. Defending makes it lose count.")
        } else if e.flag("silent") {
            log.append("🤫 The music stops. Something is here, and it makes no sound. Its hits will not be announced. Strike it and it cries out.")
        }
    }

    /// Before its attack: the count, or the bell's move.
    static func beforeAttack(_ run: inout Run, _ m: inout EnemyAbilities.Move, dice: inout some Dice, log: inout [String]) {
        guard var e = run.enemy else { return }
        defer { run.enemy = e }
        if e.flag("counting") {
            if run.defending {
                e.mechanics["count"] = .number(5)
                log.append("🔢 You brace yourself. It loses count, and starts again: five.")
                return
            }
            let n = Int(e.number("count") ?? 5) - 1
            if n <= 0 {
                e.mechanics["count"] = .number(5)
                m.multiplier *= 3
                log.append("🔢 ZERO. It strikes with everything it has!")
            } else {
                e.mechanics["count"] = .number(Double(n))
                let words = ["", "One", "Two", "Three", "Four", "Five"]
                log.append("🔢 \(n < words.count ? words[n] : String(n))…")
            }
        }
        if e.flag("bells"), let move = nextMove(e) {
            let pitch = pitches[bellMap(e).firstIndex(of: move) ?? 0]
            switch move {
            case "strike":
                m.multiplier *= 2
                log.append("🔔 The \(pitch) bell meant a strike. It hits with double force!")
            case "heal":
                let heal = max(1, e.maxHp / 5)
                e.hp = min(e.maxHp, e.hp + heal)
                m.skipAttack = true
                log.append("🔔 The \(pitch) bell meant healing. It mends \(heal) HP.")
            default: break
            }
            ring(&e, dice: &dice, log: &log)
        }
    }

    /// The Bell Choir runs when its bell said so (checked before it acts).
    static func flees(_ run: inout Run, log: inout [String]) -> Bool {
        guard let e = run.enemy, e.flag("bells"), nextMove(e) == "flee" else { return false }
        let pitch = pitches[bellMap(e).firstIndex(of: "flee") ?? 0]
        log.append("🔔 The \(pitch) bell meant escape. The Bell Choir sinks back into the water, and its gold goes with it.")
        return true
    }

    /// What VoiceOver hears after the enemy's turn. The Liar lies half the
    /// time; the Silent One is only heard if you hit it this turn. The HP
    /// figure is always true.
    static func announcement(_ e: Enemy, run: Run, taken: Int, playerDamage: Int, log: [String], dice: inout some Dice) -> String? {
        guard isNew(e) else { return nil }
        let hp = "Your HP: \(run.hp) of \(run.maxHp)."
        let cues = log.filter { $0.hasPrefix("🔢") || $0.hasPrefix("🔔") }
        let cue = cues.isEmpty ? "" : cues.joined(separator: " ") + " "
        if e.flag("liar"), dice.chance(0.5) {
            let lie = taken > 0
                ? (dice.chance(0.5) ? "The Liar misses you completely!" : "The Liar hits you for \(taken * 3) damage!")
                : "The Liar hits you for \(dice.roll(15...30)) damage!"
            return "\(lie) \(hp)"
        }
        if e.flag("silent") && playerDamage <= 0 {
            return "Silence. \(hp)"
        }
        if e.flag("silent") {
            return "It cries out when you strike it. For a moment you can hear it. "
                + (taken > 0 ? "It dealt \(taken) damage. " : "") + hp
        }
        return cue + (taken > 0 ? "\(e.name) dealt \(taken) damage. " : "") + hp
    }
}
