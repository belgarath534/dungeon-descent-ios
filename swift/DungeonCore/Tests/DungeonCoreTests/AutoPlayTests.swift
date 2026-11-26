import XCTest
@testable import DungeonCore

/// Automatic play-testing. These run with the other game rules tests on every
/// build (and before every TestFlight upload), so a crash or a broken combo is
/// caught before players find it.
///
/// - `testFreeSkillsCannotGrowWithoutLimit`: spams every free-action skill of
///   every class at 0 SP (an Apocalypse weapon) and fails if anything keeps
///   growing (the Arcane Armor shield reached 70,000 this way).
/// - `testRandomFightsKeepTheGameSane`: a bot plays thousands of fights with
///   every class in every dungeon, pressing random buttons, and checks after
///   every action that HP, SP, shields and the enemy stay in range. A crash
///   here is a crash in the app.
///
/// Every failure names the class, skill or seed, so it can be replayed.
final class AutoPlayTests: XCTestCase {
    static let apocalypseAxe: Item = {
        var i = Item(id: "axe", name: "Battle Axe", icon: "🪓", type: "weapon", desc: "Heavy.",
                     atkBase: [10, 20], level: 1, isEquippable: true)
        i.extra["rarityEffect"] = .string("apocalypse")
        return i
    }()

    func newRun(_ cls: String, dungeon: String = "Crypt of Malachar",
                difficulty: GameData.Difficulty = .wanderer) -> Run {
        Run(character: PlayerCharacter(name: "Bot", cls: cls, race: "Human", prof: "Thief",
                                       dungeon: dungeon, difficulty: difficulty))
    }

    /// The numbers a free skill must not be able to raise without limit.
    struct Snapshot: Equatable, CustomStringConvertible {
        var values: [(String, Double)]
        init(_ r: Run) {
            values = [
                ("shield", Double(r.fight.shield)),
                ("dodges", Double(r.fight.dodges)),
                ("max HP", Double(r.maxHp)),
                ("max SP", Double(r.maxSp)),
                ("attack bonus", Double(r.atkBonus)),
                ("defense bonus", Double(r.defBonus)),
                ("fight attack", Double(r.fight.atk)),
                ("fight defense", Double(r.fight.def)),
                ("free skills", Double(r.freeSkills)),
                ("skill damage bonus", r.skillDamageBonus),
                ("all damage bonus", r.allDamageBonus),
                ("gold", Double(r.gold)),
                ("xp", Double(r.xp)),
            ]
        }
        static func == (a: Snapshot, b: Snapshot) -> Bool { a.values.map(\.1) == b.values.map(\.1) }
        func grown(since early: Snapshot) -> [String] {
            zip(early.values, values).filter { $1.1 > $0.1 }.map { "\($0.0) \($0.1) → \($1.1)" }
        }
        var description: String { values.map { "\($0.0)=\($0.1)" }.joined(separator: " ") }
    }

    func testFreeSkillsCannotGrowWithoutLimit() {
        var problems: [String] = []
        for info in GameData.classes {
            let cls = info.id
            for skill in Skills.all(for: cls) where SkillTable.spec(cls: cls, effect: skill.effect).isFree {
                var r = newRun(cls)
                r.equippedWeapon = Self.apocalypseAxe
                r.maxHp = 100_000; r.hp = 100_000
                r.maxSp = 500; r.sp = 500
                r.unlockedSkills = [skill.effect]
                let wall = Enemy(name: "Wall", icon: "", hp: 10_000_000, maxHp: 10_000_000, atk: 1...1, gold: 1...1)
                Combat.begin(&r, against: wall)
                var dice = SeededDice(seed: 7)
                var early: Snapshot?
                for i in 1...300 {
                    guard r.inCombat, r.enemy != nil else { break }
                    _ = Skills.use(&r, skill.effect, dice: &dice)
                    if i == 30 { early = Snapshot(r) }
                }
                guard let early, r.inCombat else { continue }
                let grown = Snapshot(r).grown(since: early)
                if !grown.isEmpty {
                    problems.append("\(cls) \(skill.name) (\(skill.effect)): \(grown.joined(separator: ", ")) between cast 30 and 300")
                }
            }
        }
        XCTAssert(problems.isEmpty, "Free skills that grow without limit at 0 SP:\n" + problems.joined(separator: "\n"))
    }

    func testRandomFightsKeepTheGameSane() {
        var problems: [String] = []
        let difficulties: [GameData.Difficulty] = [.wanderer, .nightmare]
        var seed: UInt64 = 1
        for info in GameData.classes {
            for dungeon in GameData.dungeons {
                for difficulty in difficulties {
                    seed &+= 1
                    let label = "\(info.id) in \(dungeon) (\(difficulty.rawValue)), seed \(seed)"
                    if let p = playFights(cls: info.id, dungeon: dungeon, difficulty: difficulty, seed: seed) {
                        problems.append("\(label): \(p)")
                        if problems.count >= 20 { break }
                    }
                }
            }
        }
        XCTAssert(problems.isEmpty, "The bot found broken game states:\n" + problems.joined(separator: "\n"))
    }

    /// Plays a few fights on rising floors with random actions. Returns the
    /// first broken state it sees, with the last actions taken.
    func playFights(cls: String, dungeon: String, difficulty: GameData.Difficulty, seed: UInt64) -> String? {
        var dice = SeededDice(seed: seed)
        var r = newRun(cls, dungeon: dungeon, difficulty: difficulty)
        r.unlockedSkills = Skills.all(for: cls).map(\.effect)
        if dice.chance(0.3) { r.equippedWeapon = Self.apocalypseAxe }
        var recent: [String] = []
        for fight in 0..<6 {
            r.floor = [1, 3, 5, 8, 10, 15][fight]
            r.hp = r.maxHp; r.sp = r.maxSp
            let foe = r.floor % 5 == 0 ? Combat.nextBoss(for: r, dice: &dice) : Combat.nextEnemy(for: r, dice: &dice)
            Combat.begin(&r, against: foe)
            recent.append("fight \(fight + 1) on floor \(r.floor) vs \(foe.name)")
            for _ in 0..<150 {
                guard r.inCombat, let e = r.enemy else { break }
                let roll = dice.roll(0...9)
                let res: TurnResult
                if roll < 5, !r.unlockedSkills.isEmpty {
                    let s = r.unlockedSkills[dice.roll(0...(r.unlockedSkills.count - 1))]
                    recent.append("skill \(s) vs \(e.name) (\(e.hp) HP)")
                    res = Skills.use(&r, s, dice: &dice)
                } else {
                    let a: PlayerAction = [.attack, .attack, .heavy, .defend, .flee][min(4, roll - 5 < 0 ? 0 : roll - 5)]
                    recent.append("\(a.rawValue) vs \(e.name) (\(e.hp) HP)")
                    res = Combat.takeTurn(&r, a, dice: &dice)
                }
                if recent.count > 8 { recent.removeFirst(recent.count - 8) }
                if let p = brokenState(r) {
                    return p + "\n    last actions: " + recent.joined(separator: " → ")
                }
                if res.playerDied || r.hp <= 0 { break }
            }
            if r.inCombat { r.inCombat = false; r.enemy = nil; r.foes = [] }
        }
        return nil
    }

    func brokenState(_ r: Run) -> String? {
        if r.maxHp < 1 { return "max HP is \(r.maxHp)" }
        if r.hp < 0 { return "HP is negative (\(r.hp))" }
        if r.hp > r.maxHp { return "HP \(r.hp) is above max HP \(r.maxHp)" }
        if r.sp < 0 { return "SP is negative (\(r.sp))" }
        if r.fight.shield < 0 { return "shield is negative (\(r.fight.shield))" }
        if r.gold < 0 { return "gold is negative (\(r.gold))" }
        if let e = r.enemy {
            if e.maxHp < 1 { return "\(e.name)'s max HP is \(e.maxHp)" }
            if e.hp > e.maxHp { return "\(e.name) has \(e.hp) HP, above its max \(e.maxHp)" }
        }
        return nil
    }
}
