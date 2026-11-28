import XCTest
@testable import DungeonCore

/// The bot makes characters the way character creation does, starts their
/// first run the way the app does, and plays fights with them; and it makes
/// community enemies (including odd ones from older versions or the web)
/// and fights them. A player reported the game closing "during play or
/// creation"; a crash anywhere here is a crash in the app, and a broken
/// number is named with the character that caused it.
final class CreationBotTests: XCTestCase {
    let play = makeAutoPlay()

    /// What RunModel.newRun does at the start of a run, without the app's
    /// screens and online parts.
    func startRun(_ ch: PlayerCharacter, store: MemoryStore, wallet: Wallet, classTraits: Bool) -> Run {
        var r = Run(character: ch, gold: wallet.gold)
        r.applyStartBonuses(wallet: wallet)
        _ = Legacy.start(&r, ch)
        _ = Prestige.start(&r, ch)
        _ = Professions.start(&r, prof: r.prof)
        BossRelics.start(&r)
        _ = Races.start(&r, classTraits: classTraits, wallet: wallet)
        _ = DailyChallenge.start(&r, store: store, wallet: wallet)
        _ = ClassTraits.start(&r, classTraits: classTraits)
        r.event = Events.active()
        _ = Events.applyNextRun(&r, store: store)
        return r
    }

    /// Every class, race and profession, in Classic and Legacy, with and
    /// without class traits, on every difficulty: creating the character
    /// and starting its run must give a sane character.
    func testEveryCharacterCanBeCreatedAndStarted() {
        var problems: [String] = []
        let modes = ["classic", "legacy"]
        var n = 0
        for info in GameData.classes {
            for race in GameData.races {
                for prof in GameData.professions {
                    for mode in modes {
                        n += 1
                        let difficulty = GameData.Difficulty.allCases[n % GameData.Difficulty.allCases.count]
                        let dungeon = GameData.dungeons[n % GameData.dungeons.count]
                        let spirit = Spirits.all[n % Spirits.all.count].id
                        var ch = PlayerCharacter(name: "Bot \(n)", cls: info.id, race: race.id, prof: prof.id, dungeon: dungeon,
                                                 difficulty: difficulty, runMode: mode, spirit: spirit,
                                                 corruptionMode: n % 3 == 0, hunterMode: n % 5 == 0, hardcoreMode: n % 7 == 0)
                        if mode == "legacy" && n % 2 == 0 { ch.persistLevel = 1 + n % 50; ch.dungeonTier = 1 + n % 5 }
                        // Saved and loaded again, as the character list does.
                        guard let data = try? JSONEncoder().encode(ch), let back = try? JSONDecoder().decode(PlayerCharacter.self, from: data) else {
                            problems.append("\(info.id) \(race.id) \(prof.id) \(mode): can't be saved and loaded"); continue
                        }
                        let store = MemoryStore()
                        let r = startRun(back, store: store, wallet: Wallet(store: store), classTraits: n % 2 == 0)
                        if let p = play.brokenState(r) ?? startProblem(r) {
                            problems.append("\(info.id) \(race.id) \(prof.id) \(mode) \(difficulty.rawValue): \(p)")
                            if problems.count >= 25 { break }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(n, 100)
        XCTAssert(problems.isEmpty, "Character creation made broken characters:\n" + problems.joined(separator: "\n"))
    }

    func startProblem(_ r: Run) -> String? {
        if r.hp != r.maxHp && r.hp <= 0 { return "starts with \(r.hp) HP" }
        if r.maxSp < 0 { return "max SP is \(r.maxSp)" }
        if r.level < 1 { return "level is \(r.level)" }
        if r.lives < 1 && r.difficulty != .endless { return "starts with \(r.lives) lives" }
        if r.floor < 0 { return "floor is \(r.floor)" }
        return nil
    }

    /// Newly made characters of every class, with a random race and
    /// profession, play fights with random buttons (the same checks as the
    /// fight bot after every action).
    func testNewCharactersPlayFights() {
        var problems: [String] = []
        var seed: UInt64 = 5_000
        for info in GameData.classes {
            for round in 0..<6 {
                seed &+= 1
                var dice = SeededDice(seed: seed)
                let race = GameData.races[dice.roll(0...(GameData.races.count - 1))].id
                let prof = GameData.professions[dice.roll(0...(GameData.professions.count - 1))].id
                let dungeon = GameData.dungeons[dice.roll(0...(GameData.dungeons.count - 1))]
                let mode = round % 2 == 0 ? "classic" : "legacy"
                let ch = PlayerCharacter(name: "Bot", cls: info.id, race: race, prof: prof, dungeon: dungeon,
                                         difficulty: [.wanderer, .forsaken, .nightmare][round % 3], runMode: mode)
                let store = MemoryStore()
                var r = startRun(ch, store: store, wallet: Wallet(store: store), classTraits: round % 2 == 1)
                let label = "\(info.id) \(race) \(prof) \(mode) in \(dungeon), seed \(seed)"
                if let p = fight(&r, dice: &dice, fights: 4) { problems.append("\(label): \(p)") }
                if problems.count >= 20 { break }
            }
        }
        XCTAssert(problems.isEmpty, "New characters hit broken states:\n" + problems.joined(separator: "\n"))
    }

    /// Community enemies: every type made with the creator's rules, edited,
    /// and odd ones as an old version or the web could have stored them
    /// (zero or negative stats, huge stats, no icon, long names, emoji).
    /// Fighting each must stay sane.
    func testCommunityEnemiesCanBeMadeAndFought() {
        var problems: [String] = []
        var dice = SeededDice(seed: 77)
        var entries: [CommunityEnemies.Entry] = []
        for kind in CommunityEnemies.Kind.allCases {
            let s = CommunityEnemies.roll(kind, dice: &dice)
            let e = CommunityEnemies.Entry(name: "Bot \(kind.rawValue)", desc: "Made by the bot.", type: kind.rawValue, dungeon: "all",
                                           music: nil, creator: "Bot", icon: kind.icon, hp: s.hp, atk: s.atk, def: s.def)
            XCTAssertNil(CommunityEnemies.problem(name: e.name, desc: e.desc, creator: e.creator))
            entries.append(e)
            let edited = CommunityEnemies.edit(e, name: "Renamed \(kind.rawValue)", desc: "Edited.", kind: kind, reroll: true, dice: &dice)
            XCTAssertNil(edited.problem)
            entries.append(edited.entry)
        }
        let odd: [(Int, Int, Int)] = [(0, 0, 0), (-50, -5, -3), (1, 1, 0), (999_999, 99_999, 9_999), (5, 2_000_000_000, 0), (2_000_000_000, 1, 0)]
        for (i, s) in odd.enumerated() {
            entries.append(CommunityEnemies.Entry(name: i % 2 == 0 ? "🦇 Odd \(i)" : String(repeating: "Long", count: 30), desc: "",
                                                  type: "nonsense", dungeon: "Nowhere", music: "missing-track", creator: "",
                                                  icon: "", hp: s.0, atk: s.1, def: s.2))
        }
        // Problem checks never crash on any text.
        for text in ["", " ", "a", "🦇🦇", String(repeating: "x", count: 5_000), "Hellhound", "ass"] {
            _ = CommunityEnemies.problem(name: text, desc: text, creator: text)
        }
        for (i, ce) in entries.enumerated() {
            var r = play.newRun(GameData.classes[i % GameData.classes.count].id)
            r.unlockedSkills = Skills.all(for: r.cls).map(\.effect)
            let foe = CommunityEnemies.fight(ce)
            _ = CommunityEnemies.announcement(foe)
            _ = CommunityEnemies.music(foe)
            r.floor = 3
            Combat.begin(&r, against: foe)
            if let p = playOne(&r, dice: &dice) { problems.append("\(ce.name) (\(ce.hp) HP, \(ce.atk) attack): \(p)") }
        }
        // And from the pool, the way rooms spawn them.
        CommunityEnemies.pool = entries
        defer { CommunityEnemies.pool = [] }
        for i in 0..<200 {
            var r = play.newRun(GameData.classes[i % GameData.classes.count].id, dungeon: GameData.dungeons[i % GameData.dungeons.count])
            r.floor = 1 + i % 9
            if let foe = CommunityEnemies.spawn(for: r, dice: &dice) {
                Combat.begin(&r, against: foe)
                if let p = playOne(&r, dice: &dice) { problems.append("spawned \(foe.name): \(p)") }
            }
        }
        XCTAssert(problems.isEmpty, "Community enemies broke the game:\n" + problems.joined(separator: "\n"))
    }

    // MARK: Playing

    func fight(_ r: inout Run, dice: inout SeededDice, fights: Int) -> String? {
        r.unlockedSkills = Skills.all(for: r.cls).map(\.effect)
        for f in 0..<fights {
            r.floor = [1, 4, 7, 10][f % 4]
            r.hp = r.maxHp; r.sp = r.maxSp
            let foe = r.floor % 5 == 0 ? Combat.nextBoss(for: r, dice: &dice) : Combat.nextEnemy(for: r, dice: &dice)
            Combat.begin(&r, against: foe)
            if let p = playOne(&r, dice: &dice) { return "fight \(f + 1) vs \(foe.name): \(p)" }
            if r.hp <= 0 { return nil }
        }
        return nil
    }

    /// One fight with random buttons; the first broken state, or nil.
    func playOne(_ r: inout Run, dice: inout SeededDice) -> String? {
        var recent: [String] = []
        for _ in 0..<150 {
            guard r.inCombat, let e = r.enemy else { break }
            let res: TurnResult
            if dice.roll(0...9) < 5, !r.unlockedSkills.isEmpty {
                let s = r.unlockedSkills[dice.roll(0...(r.unlockedSkills.count - 1))]
                recent.append("skill \(s) vs \(e.name) (\(e.hp) HP)")
                res = Skills.use(&r, s, dice: &dice)
            } else {
                let a: PlayerAction = [.attack, .attack, .heavy, .defend, .flee][dice.roll(0...4)]
                recent.append("\(a.rawValue) vs \(e.name) (\(e.hp) HP)")
                res = Combat.takeTurn(&r, a, dice: &dice)
            }
            if recent.count > 6 { recent.removeFirst() }
            if let p = play.brokenState(r) { return p + "\n    last actions: " + recent.joined(separator: " → ") }
            if res.playerDied || r.hp <= 0 { break }
        }
        if r.inCombat { r.inCombat = false; r.enemy = nil; r.foes = [] }
        return nil
    }
}

/// 12.2.1: a player forged the Mountainbreaker at the menu's Blacksmith and
/// it vanished: winning a run that started before the forge saved the run's
/// bag over the saved items.
final class MountainbreakerKeepTests: XCTestCase {
    func testWinningARunKeepsAMountainbreakerForgedMeanwhile() {
        let store = MemoryStore()
        Mountainbreaker.addShards(5, store: store)
        var run = Run(character: PlayerCharacter(name: "Bot", cls: "Warrior", race: "Human", prof: "Thief",
                                                 dungeon: "Crypt of Malachar", difficulty: .wanderer))
        GlobalInventory(store: store).load(into: &run)          // the run starts
        XCTAssertTrue(Mountainbreaker.forge(store: store).contains("is yours"))   // forged at the menu meanwhile
        GlobalInventory(store: store).keep(from: run)           // the run wins
        XCTAssertTrue(GlobalInventory(store: store).has(named: "Mountainbreaker"), "The victory saved over the Mountainbreaker")
        XCTAssertFalse(Mountainbreaker.isLost(store: store))
        // Winning again with it carried doesn't make two.
        GlobalInventory(store: store).load(into: &run)
        GlobalInventory(store: store).keep(from: run)
        XCTAssertEqual(GlobalInventory(store: store).items.filter { $0.name == "Mountainbreaker" }.count, 1)
    }

    func testALostMountainbreakerCanBeRecoveredOnce() {
        let store = MemoryStore()
        Mountainbreaker.addShards(5, store: store)
        _ = Mountainbreaker.forge(store: store)
        GlobalInventory(store: store).save([])                  // lost, as in 12.2
        XCTAssertTrue(Mountainbreaker.isLost(store: store))
        XCTAssertFalse(Mountainbreaker.isLost(store: store, alsoCarried: true))
        XCTAssertTrue(Mountainbreaker.recover(store: store).ok)
        let back = GlobalInventory(store: store).items.first { $0.name == "Mountainbreaker" }
        XCTAssertEqual(back?.level, Mountainbreaker.recoveredLevel)
        XCTAssertEqual(Mountainbreaker.memory(back), Mountainbreaker.maxMemory)
        XCTAssertFalse(Mountainbreaker.recover(store: store).ok, "Recovered twice")
    }
}
