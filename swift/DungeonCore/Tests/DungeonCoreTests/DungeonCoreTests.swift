import XCTest
@testable import DungeonCore

// Expected numbers below were worked out by hand from the web version's
// formulas, so these tests catch any drift between the two versions.

final class JSCompatTests: XCTestCase {
    func testRoundMatchesJavaScript() {
        XCTAssertEqual(jsRound(2.5), 3)
        XCTAssertEqual(jsRound(-2.5), -2)
        XCTAssertEqual(jsRound(39.6), 40)
        XCTAssertEqual(jsRound(79.2), 79)
    }

    func testParseIntMatchesJavaScript() {
        XCTAssertEqual(jsParseInt("250"), 250)
        XCTAssertEqual(jsParseInt("12abc"), 12)
        XCTAssertEqual(jsParseInt("  -7"), -7)
        XCTAssertNil(jsParseInt("abc"))
        XCTAssertNil(jsParseInt(nil))
    }
}

final class WalletTests: XCTestCase {
    func testGoldAndAchievements() {
        let store = MemoryStore()
        var earned: [String] = []
        let w = Wallet(store: store) { earned.append($0) }
        w.addGold(350)
        XCTAssertEqual(w.gold, 350)
        XCTAssertEqual(store.getItem("dd_global_gold"), "350")
        XCTAssertEqual(earned, ["ach-gold-hoarder"])
        XCTAssertFalse(w.spendGold(400))
        XCTAssertTrue(w.spendGold(100))
        XCTAssertEqual(w.gold, 250)
        XCTAssertEqual(store.getItem("dd_total_gold_spent"), "100")
        XCTAssertEqual(store.getItem("dd_total_gold_ever"), "350")
    }

    func testReadsWebSaveValuesAndClampsBadOnes() {
        XCTAssertEqual(Wallet(store: MemoryStore(["dd_global_gold": "-40"])).gold, 0)
        XCTAssertEqual(Wallet(store: MemoryStore(["dd_global_gold": "oops"])).gold, 0)
        XCTAssertEqual(Wallet(store: MemoryStore(["dd_diamonds": "12"])).diamonds, 12)
    }

    func testDiamonds() {
        let w = Wallet(store: MemoryStore())
        w.addDiamonds(10)
        w.addDiamonds(-5)
        XCTAssertEqual(w.diamonds, 10)
        XCTAssertTrue(w.spendDiamonds(5))
        XCTAssertFalse(w.spendDiamonds(6))
        XCTAssertEqual(w.diamonds, 5)
    }
}

final class CharacterTests: XCTestCase {
    /// A character as the web version saves it, including fields Swift doesn't model yet.
    let webSave = """
    [{"name":"Lyra","cls":"Paladin","race":"Elf","prof":"Gravedigger","dungeon":"Crypt of Malachar",
      "difficulty":"Ironblood","floor":10,"created":1729870000000,"runMode":"classic",
      "lastSpirit":"ember-fox","corruptionMode":false,"corruption":0,"hunterMode":false,
      "hardcoreMode":false,"guidePersonality":"grim","guideEnabled":true,"earnedSpirits":["frost"],
      "levelCap":10,"completed":true,"backstory":{"id":"orphan","bonus":2},
      "deathLog":[{"floor":4,"killedBy":"Crypt Rat"}]}]
    """

    func testLoadsWebSaveAndKeepsUnknownFields() throws {
        let store = MemoryStore(["dd_chars": webSave])
        let roster = CharacterRoster(store: store)
        XCTAssertEqual(roster.characters.count, 1)
        let ch = roster.characters[0]
        XCTAssertEqual(ch.name, "Lyra")
        XCTAssertEqual(ch.difficultyLevel, .ironblood)
        XCTAssertEqual(ch.floor, 10)
        XCTAssertTrue(ch.completed)
        XCTAssertEqual(ch.extra["earnedSpirits"], .array([.string("frost")]))

        roster.save()
        let reloaded = CharacterRoster(store: store).characters[0]
        XCTAssertEqual(reloaded, ch)
        XCTAssertEqual(reloaded.extra["backstory"], .object(["id": .string("orphan"), "bonus": .number(2)]))
    }

    func testNewCharacterDefaults() {
        let classic = PlayerCharacter(name: "Kael", cls: "Warrior", race: "Human", prof: "Thief",
                                dungeon: "Crypt of Malachar", difficulty: .wanderer)
        XCTAssertEqual(classic.levelCap, 10)
        XCTAssertNil(classic.dungeonTier)
        let legacy = PlayerCharacter(name: "Kael", cls: "Warrior", race: "Human", prof: "Thief",
                               dungeon: "Crypt of Malachar", difficulty: .wanderer, runMode: "legacy")
        XCTAssertEqual(legacy.levelCap, 25)
        XCTAssertEqual(legacy.dungeonTier, 1)
    }

    func testNameRule() {
        XCTAssertFalse(PlayerCharacter.isValidName("A"))
        XCTAssertTrue(PlayerCharacter.isValidName("Al"))
        XCTAssertFalse(PlayerCharacter.isValidName(String(repeating: "x", count: 25)))
    }

    func testRosterLimitAndUnlocks() {
        let store = MemoryStore(["dd_chars": webSave])
        let roster = CharacterRoster(store: store)
        XCTAssertEqual(roster.unlockedDungeons(), ["Crypt of Malachar", "The Ashbound Wastes"])
        XCTAssertNotNil(store.getItem("dd_unlocks"))
        for i in 0..<4 {
            XCTAssertNotNil(roster.add(PlayerCharacter(name: "C\(i)", cls: "Monk", race: "Orc", prof: "Thief",
                                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)))
        }
        XCTAssertTrue(roster.isFull)
        XCTAssertNil(roster.add(PlayerCharacter(name: "Extra", cls: "Monk", race: "Orc", prof: "Thief",
                                          dungeon: "Crypt of Malachar", difficulty: .wanderer)))
    }

    func testDeathDeepInDungeonUnlocksNext() {
        let save = #"[{"name":"Z","cls":"Bard","dungeon":"Frosthold Abyss","floor":3,"deathLog":[{"floor":9}]}]"#
        let store = MemoryStore(["dd_chars": save, "dd_unlocks": #"{"The Ashbound Wastes":true,"Frosthold Abyss":true}"#])
        XCTAssertEqual(CharacterRoster(store: store).unlockedDungeons().last, "The Sunken Archives")
    }
}

final class RunTests: XCTestCase {
    func testStartingStats() {
        let ch = PlayerCharacter(name: "Brom", cls: "Sentinel", race: "Dwarf", prof: "Mercenary",
                           dungeon: "Crypt of Malachar", difficulty: .wanderer)
        let run = Run(character: ch, gold: 40)
        XCTAssertEqual(run.maxHp, 145)
        XCTAssertEqual(run.def, 7)
        XCTAssertEqual(run.atk, 5...11)
        XCTAssertEqual(run.lives, 3)
        XCTAssertEqual(run.atkBonus, 3)
        XCTAssertEqual(run.gold, 40)
        XCTAssertEqual(run.floor, 1)
    }

    func testClassWithoutOwnStatsUsesWebDefaults() {
        let ch = PlayerCharacter(name: "Vex", cls: "Arcanist", race: "Gnome", prof: "Herbalist",
                           dungeon: "Crypt of Malachar", difficulty: .forsaken)
        let run = Run(character: ch)
        XCTAssertEqual(run.maxHp, 100)
        XCTAssertEqual(run.atk, 6...12)
        XCTAssertEqual(run.lives, 1)
        XCTAssertEqual(run.potionMult, 2)
    }
}

final class EnemyScalingTests: XCTestCase {
    func testNormalEnemyScaling() {
        let golem = Bestiary.crypt.t3.first { $0.name == "Blood Golem" }!
        let e = Enemy.spawn(golem, floor: 7, playerLevel: 3)
        XCTAssertEqual(e.hp, 143)   // 80 × 1.54 × 1.16
        XCTAssertEqual(e.atk, 17...28)
    }

    func testBossScaling() {
        let malachar = Bestiary.crypt.bosses[0]
        let b1 = Enemy.spawnBoss(malachar, playerLevel: 1, playerMaxAtk: 16)
        XCTAssertEqual(b1.hp, 120)
        XCTAssertEqual(b1.phase1Hp, 79)
        XCTAssertEqual(b1.phase2Hp, 40)
        let b5 = Enemy.spawnBoss(malachar, playerLevel: 5, playerMaxAtk: 24)
        XCTAssertEqual(b5.hp, 192)
        XCTAssertEqual(b5.atk, 24...40)
    }

    func testTierByFloor() {
        XCTAssertEqual(Bestiary.crypt.pool(forFloor: 3).count, 8)
        XCTAssertEqual(Bestiary.crypt.pool(forFloor: 4).count, 10)
        XCTAssertEqual(Bestiary.crypt.pool(forFloor: 7).count, 9)
    }
}

final class CombatTests: XCTestCase {
    func makeRun(_ cls: String, _ diff: GameData.Difficulty = .wanderer, prof: String = "Thief") -> Run {
        // No spirit, so the numbers are the bare fight's.
        var r = Run(character: PlayerCharacter(name: "T", cls: cls, race: "Human", prof: prof,
                                 dungeon: "Crypt of Malachar", difficulty: diff))
        r.spirit = nil
        return r
    }

    var shade: Enemy { Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1) }

    func testAttackThenCounter() {
        var run = makeRun("Warrior")
        Combat.begin(&run, against: shade)
        var dice = LoadedDice(rolls: [10, 9], chances: [false])
        let r = Combat.takeTurn(&run, .attack, dice: &dice)
        XCTAssertEqual(r.playerDamage, 10)
        XCTAssertEqual(run.enemy?.hp, 14)
        // raw 9, block capped at floor(9 × 0.6) = 5, Warrior def 3 → blocks 3, takes 6
        XCTAssertEqual(r.enemyDamage, 6)
        XCTAssertEqual(run.hp, 114)
        XCTAssertEqual(r.log, ["You attack for 10 damage.",
                               "Hollow Shade strikes for 9 — you absorb 3. You take 6 damage."])
        XCTAssertEqual(r.announcement, "Hollow Shade dealt 6 damage. Your HP: 114 of 120.")
    }

    func testCrit() {
        var run = makeRun("Warrior")
        Combat.begin(&run, against: shade)
        var dice = LoadedDice(rolls: [10, 4], chances: [true])
        let r = Combat.takeTurn(&run, .attack, dice: &dice)
        XCTAssertTrue(r.crit)
        XCTAssertEqual(r.playerDamage, 18)
        XCTAssertEqual(r.log.first, "CRITICAL HIT! You strike for 18 damage!")
    }

    func testMarkedKillForcesCrit() {
        var run = makeRun("Assassin")
        run.markedKill = true
        Combat.begin(&run, against: shade)
        var dice = LoadedDice(rolls: [10, 4], chances: [false])
        let r = Combat.takeTurn(&run, .attack, dice: &dice)
        XCTAssertTrue(r.crit)
        XCTAssertFalse(run.markedKill)
    }

    func testHeavyMissAndHit() {
        var run = makeRun("Warrior")
        Combat.begin(&run, against: shade)
        var miss = LoadedDice(rolls: [10, 4], chances: [true])
        XCTAssertTrue(Combat.takeTurn(&run, .heavy, dice: &miss).missed)
        var hit = LoadedDice(rolls: [10, 4], chances: [false])
        XCTAssertEqual(Combat.takeTurn(&run, .heavy, dice: &hit).playerDamage, 17)
    }

    func testDefendWithSentinelTrait() {
        var run = makeRun("Sentinel")
        Combat.begin(&run, against: shade)
        var dice = LoadedDice(rolls: [9, 9])
        let r = Combat.takeTurn(&run, .defend, dice: &dice)
        XCTAssertEqual(r.playerDamage, 5)   // round(9 × 0.5)
        // raw 9, block capped at 5, then Sentinel takes 25% less: round(4 × 0.75) = 3
        XCTAssertEqual(r.enemyDamage, 3)
        XCTAssertEqual(run.hp, 142)
    }

    func testDifficultyAndUndeadResistance() {
        var nightmare = makeRun("Wizard", .nightmare)
        Combat.begin(&nightmare, against: shade)
        var d1 = LoadedDice(rolls: [14, 8])
        // raw round(8 × 1.75) = 14, Wizard has no defense
        XCTAssertEqual(Combat.takeTurn(&nightmare, .attack, dice: &d1).enemyDamage, 14)

        var digger = makeRun("Wizard", prof: "Gravedigger")
        Combat.begin(&digger, against: shade)
        var d2 = LoadedDice(rolls: [14, 9])
        // Hollow Shade is undead: round(9 × 0.65) = 6
        XCTAssertEqual(Combat.takeTurn(&digger, .attack, dice: &d2).enemyDamage, 6)
    }

    func testKillSkipsCounter() {
        var run = makeRun("Wizard")
        Combat.begin(&run, against: shade)
        var dice = LoadedDice(rolls: [24], chances: [true])
        let r = Combat.takeTurn(&run, .attack, dice: &dice)
        XCTAssertTrue(r.enemyDied)
        XCTAssertNil(r.enemyDamage)
        XCTAssertFalse(run.inCombat)
        XCTAssertEqual(run.kills, 1)
    }

    func testSeededFightIsRepeatable() {
        func fight(seed: UInt64) -> (Int, Int) {
            var run = makeRun("Warrior")
            var dice = SeededDice(seed: seed)
            Combat.begin(&run, against: Combat.nextEnemy(for: run, dice: &dice))
            while run.inCombat { _ = Combat.takeTurn(&run, .attack, dice: &dice) }
            return (run.hp, run.kills)
        }
        XCTAssertEqual(fight(seed: 42).0, fight(seed: 42).0)
        XCTAssertEqual(fight(seed: 7).1, 1)
    }
}

final class ProgressionTests: XCTestCase {
    func newRun(_ cls: String = "Warrior", race: String = "Human", prof: String = "Thief",
             _ diff: GameData.Difficulty = .wanderer) -> Run {
        // No spirit, so the numbers are the bare fight's.
        var r = Run(character: PlayerCharacter(name: "P", cls: cls, race: race, prof: prof,
                                 dungeon: "Crypt of Malachar", difficulty: diff))
        r.spirit = nil
        return r
    }

    func testLevelUpsCarryXPAndGiveThreePointsPerBatch() {
        var r = newRun()
        // 330 XP: 100 to reach level 2, 220 more to reach level 3, 10 left over
        XCTAssertEqual(Progression.gainXP(&r, 330), 2)
        XCTAssertEqual(r.level, 3)
        XCTAssertEqual(r.xp, 10)
        XCTAssertEqual(r.levelPoints, 3)
    }

    func testPilgrimXPAndLevelCap() {
        var p = newRun(prof: "Pilgrim")
        Progression.gainXP(&p, 90)
        // 90 × 1.15 is 103.49999999999999 in floating point, so JavaScript's
        // Math.round gives 103 — past the 100 needed for level 2, 3 left over
        XCTAssertEqual(p.level, 2)
        XCTAssertEqual(p.xp, 3)
        var capped = newRun()
        Progression.gainXP(&capped, 100_000)
        XCTAssertEqual(capped.level, 10)
    }

    func testSpendingLevelPoints() {
        var r = newRun()
        XCTAssertFalse(Progression.spend(&r, on: .strength))
        r.levelPoints = 2
        r.hp = 50
        XCTAssertTrue(Progression.spend(&r, on: .stamina))
        XCTAssertEqual(r.maxHp, 130)
        XCTAssertEqual(r.hp, 60)
        XCTAssertTrue(Progression.spend(&r, on: .agility))
        XCTAssertEqual(r.critBonus, 0.03, accuracy: 1e-9)
        XCTAssertEqual(r.levelPoints, 0)
    }

    func testKillRewardWithGoblinGold() {
        var r = newRun(race: "Goblin")
        let w = Wallet(store: MemoryStore())
        let shade = Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1)
        var dice = LoadedDice(rolls: [4])
        let reward = Progression.rewardKill(&r, shade, dice: &dice, wallet: w)
        XCTAssertEqual(reward.gold, 5)      // round(4 × 1.25)
        XCTAssertEqual(reward.xp, 15)
        XCTAssertEqual(w.gold, 5)
        XCTAssertEqual(reward.message, "Hollow Shade is defeated! You gain 5 gold and 15 XP.")
    }

    func testTiers() {
        XCTAssertEqual(Progression.tier(of: "Crypt Rat", in: "Crypt of Malachar"), .t1)
        XCTAssertEqual(Progression.tier(of: "Bone Archer", in: "Crypt of Malachar"), .t2)
        XCTAssertEqual(Progression.tier(of: "The Pale Queen", in: "Crypt of Malachar"), .boss)
        XCTAssertEqual(Progression.tier(of: "Blood Golem", in: "Crypt of Malachar"), .t3)
    }

    func testStartBonuses() {
        var robber = newRun(prof: "Grave Robber")
        let w = Wallet(store: MemoryStore())
        robber.applyStartBonuses(wallet: w)
        XCTAssertEqual(robber.gold, 50)
        XCTAssertEqual(w.gold, 50)
        XCTAssertTrue(robber.graveRobberLoot)
        XCTAssertEqual(newRun(race: "Halfling").atk, 6...14)
        XCTAssertEqual(newRun(prof: "Warden").defBonus, 3)
    }

    func testLives() {
        var r = newRun()
        r.hp = 0
        XCTAssertEqual(Progression.handleDeath(&r), .revived(livesLeft: 2))
        XCTAssertEqual(r.hp, 48)
        XCTAssertEqual(Progression.handleDeath(&r), .revived(livesLeft: 1))
        XCTAssertEqual(Progression.handleDeath(&r), .runOver)
        var iron = newRun("Warrior", .ironblood)
        XCTAssertEqual(Progression.handleDeath(&iron), .runOver)
    }
}

final class RoomTests: XCTestCase {
    func testRoomOddsMatchWebVersion() {
        var dice = SeededDice(seed: 2024)
        var counts: [Rooms.Outcome: Int] = [:]
        let n = 200_000
        for _ in 0..<n { counts[Rooms.roll(.wanderer, dice: &dice), default: 0] += 1 }
        XCTAssertEqual(Double(counts[.fight]!) / Double(n), 0.40, accuracy: 0.01)
        XCTAssertEqual(Double(counts[.loot]!) / Double(n), 0.28, accuracy: 0.01)
        XCTAssertEqual(Double(counts[.event]!) / Double(n), 0.32, accuracy: 0.01)
        XCTAssertEqual(Rooms.combatChance(.nightmare), 0.60)
    }
}

final class InventoryTests: XCTestCase {
    func newRun(_ cls: String = "Warrior", prof: String = "Thief") -> Run {
        // No spirit, so the numbers are the bare fight's.
        var r = Run(character: PlayerCharacter(name: "I", cls: cls, race: "Human", prof: prof,
                                       dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.spirit = nil
        return r
    }
    func item(_ name: String) -> Item {
        (ItemTables.cryptShop + ItemTables.cryptLoot).first { $0.name == name }!
    }
    var shade: Enemy { Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1) }

    func testPotionsHealWithHerbalistAndAlchemist() {
        var r = newRun(prof: "Herbalist")
        r.hp = 10
        r.inventory = [item("Health Potion")]
        let out = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.hp, 90)   // 40 × 2
        XCTAssertTrue(r.inventory.isEmpty)
        XCTAssertTrue(out.used)

        var a = newRun("Alchemist")
        _ = ClassTraits.start(&a, classTraits: true)
        a.hp = 1
        a.inventory = [item("Health Potion")]
        _ = Inventory.use(&a, at: 0)
        XCTAssertEqual(a.hp, 81)   // Master Brewer: 40 × 2, +1

        var full = newRun()
        full.inventory = [item("Health Potion")]
        XCTAssertFalse(Inventory.use(&full, at: 0).used)
        XCTAssertEqual(full.inventory.count, 1)
    }

    func testFireAndCursePotionsNeedAnEnemy() {
        var r = newRun()
        r.inventory = [item("Fire Potion"), item("Curse Potion")]
        XCTAssertFalse(Inventory.use(&r, at: 0).used)
        Combat.begin(&r, against: shade)
        let fire = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.enemy?.hp, 24 - 10)   // round(24 × 0.4) = 10
        XCTAssertFalse(fire.enemyDied)
        _ = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.enemy?.currentAtk, 2...5)   // 4…9 halved
    }

    func testBuffsLastThreeTurns() {
        var r = newRun()
        r.inventory = [item("Berserker Draught")]
        _ = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.totalAtkBonus, 4)
        Combat.begin(&r, against: Enemy(name: "Dummy", icon: "", hp: 999, maxHp: 999, atk: 1...1, gold: 0...0))
        var dice = LoadedDice()
        for _ in 0..<3 { _ = Combat.takeTurn(&r, .defend, dice: &dice) }
        XCTAssertEqual(r.totalAtkBonus, 0)
    }

    func testEquipWeaponAndArmor() {
        var r = newRun()
        r.inventory = [item("Battle Axe"), item("Chain Mail")]
        _ = Inventory.equip(&r, at: 0)
        XCTAssertEqual(r.weaponBonus, 10)   // (7 + 13) / 2
        _ = Inventory.equip(&r, at: 0)
        XCTAssertEqual(r.totalDef, 3 + 5)
        XCTAssertTrue(r.inventory.isEmpty)
        r.inventory = [item("Iron Sword")]
        _ = Inventory.equip(&r, at: 0)
        XCTAssertEqual(r.inventory.map(\.name), ["Battle Axe"])
    }

    func testFleeWithSwiftPotionAndFailedFleeGetsCountered() {
        var r = newRun()
        Combat.begin(&r, against: shade)
        r.swiftTurns = 2
        var d = LoadedDice()
        XCTAssertTrue(Combat.takeTurn(&r, .flee, dice: &d).fled)
        XCTAssertNil(r.enemy)

        var r2 = newRun()
        Combat.begin(&r2, against: shade)
        var d2 = LoadedDice(rolls: [5, 9], chances: [false])
        let res = Combat.takeTurn(&r2, .flee, dice: &d2)
        XCTAssertFalse(res.fled)
        XCTAssertEqual(res.enemyDamage, 6)
    }

    func testBossPhaseSkipsCounterAndHitsHarder() {
        var r = newRun("Wizard")
        Combat.begin(&r, against: Enemy.spawnBoss(Bestiary.crypt.bosses[0], playerLevel: 1, playerMaxAtk: 24))
        var d = LoadedDice(rolls: [24], chances: [true])   // crit: round(24 × 1.8) = 43 → 77 HP left
        let res = Combat.takeTurn(&r, .attack, dice: &d)
        XCTAssertEqual(r.enemy?.hp, 77)
        XCTAssertNotNil(res.bossPhaseMessage)
        XCTAssertNil(res.enemyDamage)
        XCTAssertEqual(r.enemy?.atk, 19...31)   // 15…25 × 1.25
        XCTAssertEqual(r.bossPhase, 2)
    }

    func testFirstSearchAlwaysFindsAndSecondIsBlocked() {
        var r = newRun()
        let w = Wallet(store: MemoryStore())
        var d = SeededDice(seed: 9)
        let first = Inventory.search(&r, dice: &d, wallet: w)
        XCTAssertTrue(first.item != nil || first.gold > 0)
        XCTAssertTrue(Inventory.search(&r, dice: &d, wallet: w).message.hasPrefix("You have already searched"))
    }

    func testTrapsAndScholar() {
        var r = newRun()
        r.firstSearchDone = true
        var d = LoadedDice(rolls: [1], chances: [false, true])   // no find, trap: Bone Spike
        let res = Inventory.search(&r, dice: &d, wallet: Wallet(store: MemoryStore()))
        XCTAssertEqual(res.trap, "Bone Spike")
        XCTAssertEqual(r.hp, 100)

        var s = newRun(prof: "Scholar")
        s.firstSearchDone = true
        var d2 = LoadedDice(chances: [false, true])
        XCTAssertEqual(Inventory.search(&s, dice: &d2, wallet: Wallet(store: MemoryStore())).trap, "avoided")
        XCTAssertEqual(s.hp, 120)
    }

    func testShopNightDiscountAndBuying() {
        let potion = item("Health Potion")
        XCTAssertEqual(Inventory.price(potion, hour: 12), 12)
        XCTAssertEqual(Inventory.price(potion, hour: 22), 9)
        var r = newRun()
        let w = Wallet(store: MemoryStore())
        w.addGold(22)
        r.gold = 22
        var entry = Inventory.ShopItem(id: 0, item: item("Greater Potion"))
        XCTAssertTrue(Inventory.buy(&r, &entry, wallet: w, hour: 12).used)
        XCTAssertEqual(w.gold, 0)
        XCTAssertTrue(entry.sold)
        var axe = Inventory.ShopItem(id: 1, item: item("Battle Axe"))
        XCTAssertFalse(Inventory.buy(&r, &axe, wallet: w, hour: 12).used)
        var d = SeededDice(seed: 3)
        XCTAssertEqual(Inventory.shopStock(for: r, dice: &d).count, 4)
    }

    func testLuckPotionFortuneAndPhoenix() {
        var r = newRun()
        r.luckKills = 1
        r.runeFortune = true
        var d = LoadedDice(rolls: [4])
        let reward = Progression.rewardKill(&r, shade, dice: &d, wallet: Wallet(store: MemoryStore()))
        XCTAssertEqual(reward.gold, 10)   // round(4 × 1.25) = 5, doubled
        XCTAssertEqual(r.luckKills, 0)

        var p = newRun()
        p.inventory = [item("Phoenix Feather")]
        p.hp = 0
        XCTAssertEqual(Progression.handleDeath(&p), .phoenix)
        XCTAssertEqual(p.hp, 36)
        XCTAssertEqual(p.lives, 3)
    }

    func testRevealQueuesRooms() {
        var r = newRun()
        var d = SeededDice(seed: 5)
        _ = Inventory.reveal(&r, dice: &d)
        let shown = r.upcomingRooms
        XCTAssertEqual(shown.count, 3)
        XCTAssertEqual(Rooms.next(&r, dice: &d), shown[0])
        XCTAssertEqual(r.upcomingRooms.count, 2)
    }

    func testRunSavesAndLoads() throws {
        var r = newRun()
        r.inventory = [item("Health Potion")]
        Combat.begin(&r, against: shade)
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(Run.self, from: data)
        XCTAssertEqual(back.inventory, r.inventory)
        XCTAssertEqual(back.enemy, r.enemy)
        XCTAssertEqual(back.hp, r.hp)
    }

    func testGlobalInventoryKeepsGearAndKeepTypes() {
        let store = MemoryStore()
        let g = GlobalInventory(store: store)
        var r = newRun()
        r.inventory = [item("Health Potion"), item("Rune of Strength"), item("Battle Axe"), item("Battle Axe")]
        r.equippedArmor = item("Chain Mail")
        g.keep(from: r)
        XCTAssertEqual(g.items.map(\.name), ["Rune of Strength", "Battle Axe"])
        var next = newRun()
        g.load(into: &next)
        XCTAssertEqual(next.equippedArmor?.name, "Chain Mail")
        XCTAssertEqual(next.inventory.count, 2)
    }

    func testLoadsWebItemWithUnknownFields() throws {
        let json = #"{"name":"Cursed Blade","icon":"🗡️","type":"weapon","atkBase":[9,15],"level":3,"rarityEffect":"cursed","gold":[2,5]}"#
        let it = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
        XCTAssertEqual(it.weaponAttack, 14...20)   // +round(2 × 2.5) = 5
        XCTAssertEqual(it.extra["rarityEffect"], .string("cursed"))
        let again = try JSONDecoder().decode(Item.self, from: JSONEncoder().encode(it))
        XCTAssertEqual(again, it)
    }
}

final class GameContentTests: XCTestCase {
    func testEveryDungeonHasItsTables() {
        for d in GameData.dungeons {
            let e = Bestiary.enemies(for: d)
            XCTAssertFalse(e.t1.isEmpty, d)
            XCTAssertFalse(e.t2.isEmpty, d)
            XCTAssertFalse(e.t3.isEmpty, d)
            XCTAssertFalse(e.bosses.isEmpty, d)
            XCTAssertFalse(ItemTables.loot(for: d).isEmpty, d)
            XCTAssertGreaterThanOrEqual(ItemTables.shop(for: d).count, 4, d)
            XCTAssertFalse(GameContent.shared.dungeon(d).rooms.isEmpty, d)
            XCTAssertNotEqual(Rooms.floorName(1, dungeon: d), "Floor 1", d)
        }
        XCTAssertFalse(Bestiary.enemies(for: "Crypt of Malachar", difficulty: .nightmare).t1.isEmpty)
    }

    func testDungeonSpecificData() {
        XCTAssertEqual(Bestiary.enemies(for: "The Ashbound Wastes").t1.first?.name, "Cinder Wraith")
        let hound = Bestiary.enemies(for: "The Ashbound Wastes").t1.first { $0.name == "Cinder Hound" }!
        XCTAssertEqual(hound.mechanics["burn"], .number(2))
        XCTAssertEqual(Rooms.floorName(1, dungeon: "The Hollow"), "The Foyer")
        XCTAssertEqual(Rooms.floorName(11, dungeon: "Crypt of Malachar"), "The Hollow Nave")
        XCTAssertEqual(ItemTables.traps(for: "Frosthold Abyss").first?.name, "Ice Blast")
    }

    func testRoomDescriptionsDependOnDepth() {
        var shallow = Run(character: PlayerCharacter(name: "R", cls: "Monk", race: "Elf", prof: "Thief",
                                                     dungeon: "Crypt of Malachar", difficulty: .wanderer))
        var dice = SeededDice(seed: 1)
        let early = Set((0..<200).map { _ in Rooms.description(for: shallow, dice: &dice) })
        shallow.floor = 9
        let deep = Set((0..<200).map { _ in Rooms.description(for: shallow, dice: &dice) })
        XCTAssertTrue(early.isDisjoint(with: deep))
    }
}

final class SkillTests: XCTestCase {
    func newRun(_ cls: String, race: String = "Human") -> Run {
        Run(character: PlayerCharacter(name: "S", cls: cls, race: race, prof: "Thief",
                                       dungeon: "Crypt of Malachar", difficulty: .wanderer))
    }
    var dummy: Enemy { Enemy(name: "Dummy", icon: "", hp: 500, maxHp: 500, atk: 10...10, gold: 1...1) }

    func testEveryClassStartsWithASkillFromItsOwnList() {
        for c in GameData.classes {
            var r = newRun(c.id)
            var d = SeededDice(seed: 1)
            Skills.start(&r, dice: &d)
            XCTAssertEqual(r.unlockedSkills.count, 1, c.id)
            XCTAssertNotNil(Skills.skill(r.unlockedSkills[0], cls: c.id), c.id)
            XCTAssertEqual(r.skillPool.count, Skills.all(for: c.id).count - 1, c.id)
        }
        var w = newRun("Warrior")
        var d = SeededDice(seed: 2)
        Skills.start(&w, dice: &d)
        XCTAssertEqual(w.unlockedSkills, ["shield-bash"])
    }

    func testOfferingAndPickingRemovesTheOthers() {
        var r = newRun("Monk")
        var d = SeededDice(seed: 3)
        Skills.start(&r, dice: &d)
        Skills.offer(&r, dice: &d)
        XCTAssertEqual(r.skillChoices.count, 3)
        let tiers = Set(r.skillChoices.compactMap { Skills.skill($0, cls: "Monk")?.tier })
        XCTAssertEqual(tiers, ["common", "rare", "legendary"])
        let pick = r.skillChoices[1]
        let others = r.skillChoices.filter { $0 != pick }
        Skills.pick(&r, pick)
        XCTAssertTrue(r.unlockedSkills.contains(pick))
        XCTAssertTrue(r.skillChoices.isEmpty)
        for o in others { XCTAssertFalse(r.skillPool.contains(o)) }
    }

    func testDamageSkillThenCounter() {
        var r = newRun("Warrior")
        r.unlockedSkills = ["shield-bash"]
        Combat.begin(&r, against: dummy)
        var d = LoadedDice(rolls: [10, 10])
        let res = Skills.use(&r, "shield-bash", dice: &d)
        XCTAssertEqual(res.playerDamage, 9)          // round(10 × 0.9)
        XCTAssertEqual(r.sp, 12)                     // 20 − 8
        XCTAssertEqual(r.totalDef, 6)                // 3 + 3 this fight
        XCTAssertNotNil(res.enemyDamage)
    }

    func testFreeSkillsSkipTheCounterAndStunsBlockIt() {
        var r = newRun("Paladin")
        r.unlockedSkills = ["lay-on-hands"]
        r.hp = 50
        Combat.begin(&r, against: dummy)
        var d = LoadedDice(rolls: [6])
        let heal = Skills.use(&r, "lay-on-hands", dice: &d)
        XCTAssertEqual(r.hp, 85)
        XCTAssertNil(heal.enemyDamage)

        var n = newRun("Naturalist")
        n.unlockedSkills = ["entangle"]
        Combat.begin(&n, against: dummy)
        var d2 = LoadedDice(rolls: [10])
        XCTAssertNil(Skills.use(&n, "entangle", dice: &d2).enemyDamage)
        XCTAssertEqual(n.hp, n.maxHp)
    }

    func testNotEnoughSPDoesNothing() {
        var r = newRun("Warrior")
        r.unlockedSkills = ["indomitable"]
        Combat.begin(&r, against: dummy)
        var d = LoadedDice()
        let res = Skills.use(&r, "indomitable", dice: &d)
        XCTAssertFalse(res.acted)
        XCTAssertEqual(r.sp, 20)
    }

    func testShieldsDodgesAndDamageOverTime() {
        var r = newRun("Sorcerer")
        r.unlockedSkills = ["mana-shield"]
        Combat.begin(&r, against: dummy)
        var d = LoadedDice(rolls: [10, 10, 10])
        _ = Skills.use(&r, "mana-shield", dice: &d)
        _ = Combat.takeTurn(&r, .defend, dice: &d)
        // The hit is 10, defending blocks 4 (Sorcerer has no defense), the shield takes the other 6.
        XCTAssertEqual(r.hp, 70)
        XCTAssertEqual(r.fight.shield, 19)

        var v = newRun("Naturalist")
        v.unlockedSkills = ["venom"]
        Combat.begin(&v, against: dummy)
        var d2 = LoadedDice(rolls: [10, 10, 10])
        _ = Skills.use(&v, "venom", dice: &d2)
        _ = Combat.takeTurn(&v, .defend, dice: &d2)
        XCTAssertEqual(v.enemy?.dotTurns, 2)
        XCTAssertEqual(v.enemy?.hp, 500 - 5 - 8)     // defend hit (round(10 × 0.5)) + one venom tick
    }

    func testPreviouslyBrokenSkillsNowWork() {
        var r = newRun("Elementalist")
        r.unlockedSkills = ["fireball"]
        Combat.begin(&r, against: dummy)
        var d = LoadedDice(rolls: [10, 10], chances: [false])
        XCTAssertEqual(Skills.use(&r, "fireball", dice: &d).playerDamage, 18)

        var ranger = newRun("Ranger")
        ranger.unlockedSkills = ["aimed-shot"]
        Combat.begin(&ranger, against: dummy)
        var d2 = LoadedDice(rolls: [10, 10])
        XCTAssertEqual(Skills.use(&ranger, "aimed-shot", dice: &d2).playerDamage, 16)
    }

    func testResurrectionAndGnomeDiscount() {
        var r = newRun("Paladin")
        r.resurrection = true
        r.lives = 1
        r.hp = 0
        XCTAssertEqual(Progression.handleDeath(&r), .resurrected)
        XCTAssertEqual(r.hp, 65)
        XCTAssertEqual(r.lives, 1)

        var g = newRun("Warrior", race: "Gnome")
        g.raceTraits = true
        XCTAssertEqual(Skills.cost(Skills.skill("shield-bash", cls: "Warrior")!, g), 6)
    }

    /// Uses every skill of every class against a sturdy enemy, many times over,
    /// to catch crashes, negative HP or stuck states.
    func testEverySkillWorksInAFight() {
        var dice = SeededDice(seed: 77)
        for c in GameData.classes {
            for s in Skills.all(for: c.id) {
                for _ in 0..<5 {
                    var r = newRun(c.id)
                    r.sp = 200; r.maxSp = 200; r.gold = 50; r.kills = 4
                    r.unlockedSkills = Skills.all(for: c.id).map(\.effect)
                    r.lastSkill = "\(Skills.all(for: c.id)[0].effect)"
                    Combat.begin(&r, against: Enemy(name: "Golem", icon: "", hp: 300, maxHp: 300, atk: 5...15, gold: 1...1))
                    _ = Combat.takeTurn(&r, .attack, dice: &dice)
                    let res = Skills.use(&r, s.effect, dice: &dice)
                    XCTAssertTrue(res.acted, "\(c.id)/\(s.effect)")
                    XCTAssertGreaterThanOrEqual(r.hp, 0, "\(c.id)/\(s.effect)")
                    XCTAssertLessThanOrEqual(r.hp, r.maxHp, "\(c.id)/\(s.effect)")
                    if let e = r.enemy { XCTAssertGreaterThanOrEqual(e.hp, 0) }
                    // A few more turns with effects active
                    for _ in 0..<4 where r.inCombat { _ = Combat.takeTurn(&r, .attack, dice: &dice) }
                }
            }
        }
    }
}

final class SoundtrackTests: XCTestCase {
    func testTracksMatchTheWebVersion() {
        XCTAssertEqual(Soundtrack.exploreTrack(dungeon: "Crypt of Malachar", floor: 1), "floor1")
        XCTAssertEqual(Soundtrack.exploreTrack(dungeon: "Crypt of Malachar", floor: 6), "floor3")
        XCTAssertEqual(Soundtrack.exploreTrack(dungeon: "Frosthold Abyss", floor: 5), "frost2")
        XCTAssertEqual(Soundtrack.exploreTrack(dungeon: "The Hollow", floor: 8), "hollow1")
        XCTAssertEqual(Soundtrack.bossTrack(dungeon: "The Abyssal Deep"), "abyssal-boss")
        XCTAssertEqual(Soundtrack.battleTrack(dungeon: "The Ashbound Wastes"), "ash-battle")
        XCTAssertEqual(Soundtrack.ambientKey(dungeon: "The Hollow", difficulty: .nightmare), "nightmare")
        XCTAssertEqual(Soundtrack.enemyCue(dungeon: "The Hollow", boss: false), "sfx-enemy-horror")
    }

    func testEveryTrackTheGameAsksForHasAFile() {
        for d in GameData.dungeons {
            for f in 1...10 { XCTAssertNotNil(Soundtrack.file(forTrack: Soundtrack.exploreTrack(dungeon: d, floor: f)), "\(d) \(f)") }
            XCTAssertNotNil(Soundtrack.file(forTrack: Soundtrack.battleTrack(dungeon: d)), d)
            XCTAssertNotNil(Soundtrack.file(forAmbient: Soundtrack.ambientKey(dungeon: d, difficulty: .wanderer)), d)
        }
        XCTAssertNotNil(Soundtrack.file(forTrack: "menu"))
    }
}

final class EncounterTests: XCTestCase {
    func newRun(_ dungeon: String = "Crypt of Malachar") -> Run {
        Run(character: PlayerCharacter(name: "E", cls: "Warrior", race: "Human", prof: "Thief",
                                       dungeon: dungeon, difficulty: .wanderer))
    }

    func testFloorPlanKeepsFirstAndLastRoomsNormal() {
        var dice = SeededDice(seed: 11)
        var specials = 0, middles = 0
        for _ in 0..<500 {
            var r = newRun()
            r.floorRoomsNeeded = 8
            Encounters.planFloor(&r, dice: &dice)
            XCTAssertEqual(r.roomPlan.count, 8)
            XCTAssertEqual(r.roomPlan.first, "normal")
            XCTAssertEqual(r.roomPlan.last, "normal")
            middles += 6
            specials += r.roomPlan.filter { $0 != "normal" }.count
        }
        // 39% of middle rooms are special in the web version
        XCTAssertEqual(Double(specials) / Double(middles), 0.39, accuracy: 0.03)
    }

    func testSpecialRooms() {
        let store = MemoryStore()
        let w = Wallet(store: store)
        var dice = SeededDice(seed: 4)
        var r = newRun()
        r.floor = 3
        let treasure = Encounters.specialRooms.first { $0.type == "treasure" }!
        let t = Encounters.enterSpecial(treasure, &r, dice: &dice, wallet: w, store: store)
        XCTAssertEqual(t.gold, 35)
        XCTAssertGreaterThanOrEqual(w.gold, 35)

        r.hp = 50
        let rest = Encounters.specialRooms.first { $0.type == "rest" }!
        _ = Encounters.enterSpecial(rest, &r, dice: &dice, wallet: w, store: store)
        XCTAssertEqual(r.hp, 74)   // +20% of 120

        let cursed = Encounters.specialRooms.first { $0.type == "cursed" }!
        let c = Encounters.enterSpecial(cursed, &r, dice: &dice, wallet: w, store: store)
        XCTAssertTrue(c.enemy?.name.hasPrefix("Cursed ") ?? false)

        let merchant = Encounters.specialRooms.first { $0.type == "merchant" }!
        XCTAssertTrue(Encounters.enterSpecial(merchant, &r, dice: &dice, wallet: w, store: store).openShop)
    }

    func testEventsMatchTheirDungeons() {
        var dice = SeededDice(seed: 8)
        var crypt: Set<String> = [], abyss: Set<String> = []
        for _ in 0..<3000 {
            if let e = Encounters.rollEvent(newRun(), dice: &dice) { crypt.insert(e.id) }
            if let e = Encounters.rollEvent(newRun("The Abyssal Deep"), dice: &dice) { abyss.insert(e.id) }
        }
        XCTAssertEqual(crypt, ["julio", "shrine", "chest", "wounded", "inscription"])
        XCTAssertEqual(abyss, ["abyssal-singing", "abyssal-crack", "abyssal-ship", "abyssal-shrine", "abyssal-witness"])
    }

    func testEveryEventChoiceResolves() {
        var dice = SeededDice(seed: 21)
        let w = Wallet(store: MemoryStore())
        w.addGold(100)
        for e in Encounters.events {
            for c in e.choices.indices {
                for _ in 0..<20 {
                    var r = newRun(e.dungeons?.first ?? "Crypt of Malachar")
                    r.gold = 100
                    r.inventory = [Encounters.potion]
                    r.pendingEvent = e.id
                    let out = Encounters.choose(c, &r, dice: &dice, wallet: w)
                    XCTAssertFalse(out.message.isEmpty, "\(e.id) \(c)")
                    XCTAssertNil(r.pendingEvent)
                }
            }
        }
    }

    func testElitesAppearFromFloorFour() {
        var dice = SeededDice(seed: 2)
        var r = newRun()
        r.floor = 3
        XCTAssertFalse((0..<300).contains { _ in Combat.nextEnemy(for: r, dice: &dice).isElite })
        r.floor = 5
        let elites = (0..<1000).filter { _ in Combat.nextEnemy(for: r, dice: &dice).isElite }.count
        XCTAssertEqual(Double(elites) / 1000, 0.15, accuracy: 0.04)
    }

    func testCowardsRunFromHealthyHeroes() {
        var r = newRun()
        let rat = Bestiary.crypt.t1.first { $0.coward }!
        Combat.begin(&r, against: Enemy.spawn(rat, floor: 1, playerLevel: 1))
        var d = LoadedDice(rolls: [1, 2])
        let res = Combat.takeTurn(&r, .defend, dice: &d)
        if !res.enemyDied {
            XCTAssertTrue(res.enemyFled)
            XCTAssertEqual(res.goldGained, 2)
            XCTAssertNil(r.enemy)
        }
    }

    func testImmuneFirstHitAndSpecialMoves() {
        var r = newRun("The Ashbound Wastes")
        let sentinel = Bestiary.enemies(for: "The Ashbound Wastes").t2.first { $0.name == "Pyre Sentinel" }!
        Combat.begin(&r, against: Enemy.spawn(sentinel, floor: 4, playerLevel: 1))
        var d = LoadedDice(rolls: [12, 5])
        XCTAssertEqual(Combat.takeTurn(&r, .attack, dice: &d).playerDamage, 0)
        var d2 = LoadedDice(rolls: [12, 5])
        XCTAssertGreaterThan(Combat.takeTurn(&r, .attack, dice: &d2).playerDamage, 0)

        // Death Knight's Shield Slam ignores defense when it fires
        var k = newRun()
        let dk = Bestiary.crypt.t3.first { $0.name == "Death Knight" }!
        Combat.begin(&k, against: Enemy.spawn(dk, floor: 7, playerLevel: 1))
        var d3 = LoadedDice(rolls: [8, 10], chances: [false, true])
        let res = Combat.takeTurn(&k, .attack, dice: &d3)
        // On floor 7 its hits start at 14; Shield Slam means none of it is blocked
        XCTAssertEqual(res.enemyDamage, 14)
    }
}

final class RarityTests: XCTestCase {
    func newRun() -> Run {
        Run(character: PlayerCharacter(name: "R", cls: "Warrior", race: "Human", prof: "Thief",
                                       dungeon: "Crypt of Malachar", difficulty: .wanderer))
    }
    let axe = Item(id: "axe", name: "Battle Axe", icon: "🪓", type: "weapon", desc: "Heavy.", atkBase: [10, 20], level: 1, isEquippable: true)
    let mail = Item(id: "mail", name: "Chain Mail", icon: "⛓️", type: "armor", desc: "+5.", defBase: 10, level: 1, isEquippable: true)

    func tier(_ id: String) -> Rarity.Tier { Rarity.tiers.first { $0.id == id }! }

    func testDropOddsMatchTheWebTable() {
        var dice = SeededDice(seed: 99)
        var counts: [String: Int] = [:]
        for _ in 0..<100_000 { counts[Rarity.roll(dice: &dice).id, default: 0] += 1 }
        XCTAssertEqual(Double(counts["common"]!) / 100_000, 0.60, accuracy: 0.01)
        XCTAssertEqual(Double(counts["uncommon"]!) / 100_000, 0.25, accuracy: 0.01)
        XCTAssertEqual(Double(counts["rare"]!) / 100_000, 0.10, accuracy: 0.01)
        XCTAssertEqual(Double(counts["epic"]!) / 100_000, 0.04, accuracy: 0.005)
    }

    func testRarityBoostsStatsAndAddsAnEffect() {
        var dice = SeededDice(seed: 1)
        let epic = Rarity.apply(tier("epic"), to: axe, dice: &dice)
        XCTAssertEqual(epic.atkBase, [15, 30])
        XCTAssertTrue(epic.name.hasPrefix("Epic "))
        XCTAssertNotNil(epic.rarityEffect)
        let leg = Rarity.apply(tier("legendary"), to: mail, dice: &dice)
        XCTAssertEqual(leg.defBase, 18)   // round(10 × 1.75)
        XCTAssertTrue(["juggernaut", "unbreakable"].contains(leg.rarityEffect ?? ""))
        XCTAssertEqual(Rarity.apply(tier("common"), to: axe, dice: &dice), axe)
    }

    func withEffect(_ item: Item, _ effect: String) -> Item {
        var i = item
        i.extra["rarityEffect"] = .string(effect)
        return i
    }

    func testWeaponEffects() {
        let dummy = Enemy(name: "D", icon: "", hp: 500, maxHp: 500, atk: 1...1, gold: 1...1)
        var r = newRun()
        r.equippedWeapon = withEffect(axe, "apocalypse")
        Combat.begin(&r, against: dummy)
        var d = LoadedDice(rolls: [10, 1])
        // roll 10 + weapon bonus 15 = 25, × 1.6 = 40
        XCTAssertEqual(Combat.takeTurn(&r, .attack, dice: &d).playerDamage, 40)
        XCTAssertEqual(Skills.cost(Skills.skill("shield-bash", cls: "Warrior")!, r), 0)

        var w = newRun()
        w.equippedWeapon = withEffect(axe, "weighted")
        Combat.begin(&w, against: dummy)
        var d2 = LoadedDice(rolls: [10, 1], chances: [true])
        XCTAssertFalse(Combat.takeTurn(&w, .heavy, dice: &d2).missed)
    }

    func testArmorEffectsAndOncePerFloorSave() {
        var r = newRun()
        r.equippedArmor = withEffect(mail, "unbreakable")
        Combat.begin(&r, against: Enemy(name: "Ogre", icon: "", hp: 500, maxHp: 500, atk: 200...200, gold: 1...1))
        var d = LoadedDice(rolls: [10, 200])
        _ = Combat.takeTurn(&r, .attack, dice: &d)
        XCTAssertEqual(r.hp, 120 - 30)   // capped at 25% of 120

        var s = newRun()
        s.equippedArmor = withEffect(mail, "sanctuary")
        s.hp = 0
        XCTAssertEqual(Progression.handleDeath(&s), .gearSaved)
        XCTAssertEqual(s.hp, 1)
        s.hp = 0
        XCTAssertEqual(Progression.handleDeath(&s), .revived(livesLeft: 2))
    }
}

final class AchievementTests: XCTestCase {
    func book(_ store: MemoryStore = MemoryStore()) -> (AchievementBook, Wallet, MemoryStore) {
        let w = Wallet(store: store)
        return (AchievementBook(store: store, wallet: w), w, store)
    }
    func newRun(_ diff: GameData.Difficulty = .ironblood) -> Run {
        Run(character: PlayerCharacter(name: "A", cls: "Wizard", race: "Elf", prof: "Thief",
                                       dungeon: "Crypt of Malachar", difficulty: diff))
    }

    func testAllAchievementsLoadWithGameCenterIDs() {
        XCTAssertEqual(AchievementBook.all.count, 115)
        XCTAssertEqual(AchievementBook.all.filter { $0.gcId != nil }.count, 100)
    }

    func testFirstKillUnlocksFirstBloodWithItsReward() {
        let (b, w, store) = book()
        var got: [String] = []
        b.onUnlock = { got += $0.map(\.id) }
        let shade = Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1)
        b.record(.enemyKilled(shade, run: newRun()))
        XCTAssertEqual(got, ["ach-first-blood"])
        XCTAssertEqual(b.stat("totalKills"), 1)
        XCTAssertEqual(w.gold, 50)
        XCTAssertEqual(store.getItem("dd_trophies"), "1")
        b.record(.enemyKilled(shade, run: newRun()))
        XCTAssertEqual(got, ["ach-first-blood"])   // only once
    }

    func testVictoryStats() {
        let (b, _, store) = book()
        b.record(.runWon(newRun(.ironblood), diedThisRun: false, seconds: 300))
        XCTAssertEqual(b.stat("dungeonsComplete"), 1)
        XCTAssertEqual(b.stat("ironbloodWins"), 1)
        XCTAssertEqual(b.stat("cryptComplete"), 1)
        XCTAssertEqual(b.stat("flawlessRuns"), 1)
        XCTAssertEqual(b.stat("speedRuns"), 1)
        XCTAssertEqual(store.getItem("dd_won_classes"), #"["Wizard"]"#)
        XCTAssertTrue(b.unlockedIDs.contains("ach-dungeon-1"))
        XCTAssertTrue(b.unlockedIDs.contains("ach-ironblood"))
    }

    func testUniqueBossKillsCountEachBossOnce() {
        let (b, _, _) = book()
        let boss = Enemy.spawnBoss(Bestiary.crypt.bosses[0], playerLevel: 1, playerMaxAtk: 10)
        b.record(.enemyKilled(boss, run: newRun()))
        b.record(.enemyKilled(boss, run: newRun()))
        XCTAssertEqual(b.stat("uniqueBossKills"), 1)
    }

    func testImportedUnlocksArePaidOnce() {
        let store = MemoryStore(["dd_achievements": #"["ach-first-blood","ach-dungeon-1"]"#])
        let (b, w, _) = book(store)
        b.payOutstandingRewards()
        XCTAssertEqual(w.gold, 100)
        XCTAssertEqual(b.trophies, 2)
        b.payOutstandingRewards()
        XCTAssertEqual(w.gold, 100)
    }

    func testStoreAndGoldConditions() {
        let store = MemoryStore(["dd_total_sells": "5"])
        let (b, w, _) = book(store)
        w.addGold(1000)
        b.check()
        XCTAssertTrue(b.unlockedIDs.contains("ach-merchant"))
        XCTAssertTrue(b.unlockedIDs.contains("ach-gold-rich"))
    }
}

final class RunModeTests: XCTestCase {
    func hero(hardcore: Bool = false) -> PlayerCharacter {
        PlayerCharacter(name: "H", cls: "Monk", race: "Orc", prof: "Thief", dungeon: "Crypt of Malachar",
                        difficulty: .wanderer, hardcoreMode: hardcore)
    }

    func testHardcoreDiesOnFirstDeathDespiteLives() {
        var r = Run(character: hero(hardcore: true))
        XCTAssertEqual(r.lives, 3)
        r.hp = 0
        XCTAssertEqual(Progression.handleDeath(&r), .runOver)
    }

    func testContinueJourneyCarriesLevel() {
        var ch = hero()
        ch.completed = true
        XCTAssertTrue(ch.continueJourney(level: 6, xp: 120))
        XCTAssertEqual(ch.dungeon, "The Ashbound Wastes")
        XCTAssertFalse(ch.completed)
        let r = Run(character: ch)
        XCTAssertEqual(r.level, 6)
        XCTAssertEqual(r.xp, 120)
        var last = hero()
        last.dungeon = "The Shadow World"
        XCTAssertFalse(last.continueJourney(level: 1, xp: 0))
    }

    func testNewGamePlusMakesEnemiesStronger() {
        var ch = hero()
        ch.startNewGamePlus()
        ch.startNewGamePlus()
        XCTAssertEqual(ch.ngPlusCount, 2)
        let r = Run(character: ch)
        XCTAssertTrue(r.ngPlus)
        let normal = Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1)
        let tough = Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1, ngPlusCount: 2)
        XCTAssertEqual(normal.hp, 24)
        XCTAssertEqual(tough.hp, jsRound(24 * 1.25))   // 1.20 + (2 − 1) × 0.05
    }
}

final class FileStoreTests: XCTestCase {
    func testBatchedWritesReachDisk() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dd_test_\(UUID().uuidString).json")
        let s = FileStore(url: url)
        for i in 0..<100 { s.setItem("dd_global_gold", String(i)) }
        s.flushNow()
        XCTAssertEqual(FileStore(url: url).getItem("dd_global_gold"), "99")
        s.removeItem("dd_global_gold")
        let written = expectation(description: "batched write")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { written.fulfill() }
        wait(for: [written], timeout: 2)
        XCTAssertNil(FileStore(url: url).getItem("dd_global_gold"))
        try? FileManager.default.removeItem(at: url)
    }
}

final class DailyQuestTests: XCTestCase {
    func quests(on day: String, _ store: MemoryStore = MemoryStore()) -> DailyQuests {
        let q = DailyQuests(store: store, calendar: Calendar(identifier: .gregorian))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone.current
        let date = f.date(from: day + " 12:00")!
        q.now = { date }
        return q
    }

    func testSameQuestAllDayAndRotatesByDayOfYear() {
        // 1 January is day 1 → the second quest in the list
        XCTAssertEqual(quests(on: "2026-01-01").quest.id, "dq-kills-10")
        XCTAssertEqual(quests(on: "2026-01-02").quest.id, "dq-kills-20")
        let store = MemoryStore()
        XCTAssertEqual(quests(on: "2026-01-04", store).quest.id, quests(on: "2026-01-04", store).quest.id)
    }

    func testProgressAndCompletionHappenOnce() {
        let q = quests(on: "2026-01-01")   // defeat 10 enemies
        XCTAssertNil(q.report("loot", 5))
        XCTAssertNil(q.report("kills", 9))
        XCTAssertEqual(q.progress, 9)
        XCTAssertEqual(q.report("kills", 3)?.id, "dq-kills-10")
        XCTAssertTrue(q.isComplete)
        XCTAssertNil(q.report("kills", 1))
    }

    func testFloorQuestsUseTheFloorReached() {
        let q = quests(on: "2026-01-04")   // reach floor 8
        XCTAssertEqual(q.quest.type, "floor")
        XCTAssertNil(q.reachedFloor(4, usedPotion: false))
        XCTAssertNotNil(q.reachedFloor(8, usedPotion: true))
    }

    func testUnsupportedQuestDaysMoveToTheNextOne() {
        // Day 15 is the rare-spirit quest, which isn't ported yet
        XCTAssertEqual(quests(on: "2026-01-15").quest.id, "dq-hollow")
    }

    func testRewardPaysGoldAndPotion() {
        let w = Wallet(store: MemoryStore())
        var r = Run(character: PlayerCharacter(name: "Q", cls: "Bard", race: "Elf", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        let q = GameContent.shared.dailyQuests.first { $0.id == "dq-kills-20" }!
        DailyQuests.payReward(q, &r, wallet: w)
        XCTAssertEqual(w.gold, 150)
        XCTAssertEqual(r.inventory.last?.name, "Health Potion")
    }
}

final class DeathLogTests: XCTestCase {
    func testDeathsKeepTheWebFieldsAndTheLastFive() {
        var ch = PlayerCharacter(name: "Ash", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        var r = Run(character: ch, gold: 0)
        r.kills = 7
        r.level = 3
        for f in 1...7 { ch.logDeath(floor: f, killedBy: "Skeleton", run: r) }
        XCTAssertEqual(ch.deaths.count, 5)
        XCTAssertEqual(ch.deaths[0].floor, 7)
        XCTAssertEqual(ch.deaths[0].kills, 7)
        XCTAssertEqual(ch.deaths[0].level, 3)
        XCTAssertEqual(ch.deaths[0].flavor, "The Crypt is silent again. As if you were never there.")
    }

    func testDeletingBuriesTheCharacter() {
        let store = MemoryStore()
        let roster = CharacterRoster(store: store)
        var ch = PlayerCharacter(name: "Bea", cls: "Monk", race: "Elf", prof: "Scholar",
                                 dungeon: "Crypt of Malachar", difficulty: .ironblood)
        ch.logDeath(floor: 4, killedBy: "Ghoul")
        roster.add(ch)
        roster.bury(at: 0)
        XCTAssertTrue(roster.characters.isEmpty)
        let raw = store.getItem("dd_graveyard") ?? ""
        XCTAssertTrue(raw.contains("\"name\":\"Bea\""))
        XCTAssertTrue(raw.contains("\"killedBy\":\"Ghoul\""))
    }
}

final class BackstoryTests: XCTestCase {
    func testOriginBonusesReachTheRun() {
        var ch = PlayerCharacter(name: "Cid", cls: "Warrior", race: "Human", prof: "Scholar",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        ch.extra["backstory"] = .string("true-believer")
        let wallet = Wallet(store: MemoryStore())
        var r = Run(character: ch, gold: 0)
        r.applyStartBonuses(wallet: wallet)
        XCTAssertEqual(r.lives, 4)

        ch.extra["backstory"] = .string("debt-collector")
        r = Run(character: ch, gold: 0)
        r.applyStartBonuses(wallet: wallet)
        XCTAssertEqual(r.gold, 25)
        XCTAssertEqual(wallet.gold, 25)

        ch.extra["backstory"] = .string("last-hope")
        r = Run(character: ch, gold: 0)
        r.applyStartBonuses(wallet: wallet)
        let sp = r.maxSp
        _ = Progression.gainXP(&r, Progression.xpNeeded(atLevel: 1))
        XCTAssertEqual(r.maxSp, sp + 5)
    }
}

final class InfernalUnlockTests: XCTestCase {
    func testInfernalAndAbyssalOpenAtOneHundredTrophies() {
        let store = MemoryStore()
        let roster = CharacterRoster(store: store)
        store.setItem("dd_unlocks", #"{"The Infernal Descent":true}"#)
        XCTAssertFalse(roster.unlockedDungeons().contains("The Infernal Descent"))
        store.setItem("dd_trophies", "100")
        let list = roster.unlockedDungeons()
        XCTAssertTrue(list.contains("The Infernal Descent"))
        XCTAssertTrue(list.contains("The Abyssal Deep"))
        XCTAssertEqual(store.getItem("dd_infernal_unlocked"), "1")
    }
}

final class SavedRunTests: XCTestCase {
    func testOlderSavesStillLoad() throws {
        let ch = PlayerCharacter(name: "Dee", cls: "Monk", race: "Elf", prof: "Thief",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        var r = Run(character: ch)
        r.floor = 6
        r.gold = 77
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
        obj["usedPotion"] = nil
        obj["guardianDone"] = nil
        var fight = try XCTUnwrap(obj["fight"] as? [String: Any])
        fight["shield"] = nil
        obj["fight"] = fight
        let old = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertNil(try? JSONDecoder().decode(Run.self, from: old))
        let back = try XCTUnwrap(Run.decodeSaved(old))
        XCTAssertEqual(back.floor, 6)
        XCTAssertEqual(back.gold, 77)
        XCTAssertFalse(back.usedPotion)
    }

    func testEliteGuardianIsATougherTierThreeEnemy() {
        let ch = PlayerCharacter(name: "Eve", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                 dungeon: "Crypt of Malachar", difficulty: .condemned)
        var r = Run(character: ch)
        r.floor = 10
        var d = SeededDice(seed: 3)
        let e = Combat.eliteGuardian(for: r, dice: &d)
        let base = Bestiary.enemies(for: r.dungeon, difficulty: r.difficulty).t3.first { $0.name == e.name }!
        XCTAssertEqual(e.maxHp, jsRound(Double(base.hp) * 1.5 * 1.15))
        XCTAssertTrue(e.isElite)
        XCTAssertFalse(e.isBoss)
    }
}

final class StashTests: XCTestCase {
    func testDeathKeepsGearAndSingletonsOnce() {
        let store = MemoryStore()
        let stash = GlobalInventory(store: store)
        let ch = PlayerCharacter(name: "Fay", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        var r = Run(character: ch)
        let sword = Item(name: "Iron Sword", icon: "🗡️", type: "weapon", desc: "")
        let trap = Item(name: "Soul Trap", icon: "🪤", type: "soul-trap", desc: "")
        let potion = Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "", heal: 40)
        r.inventory = [sword, sword, trap, trap, potion]
        stash.keepOnDeath(from: r)
        stash.keepOnDeath(from: r)
        XCTAssertEqual(stash.items.map(\.name), ["Iron Sword", "Soul Trap"])
    }
}

final class MilestoneTests: XCTestCase {
    func testMilestoneBuffsAndGlobalMax() {
        let ch = PlayerCharacter(name: "Gus", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        var r = Run(character: ch)
        let hp = r.maxHp, def = r.defBonus
        r.applyMilestoneBuffs(["hpUp": 2, "defUp": 1, "atkUp": 1])
        XCTAssertEqual(r.maxHp, hp + 5)
        XCTAssertEqual(r.defBonus, def + 3)

        let store = MemoryStore()
        let book = AchievementBook(store: store, wallet: Wallet(store: store))
        book.setGlobalMax("bestFloor", 4)
        book.setGlobalMax("bestFloor", 2)
        XCTAssertEqual(book.globalStats["bestFloor"], .number(4))
    }
}

final class BossRushTests: XCTestCase {
    private func hero(level: Int) -> PlayerCharacter {
        var ch = PlayerCharacter(name: "Hal", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        ch.persistLevel = level
        return ch
    }

    func testStartingStatsFollowLevelGearAndUpgrades() {
        let info = GameData.classInfo("Warrior")
        let sword = Item(name: "Blade", icon: "🗡️", type: "weapon", desc: "", atkBase: [4, 8])
        let br = BossRush(character: hero(level: 7), weapon: sword, armor: nil, upgrades: ["cu-hp-boost", "cu-sp-boost"])
        XCTAssertEqual(br.maxHp, info.maxHp + 10 + 60)
        XCTAssertEqual(br.atkBonus, (sword.weaponAttack.lowerBound + sword.weaponAttack.upperBound) / 2 + 3)
        XCTAssertEqual(br.maxSp, 32)
        XCTAssertEqual(br.sp, 37)
        XCTAssertEqual(br.potions, 4)
    }

    func testCoinsAtThreeSixAndNineAndAWinIsSaved() {
        var br = BossRush(character: hero(level: 40), weapon: nil, armor: nil, upgrades: [])
        var dice = SeededDice(seed: 9)
        var turns = 0
        while !br.done && turns < 2000 {
            turns += 1
            _ = br.fight(br.hp < br.maxHp / 3 && br.potions > 0 ? .potion : .attack, dice: &dice)
        }
        XCTAssertTrue(br.won)
        XCTAssertEqual(br.coinsEarned, 6)
        let store = MemoryStore()
        BossRushScore.save(BossRushScore(bosses: 9, time: 300, timeStr: "5m 0s", cls: "Warrior", date: "2026-10-26"), store: store)
        BossRushScore.save(BossRushScore(bosses: 4, time: 100, timeStr: "1m 40s", cls: "Monk", date: "2026-10-26"), store: store)
        XCTAssertEqual(BossRushScore.load(store).map(\.bosses), [9, 4])
    }
}

final class RaidTests: XCTestCase {
    func testWavesScaleAndTheLegionClosesWaveFive() {
        var ch = PlayerCharacter(name: "Ivy", cls: "Paladin", race: "Human", prof: "Blacksmith",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        ch.persistLevel = 60
        var dice = SeededDice(seed: 5)
        var raid = Raid(character: ch, weapon: nil, armor: nil, upgrades: ["cu-raid-boost"], hard: false, dice: &dice)
        XCTAssertEqual(raid.potions, 5)
        XCTAssertTrue((5...7).contains(raid.enemies.count))
        var turns = 0
        var sawLegion = false
        while !raid.done && turns < 5000 {
            turns += 1
            if raid.wave == 5, raid.enemies.last?.name == "The Undying Legion" { sawLegion = true }
            _ = raid.fight(raid.hp < raid.maxHp / 3 && raid.potions > 0 ? .potion : .attack, dice: &dice)
        }
        XCTAssertTrue(raid.won)
        XCTAssertTrue(sawLegion)
        XCTAssertGreaterThan(raid.gold, 0)

        let store = MemoryStore()
        let save = RaidSave(store: store)
        XCTAssertEqual(save.recordWin(gold: raid.gold), 1)
        XCTAssertTrue(save.doneToday())
        save.recordWin(gold: 0); save.recordWin(gold: 0)
        XCTAssertEqual(save.recordWin(gold: 0), 2)
    }
}


final class CoinShopTests: XCTestCase {
    private func freshRun() -> Run {
        Run(character: PlayerCharacter(name: "Ivy", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                       dungeon: "Crypt of Malachar", difficulty: .wanderer))
    }

    func testBuyingSpendsCoinsAndKeepsTheRaidSaveInStep() {
        let store = MemoryStore(["dd_mystery_coins": "12", "dd_raid": #"{"mysteryCoins":30}"#])
        XCTAssertEqual(CoinShop.coins(store), 30)
        XCTAssertEqual(store.getItem("dd_mystery_coins"), "30")
        let hp = CoinShop.upgrades.first { $0.id == "cu-hp-boost" }!
        XCTAssertTrue(CoinShop.buy(hp, store: store))
        XCTAssertFalse(CoinShop.buy(hp, store: store))
        XCTAssertEqual(CoinShop.coins(store), 15)
        XCTAssertEqual(RaidSave(store: store).coins, 15)
        XCTAssertEqual(CoinShop.owned(store), ["cu-hp-boost"])
        let blade = CoinShop.upgrades.first { $0.id == "cu-void-touched" }!
        XCTAssertFalse(CoinShop.buy(blade, store: store))
        XCTAssertEqual(CoinShop.upgrades.count, 26)
    }

    func testUpgradesApplyAtRunStart() {
        var r = freshRun()
        let hp = r.maxHp, def = r.defBonus, gold = r.gold
        var dice = LoadedDice()
        CoinShop.apply(["cu-hp-boost", "cu-iron-skin", "cu-starting-gold", "cu-alchemist-gift", "cu-trapper",
                        "cu-gamblers-spirit", "cu-void-touched", "cu-second-wind"],
                       to: &r, dice: &dice, wallet: Wallet(store: MemoryStore()))
        XCTAssertEqual(r.maxHp, hp + 10)
        XCTAssertEqual(r.defBonus, def + 2)
        XCTAssertEqual(r.gold, gold + 15)
        XCTAssertEqual(r.inventory.filter { $0.type == "potion" }.count, 2)
        XCTAssertTrue(r.inventory.contains { $0.type == "soul-trap" })
        XCTAssertTrue(r.inventory.contains { $0.type == "gamblers-spirit" })
        XCTAssertTrue(r.inventory.contains { $0.name == "Void Shard" })
        XCTAssertTrue(r.secondWind)
    }

    func testSecondWindThenDeathsBargain() {
        var r = freshRun()
        r.coinUpgrades = ["cu-second-wind", "cu-deaths-bargain"]
        r.secondWind = true
        r.deathsBargain = true
        r.lives = 1
        r.hp = 0
        XCTAssertEqual(Progression.handleDeath(&r), .secondWind)
        XCTAssertEqual(r.hp, 1)
        XCTAssertEqual(r.lives, 1)
        r.enemy = Enemy(name: "Rat", icon: "🐀", hp: 500, maxHp: 500, atk: 1...2, gold: 1...2)
        r.hp = 0
        XCTAssertEqual(Progression.handleDeath(&r), .runOver)
        XCTAssertEqual(r.bargainStrike, r.atk.upperBound * 2)
        XCTAssertEqual(r.enemy?.hp, 500 - r.atk.upperBound * 2)
    }

    func testEmberWardSoulSurgeAndAncientKnowledge() {
        var plain = freshRun(), warded = freshRun()
        warded.coinUpgrades = ["cu-ember-ward"]
        let e = Enemy(name: "Rat", icon: "🐀", hp: 500, maxHp: 500, atk: 20...20, gold: 1...2)
        Combat.begin(&plain, against: e)
        Combat.begin(&warded, against: e)
        var d1 = LoadedDice(), d2 = LoadedDice()
        let a = Combat.takeTurn(&plain, .defend, dice: &d1)
        let b = Combat.takeTurn(&warded, .defend, dice: &d2)
        XCTAssertEqual((a.enemyDamage ?? 0) - 2, b.enemyDamage)

        var s = freshRun()
        let skill = Skills.all(for: s.cls).first { $0.spCost > 1 }!
        let before = Skills.cost(skill, s)
        s.coinUpgrades = ["cu-soul-surge"]
        XCTAssertEqual(Skills.cost(skill, s), before - 1)

        var x = freshRun()
        x.coinUpgrades = ["cu-xp-boost"]
        _ = Progression.gainXP(&x, 20)
        XCTAssertEqual(x.xp, 23)
    }
}

final class HighScoreTests: XCTestCase {
    func testScoreAddsUpAndRanks() {
        let store = MemoryStore()
        HighScore.add("enemy_kills", 10, store: store)
        HighScore.add("boss_kills", 500, store: store)
        HighScore.add("enemy_kills", 10, store: store)
        let s = HighScore.load(store)
        XCTAssertEqual(s.total, 520)
        XCTAssertEqual(s.breakdown["enemy_kills"], 20)
        XCTAssertEqual(HighScore.rank(for: s.total).label, "ADVENTURER")
        XCTAssertEqual(HighScore.rank(for: 0).label, "INITIATE")
        XCTAssertEqual(HighScore.rank(for: 250_000).label, "DDDI CERTIFIED")
    }
}

final class AFKTests: XCTestCase {
    private func champion(_ cls: String = "Warrior") -> PlayerCharacter {
        PlayerCharacter(name: "Ivy", cls: cls, race: "Human", prof: "Blacksmith",
                        dungeon: "Crypt of Malachar", difficulty: .wanderer)
    }

    func testRunStartsLikeTheWebVersion() {
        var save = AFKSave(raw: [:])
        save.upgrades = ["afk-hp-boost": 2, "afk-extra-potion": 1, "afk-slow-fight": 1, "afk-iron-will": 1]
        let run = AFKRun(character: champion(), index: 0, save: save, weapon: nil, armor: nil, now: 0)
        XCTAssertEqual(run.maxHp, 1000 + 100 + 200)
        XCTAssertEqual(run.atk, 28)
        XCTAssertEqual(run.potions, 6)
        XCTAssertEqual(run.fightSeconds, 20)
        XCTAssertEqual(run.classPassive, "warrior")
        let wiz = AFKRun(character: champion("Wizard"), index: 0, save: AFKSave(raw: [:]), weapon: nil, armor: nil, now: 0)
        XCTAssertEqual(wiz.maxHp, 800)
        XCTAssertEqual(wiz.atk, jsRound(28 * 1.30))
    }

    func testRunsDescendUntilTheyFallAndSurviveSaving() throws {
        for seed in UInt64(1)...20 {
            var dice = SeededDice(seed: seed)
            var run = AFKRun(character: champion(["Warrior", "Assassin", "Bard", "Wizard"][Int(seed) % 4]), index: 0,
                             save: AFKSave(raw: [:]), weapon: nil, armor: nil, now: 0)
            var t = 0.0
            while run.running && t < 15 * 5000 {
                t += run.fightSeconds
                _ = run.fight(dice: &dice, save: AFKSave(raw: [:]), now: t)
                XCTAssertLessThanOrEqual(run.hp, run.maxHp)
                XCTAssertLessThanOrEqual(run.log.count, 50)
            }
            XCTAssertGreaterThan(run.floor, 10, "seed \(seed)")
            XCTAssertLessThanOrEqual(run.level, 10)
            let back = try JSONDecoder().decode(AFKRun.self, from: JSONEncoder().encode(run))
            XCTAssertEqual(back.floor, run.floor)
            XCTAssertEqual(back.log, run.log)
        }
    }

    func testFightsOwedForTimeAway() {
        var run = AFKRun(character: champion(), index: 0, save: AFKSave(raw: [:]), weapon: nil, armor: nil, now: 1000)
        XCTAssertEqual(run.fightsDue(at: 1014), 0)
        XCTAssertEqual(run.fightsDue(at: 1015), 1)
        XCTAssertEqual(run.fightsDue(at: 1000 + 3600), 240)
        run.running = false
        XCTAssertEqual(run.fightsDue(at: 1000 + 3600), 0)
    }

    func testShopChallengeAndPoints() {
        let store = MemoryStore()
        var save = AFKSave(raw: [:])
        save.totalPoints = 400
        let title = AFKRun.shop.first { $0.id == "afk-title-void" }!
        XCTAssertTrue(save.buy(title, store: store).1)
        XCTAssertFalse(save.buy(title, store: store).1)
        XCTAssertEqual(save.totalPoints, 100)
        XCTAssertEqual(store.getItem("dd_unlocked_titles"), #"["TheEndless"]"#)
        save.save(store)
        XCTAssertEqual(AFKSave.load(store).totalPoints, 100)

        var run = AFKRun(character: champion(), index: 0, save: save, weapon: nil, armor: nil, now: 0)
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        XCTAssertEqual(AFKSave.todaysChallenge(day).id, "defeat-boss")
        XCTAssertNil(save.checkChallenge(&run, date: day))
        run.bossesDefeated = 1
        XCTAssertNotNil(save.checkChallenge(&run, date: day))
        XCTAssertTrue(save.challengeDone(day))
        XCTAssertEqual(save.totalPoints, 180)
        run.points = 37
        run.floor = 42
        save.finish(run)
        XCTAssertEqual(save.totalPoints, 217)
        XCTAssertEqual(save.bestFloor, 42)
    }
}

final class TournamentTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testSeasonsAndCountdown() {
        let oct3 = Tournament.season(date(2026, 10, 3))
        XCTAssertTrue(oct3.active)
        XCTAssertEqual(oct3.key, "season_3_2026")
        XCTAssertEqual(oct3.name, "Autumn 2026")
        XCTAssertEqual(oct3.boss.name, "The Eternal Colossus")
        let oct26 = Tournament.season(date(2026, 10, 26))
        XCTAssertFalse(oct26.active)
        XCTAssertEqual(oct26.daysUntil, 67)
        let feb = Tournament.season(date(2026, 2, 10))
        XCTAssertFalse(feb.active)
        XCTAssertEqual(feb.boss.name, "The Eternal Colossus")
        XCTAssertEqual(Tournament.season(date(2026, 4, 2)).boss.name, "The Void Sovereign")
    }

    func testFightScoresAndBest() {
        let ch = PlayerCharacter(name: "Ivy", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        var fight = Tournament(character: ch, boss: Tournament.bosses[0])
        var dice = SeededDice(seed: 3)
        while !fight.done { _ = fight.act(.heavy, dice: &dice) }
        XCTAssertEqual(fight.score, fight.damageDealt + fight.speedBonus + fight.survivalBonus)
        if !fight.won { XCTAssertEqual(fight.score, fight.damageDealt) }
        let store = MemoryStore()
        let s = Tournament.season(date(2026, 10, 3))
        XCTAssertTrue(Tournament.record(300, season: s, store: store))
        XCTAssertFalse(Tournament.record(200, season: s, store: store))
        XCTAssertEqual(Tournament.best(s, store: store), 300)
    }
}

final class HideAndSeekTests: XCTestCase {
    func testWallsChaseAndEnding() {
        var dice = LoadedDice()
        var hs = HideAndSeek(dice: &dice)
        XCTAssertEqual(hs.distance, 6)
        XCTAssertEqual(hs.move(.north, dice: &dice).outcome, .wall)
        XCTAssertEqual(hs.moves, 0)
        _ = hs.move(.east, dice: &dice)
        XCTAssertEqual(hs.moves, 1)
        XCTAssertEqual(hs.distance, 4)
        XCTAssertTrue(hs.chasing)
        var ended = HideAndSeek.Outcome.none
        for _ in 0..<20 where hs.active {
            ended = hs.move(.east, dice: &dice).outcome
        }
        XCTAssertEqual(ended, .caught)
    }

    func testRunsAlwaysEnd() {
        for seed in UInt64(1)...200 {
            var dice = SeededDice(seed: seed)
            var hs = HideAndSeek(dice: &dice)
            var n = 0
            while hs.active && n < 500 {
                n += 1
                if hs.distance <= 2, dice.chance(0.5) { _ = hs.hide(dice: &dice) }
                else { _ = hs.move(dice.chance(0.5) ? .east : .south, dice: &dice) }
            }
            XCTAssertFalse(hs.active)
        }
    }
}

final class SellTests: XCTestCase {
    func testSellPricesAndCount() {
        XCTAssertEqual(Inventory.sellPrice(Item(name: "P", icon: "", type: "potion", desc: "", heal: 40)), 6)
        XCTAssertEqual(Inventory.sellPrice(Item(name: "W", icon: "", type: "weapon", desc: "", cost: 100, level: 3)), 65)
        XCTAssertEqual(Inventory.sellPrice(Item(name: "A", icon: "", type: "armor", desc: "")), 15)
        var r = Run(character: PlayerCharacter(name: "Ivy", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.inventory = [Item(name: "Ruby", icon: "", type: "gem", desc: "", gold: 30)]
        let store = MemoryStore()
        let gold = r.gold
        XCTAssertEqual(Inventory.sell(&r, at: 0, wallet: Wallet(store: store), store: store), 30)
        XCTAssertEqual(r.gold, gold + 30)
        XCTAssertTrue(r.inventory.isEmpty)
        XCTAssertEqual(store.getItem("dd_total_sells"), "1")
        XCTAssertNil(Inventory.sell(&r, at: 0, wallet: Wallet(store: store), store: store))
    }
}

final class EquipmentDropTests: XCTestCase {
    func testDropsAreScaledGear() {
        var r = Run(character: PlayerCharacter(name: "Ivy", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.floor = 7
        var drops = 0
        var dice = SeededDice(seed: 9)
        for _ in 0..<1000 {
            if let item = Inventory.equipmentDrop(&r, dice: &dice) {
                drops += 1
                XCTAssertTrue(item.isWeapon || item.isArmor)
                XCTAssertEqual(item.level, 3)
            }
        }
        XCTAssertGreaterThan(drops, 100)
        XCTAssertLessThan(drops, 200)
        XCTAssertEqual(r.inventory.count, drops)
    }
}

final class HomeTests: XCTestCase {
    func newRun() -> Run {
        Run(character: PlayerCharacter(name: "Ivy", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                       dungeon: "Crypt of Malachar", difficulty: .wanderer))
    }

    func testBuyHomeBedAndSafe() {
        let store = MemoryStore(["dd_global_gold": "600"])
        let w = Wallet(store: store)
        XCTAssertTrue(Home.buyHome(store: store, wallet: w))
        XCTAssertTrue(Home.owned(store))
        XCTAssertEqual(w.gold, 100)
        XCTAssertTrue(Home.buyBed(store: store, wallet: w))
        XCTAssertFalse(Home.buyBed(store: store, wallet: w))
        XCTAssertTrue(Home.deposit(20, store: store, wallet: w))
        XCTAssertEqual(Home.safe(store), 20)
        XCTAssertFalse(Home.withdraw(21, store: store, wallet: w))
        XCTAssertTrue(Home.withdraw(5, store: store, wallet: w))
        XCTAssertEqual(w.gold, 10)
    }

    func testSleepNeedsFiveRoomsAndDreamBuffsNextRun() {
        let store = MemoryStore()
        var r = newRun()
        var dice = SeededDice(seed: 3)
        r.hp = 1
        r.totalRooms = 4
        XCTAssertNil(Home.sleep(&r, store: store, dice: &dice))
        r.totalRooms = 5
        XCTAssertNotNil(Home.sleep(&r, store: store, dice: &dice))
        XCTAssertEqual(r.hp, r.maxHp)
        XCTAssertEqual(Home.roomsBeforeSleep(r, store: store), 5)
        var next = newRun()
        let atk = next.atkBonus
        XCTAssertNotNil(Home.applyDream("warriors-dream", to: &next))
        XCTAssertEqual(next.atkBonus, atk + 3)
        XCTAssertNil(Home.applyDream("void-lore", to: &next))
    }

    func testSkillUpgradeCostsAndCooldown() {
        let store = MemoryStore(["dd_global_gold": "5000"])
        let w = Wallet(store: store)
        XCTAssertEqual(Home.upgradeSkill(cls: "Warrior", name: "Shield Bash", store: store, wallet: w, now: 0), "Shield Bash upgraded to level 2.")
        XCTAssertEqual(w.gold, 4920)
        XCTAssertEqual(Home.skillLevels(store)["Warrior_Shield_Bash"], 2)
        for _ in 0..<4 { _ = Home.upgradeSkill(cls: "Warrior", name: "Cleave", store: store, wallet: w, now: 0) }
        XCTAssertEqual(Home.skillCooldownLeft(store, now: 0), 180)
        XCTAssertEqual(Home.upgradeSkill(cls: "Warrior", name: "Cleave", store: store, wallet: w, now: 10), "On cooldown.")
        XCTAssertEqual(Home.upgradeSkill(cls: "Warrior", name: "Cleave", store: store, wallet: w, now: 200), "Cleave is maxed.")
    }

    func testSoulTrapCapturesAndMinionFights() {
        let store = MemoryStore()
        var r = newRun()
        var dice = SeededDice(seed: 5)
        var e = Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1)
        Combat.begin(&r, against: e)
        XCTAssertEqual(Home.capture(&r, store: store), .noTrap)
        r.inventory = [Item(name: "Soul Trap", icon: "🪤", type: "soul-trap", desc: "")]
        guard case .captured(let m) = Home.capture(&r, store: store) else { return XCTFail("not captured") }
        XCTAssertEqual(m.atk, max(1, Int(Double(e.atk.upperBound) * 0.60)))
        XCTAssertTrue(r.inventory.isEmpty)
        XCTAssertNil(r.enemy)
        XCTAssertEqual(r.kills, 1)
        r.inventory = [Item(name: "Soul Trap", icon: "🪤", type: "soul-trap", desc: "")]
        Combat.begin(&r, against: e)
        XCTAssertEqual(Home.capture(&r, store: store), .duplicate)
        XCTAssertEqual(r.inventory.count, 1)
        e.isElite = true
        e.name = "Elite Shade"
        Combat.begin(&r, against: e)
        guard case .captured(let elite) = Home.capture(&r, store: store) else { return XCTFail("not captured") }
        XCTAssertEqual(elite.tier, "elite")
        Home.setActive(m.id, store: store)
        XCTAssertEqual(Home.activeMinion(store)?.name, m.name)
        Home.release(m.id, store: store)
        XCTAssertNil(Home.activeMinion(store))

        // The minion adds its hit to every round.
        var big = Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1)
        big.hp = 10_000
        big.maxHp = 10_000
        Combat.begin(&r, against: big)
        r.minion = Minion(id: "x", name: "Rat", icon: "🐀", atk: 50, tier: "common", capturedOn: 0)
        let t = Combat.takeTurn(&r, .defend, dice: &dice, options: .init())
        XCTAssertTrue(t.log.contains { $0.hasPrefix("👾 Rat attacks for ") })
        XCTAssertLessThanOrEqual(r.enemy!.hp, 10_000 - 50)
    }

    func testBossCannotBeCaptured() {
        let store = MemoryStore()
        var r = newRun()
        Combat.begin(&r, against: Enemy.spawnBoss(Bestiary.crypt.bosses[0], playerLevel: 1, playerMaxAtk: 16))
        r.inventory = [Item(name: "Soul Trap", icon: "🪤", type: "soul-trap", desc: "")]
        XCTAssertEqual(Home.capture(&r, store: store), .boss)
    }
}

final class SubclassTests: XCTestCase {
    func run(_ cls: String) -> Run {
        Run(character: PlayerCharacter(name: "Ivy", cls: cls, race: "Human", prof: "Blacksmith",
                                       dungeon: "Crypt of Malachar", difficulty: .wanderer))
    }

    func testEveryClassHasTwo() {
        // Berserker and Druid have no subclasses in the web version either.
        for cls in GameData.classes.map(\.id) where cls != "Berserker" && cls != "Druid" {
            XCTAssertEqual(Subclasses.options(for: cls).count, 2, cls)
        }
        var b = run("Berserker")
        b.level = 5
        XCTAssertFalse(Subclasses.pending(b))
    }

    func testChoosingAppliesStatsOnce() {
        var r = run("Warrior")
        r.level = 5
        XCTAssertTrue(Subclasses.pending(r))
        let atk = r.atkBonus, hp = r.maxHp, crit = r.critBonus
        XCTAssertFalse(Subclasses.choose(&r, "gladiator").isEmpty)
        XCTAssertEqual(r.atkBonus, atk + 4)
        XCTAssertEqual(r.critBonus, crit + 0.23, accuracy: 0.0001)
        XCTAssertEqual(r.maxHp, hp)
        XCTAssertFalse(Subclasses.pending(r))
        XCTAssertTrue(Subclasses.choose(&r, "warlord").isEmpty)
    }

    func testIroncladCapsAndUndyingSaves() {
        var r = run("Sentinel")
        r.subclass = "ironclad"
        var dice = SeededDice(seed: 1)
        var log: [String] = []
        XCTAssertEqual(Subclasses.incoming(&r, 40, dice: &dice, log: &log), 12)
        var dk = run("DeathKnight")
        dk.subclass = "undying"
        dk.hp = 0
        XCTAssertTrue(Subclasses.cheatDeath(&dk, hpBefore: 5, log: &log))
        XCTAssertEqual(dk.hp, 1)
        dk.hp = 0
        XCTAssertFalse(Subclasses.cheatDeath(&dk, hpBefore: 5, log: &log))
    }

    func testWarlordStreakResetsEachFloor() {
        var r = run("Warrior")
        r.subclass = "warlord"
        var log: [String] = []
        let e = Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1)
        Subclasses.onKill(&r, e, log: &log)
        Subclasses.onKill(&r, e, log: &log)
        XCTAssertEqual(r.warlordAtk, 4)
        var dice = SeededDice(seed: 2)
        _ = Subclasses.onFloor(&r, dice: &dice)
        XCTAssertEqual(r.warlordAtk, 0)
    }

    func testBombOncePerFloor() {
        var r = run("Alchemist")
        r.level = 5
        _ = Subclasses.choose(&r, "bomb-thrower")
        var big = Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1)
        big.hp = 500
        big.maxHp = 500
        Combat.begin(&r, against: big)
        var dice = SeededDice(seed: 4)
        let t = Combat.throwBomb(&r, dice: &dice)
        XCTAssertTrue(t.acted)
        XCTAssertEqual(r.enemy!.hp, 440)
        XCTAssertFalse(Combat.throwBomb(&r, dice: &dice).acted)
    }

    func testHawkeyeHeavyNeverMisses() {
        var r = run("Ranger")
        r.subclass = "hawkeye"
        var dice = SeededDice(seed: 7)
        for _ in 0..<40 {
            var e = Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1)
            e.hp = 10_000
            e.maxHp = 10_000
            Combat.begin(&r, against: e)
            r.hp = r.maxHp
            XCTAssertFalse(Combat.takeTurn(&r, .heavy, dice: &dice).missed)
        }
    }
}

final class SpiritTests: XCTestCase {
    func run(spirit: String?) -> Run {
        var ch = PlayerCharacter(name: "Ivy", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        ch.lastSpirit = spirit
        return Run(character: ch)
    }

    func testDefaultsToEmberFox() {
        XCTAssertEqual(run(spirit: nil).spirit, "ember-fox")
        XCTAssertEqual(run(spirit: "nonsense").spirit, "ember-fox")
        XCTAssertEqual(run(spirit: "stone-turtle").spirit, "stone-turtle")
        XCTAssertEqual(Spirits.available(earned: []).count, 7)
    }

    func testCombatStartEffects() {
        var r = run(spirit: "stone-turtle")
        let log = Combat.begin(&r, against: Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1))
        XCTAssertEqual(r.fight.shield, 15)
        XCTAssertFalse(log.isEmpty)
        // Glacial Wolf's defense lasts one fight, not forever.
        var w = run(spirit: "glacial-wolf")
        w.level = 5
        let def = w.totalDef
        Combat.begin(&w, against: Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1))
        Combat.begin(&w, against: Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1))
        XCTAssertEqual(w.totalDef, def + 4)
    }

    func testRareSleepsUntilLevelFive() {
        var r = run(spirit: "void-wraith")
        var dice = SeededDice(seed: 1)
        var log: [String] = []
        var e = Enemy.spawn(Bestiary.crypt.t1[0], floor: 1, playerLevel: 1)
        e.hp = 1000
        Combat.begin(&r, against: e)
        Spirits.attack(&r, base: 20, dice: &dice, log: &log)
        XCTAssertEqual(r.enemy!.hp, 1000)
        XCTAssertTrue(log.last!.contains("dormant"))
        r.level = 5
        Spirits.attack(&r, base: 20, dice: &dice, log: &log)
        XCTAssertEqual(r.enemy!.hp, 993)
    }

    func testMarketSpriteAndCrow() {
        var r = run(spirit: "market-sprite")
        XCTAssertEqual(Spirits.shopPrice(100, r), 80)
        r.spirit = "shadow-crow"
        XCTAssertEqual(Spirits.shopPrice(100, r), 100)
        var dice = SeededDice(seed: 1)
        var log: [String] = []
        let g = r.gold
        XCTAssertEqual(Spirits.kill(&r, dice: &dice, log: &log), 3)
        XCTAssertEqual(r.gold, g + 3)
    }

    func testRewards() {
        var dice = SeededDice(seed: 1)
        let r = run(spirit: nil)
        XCTAssertEqual(Spirits.victoryReward(r, earned: [], dice: &dice)?.id, "bone-hound-prime")
        XCTAssertNil(Spirits.victoryReward(r, earned: ["bone-hound-prime"], dice: &dice))
        XCTAssertNil(Spirits.eliteReward(earned: Set(Spirits.eliteIds), dice: &dice))
    }
}

final class EventTests: XCTestCase {
    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testCalendar() {
        XCTAssertEqual(Events.active(on: day(2026, 10, 26)), "halloween")
        XCTAssertEqual(Events.active(on: day(2026, 11, 2)), "halloween")
        XCTAssertEqual(Events.active(on: day(2026, 12, 3)), "christmas")
        XCTAssertEqual(Events.active(on: day(2026, 11, 24)), "thanksgiving")
        XCTAssertEqual(Events.active(on: day(2026, 4, 5)), "easter") // Easter Sunday 2026
        XCTAssertEqual(Events.easter(2027).month, 3)
        XCTAssertEqual(Events.easter(2027).day, 28)
        XCTAssertEqual(Events.active(on: day(2026, 3, 13)), "friday13")
        XCTAssertEqual(Events.active(on: day(2026, 7, 4)), "july4")
        XCTAssertEqual(Events.daysLeft("halloween", from: day(2026, 10, 26)), 7)
        XCTAssertEqual(Events.daysUntil("christmas", from: day(2026, 10, 26)), 36)
        XCTAssertFalse(Events.bannerLines(on: day(2026, 10, 26)).isEmpty)
    }

    func testDataAndEnemies() {
        XCTAssertEqual(Events.list.count, 16)
        XCTAssertEqual(Events.enemies("halloween").count, 11) // the Pumpkin King is a boss
        XCTAssertEqual(Events.shop("demonCoins").count, 5)
    }

    func testBonusesApplyInRuns() {
        var r = Run(character: PlayerCharacter(name: "E", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.event = "xpweekend"
        let xp = r.xp
        Progression.gainXP(&r, 10)
        XCTAssertEqual(r.xp - xp, 20)
        r.event = "halloween"
        var dice = SeededDice(seed: 3)
        var seasonal = 0
        for _ in 0..<200 where Combat.nextEnemy(for: r, dice: &dice).mechanics["seasonal"] != nil { seasonal += 1 }
        XCTAssertTrue((20...70).contains(seasonal), "\(seasonal)")
    }

    func testShopAndNextRun() {
        let store = MemoryStore()
        let w = Wallet(store: store)
        Events.addCurrency("demonCoins", 40, store: store)
        let revival = Events.shop("demonCoins").first { $0.id == "demon-revival" }!
        let brew = Events.shop("demonCoins").first { $0.id == "halloween-potion" }!
        XCTAssertNotNil(Events.buy(revival, currency: "demonCoins", store: store, wallet: w))
        XCTAssertNotNil(Events.buy(brew, currency: "demonCoins", store: store, wallet: w))
        XCTAssertNil(Events.buy(revival, currency: "demonCoins", store: store, wallet: w)) // 2 left
        XCTAssertEqual(Events.currency("demonCoins", store: store), 2)
        var r = Run(character: PlayerCharacter(name: "E", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        let lives = r.lives
        XCTAssertEqual(Events.applyNextRun(&r, store: store).count, 2)
        XCTAssertEqual(r.lives, lives + 1)
        XCTAssertTrue(r.inventory.contains { $0.name == "Pumpkin Brew" })
        XCTAssertTrue(Events.applyNextRun(&r, store: store).isEmpty)
    }
}

final class BlacksmithTests: XCTestCase {
    func forge(gold: Int, prof: String? = nil) -> Forge {
        Forge(weapon: Blacksmith.weapons[1], armor: Blacksmith.armors[0], bag: [], gold: gold, prof: prof)
    }

    func testUpgradeCostsAndCap() {
        let store = MemoryStore()
        XCTAssertEqual(Blacksmith.upgradeCost(level: 1, prof: nil, store: store), 40)
        XCTAssertEqual(Blacksmith.upgradeCost(level: 1, prof: "Blacksmith", store: store), 36)
        store.setItem("dd_blacksmith_discount", "{\"pct\":0.10,\"expires\":9999999999999,\"source\":\"Curse Shop\"}")
        XCTAssertEqual(Blacksmith.upgradeCost(level: 2, prof: nil, store: store), 72)
        let s2 = MemoryStore(["dd_global_gold": "100000"])
        let w = Wallet(store: s2)
        var f = forge(gold: 100000)
        for _ in 0..<12 { _ = Blacksmith.upgrade(.armor, &f, wallet: w, store: s2) }
        XCTAssertEqual(f.armor?.level, 10)
        XCTAssertEqual(f.armor?.armorDefense, 3 + 14)
    }

    func testEnchanterPaysFirst() {
        let store = MemoryStore(["dd_global_gold": "0"])
        let w = Wallet(store: store)
        var f = forge(gold: 0)
        var e = Item(name: "Enchanter", icon: "✨", type: "enchanter", desc: "")
        e.extra["charges"] = .number(1)
        f.bag = [e]
        XCTAssertTrue(Blacksmith.upgrade(.weapon, &f, wallet: w, store: store).ok)
        XCTAssertEqual(f.weapon?.level, 2)
        XCTAssertTrue(f.bag.isEmpty)
        XCTAssertFalse(Blacksmith.upgrade(.weapon, &f, wallet: w, store: store).ok)
    }

    func testStarterOnceAndArmorOnce() {
        let store = MemoryStore(["dd_global_gold": "500"])
        let w = Wallet(store: store)
        var f = forge(gold: 500)
        XCTAssertTrue(Blacksmith.buyWeapon(Blacksmith.weapons[0], &f, wallet: w, store: store).ok)
        XCTAssertFalse(Blacksmith.buyWeapon(Blacksmith.weapons[0], &f, wallet: w, store: store).ok)
        XCTAssertTrue(Blacksmith.buyArmor(Blacksmith.armors[1], &f, wallet: w).ok)
        XCTAssertFalse(Blacksmith.buyArmor(Blacksmith.armors[1], &f, wallet: w).ok)
        XCTAssertEqual(f.gold, 420)
        XCTAssertEqual(w.gold, 420)
    }

    func testReforgeNeverStacks() {
        let store = MemoryStore(["dd_global_gold": "100000"])
        let w = Wallet(store: store)
        var f = forge(gold: 100000)
        var dice = SeededDice(seed: 11)
        for _ in 0..<5 { _ = Blacksmith.raiseRarity(&f, wallet: w, dice: &dice) }
        XCTAssertEqual(Blacksmith.rarityIndex(f.weapon!), 5)
        XCTAssertEqual(f.weapon?.name, "Mythic Iron Sword")
        XCTAssertEqual(f.weapon?.atkBase, [11, 22])
        for _ in 0..<30 {
            _ = Blacksmith.reforge(&f, wallet: w, dice: &dice)
            let name = f.weapon!.name
            XCTAssertTrue(name == "Iron Sword" || name.split(separator: " ").count == 3, name)
        }
    }

    func testDurabilityAndRepair() {
        var r = Run(character: PlayerCharacter(name: "B", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.equippedWeapon = Blacksmith.weapons[1]
        var log: [String] = []
        Blacksmith.degrade(&r, by: 61, log: &log)
        XCTAssertEqual(log.count, 1) // Worn
        Blacksmith.degrade(&r, by: 39, log: &log)
        XCTAssertEqual(Blacksmith.damageMultiplier(r), 0.5)
        XCTAssertEqual(Blacksmith.repairCost(r.equippedWeapon), 24)
        r.equippedWeapon = Blacksmith.weapons.last
        XCTAssertEqual(Blacksmith.onFloor(&r), "💔 The Last Blade degrades to level 9.")
    }
}

final class SpireTests: XCTestCase {
    func climber() -> PlayerCharacter {
        PlayerCharacter(name: "S", cls: "Warrior", race: "Human", prof: "Thief", dungeon: "Crypt of Malachar", difficulty: .wanderer)
    }

    func testBossesAppearAndRestFloorsBetween() {
        XCTAssertTrue(Spire.boss(on: 10))
        XCTAssertFalse(Spire.isRest(10))
        XCTAssertTrue(Spire.isRest(20))
        XCTAssertFalse(Spire.isRest(1800))
        let store = MemoryStore()
        let w = Wallet(store: store)
        var r = Spire.start(climber(), store: store, wallet: w)
        XCTAssertEqual(r.floor, 1)
        XCTAssertEqual(r.maxHp, 120 + 150)
        r.floor = 10
        var dice = SeededDice(seed: 1)
        _ = Spire.enter(&r, store: store, wallet: w, dice: &dice)
        XCTAssertEqual(r.enemy?.name, "The Gate Warden")
        XCTAssertTrue(r.enemy!.isBoss)
    }

    func testClimbSavesBestAndPaysOnce() {
        let store = MemoryStore()
        let w = Wallet(store: store)
        var r = Spire.start(climber(), store: store, wallet: w)
        r.atk = 10_000
        var dice = SeededDice(seed: 4)
        _ = Spire.enter(&r, store: store, wallet: w, dice: &dice)
        let before = w.gold
        _ = Spire.turn(&r, .attack, store: store, wallet: w, dice: &dice)
        XCTAssertTrue(r.cleared)
        XCTAssertEqual(w.gold - before, 4) // 3 + floor 1 × 0.5, once
        for _ in 0..<19 {
            _ = Spire.next(&r, store: store, wallet: w, dice: &dice)
            if !r.cleared { _ = Spire.turn(&r, .attack, store: store, wallet: w, dice: &dice) }
        }
        XCTAssertEqual(r.floor, 20)
        XCTAssertTrue(r.cleared) // rest floor
        XCTAssertEqual(Spire.bestFloor(store), 20)
        // Coming back onto the rest floor heals again but pays no drops twice.
        let diamonds = w.diamonds
        var again = Spire.start(climber(), store: store, wallet: w)
        XCTAssertEqual(again.floor, 20)
        for _ in 0..<20 { _ = Spire.enter(&again, store: store, wallet: w, dice: &dice) }
        XCTAssertEqual(w.diamonds, diamonds)
    }

    func testTimeEaterVictory() {
        let store = MemoryStore()
        let w = Wallet(store: store)
        var r = Spire.start(climber(), store: store, wallet: w)
        r.floor = 1800
        r.atk = 100_000
        var dice = SeededDice(seed: 2)
        _ = Spire.enter(&r, store: store, wallet: w, dice: &dice)
        XCTAssertEqual(r.enemy?.name, "The Time Eater")
        _ = Spire.turn(&r, .attack, store: store, wallet: w, dice: &dice)
        XCTAssertTrue(r.won)
        XCTAssertGreaterThanOrEqual(CoinShop.coins(store), 25)
        XCTAssertEqual(Blacksmith.discount(store).pct, 0.25)
    }

    func testDeathSaves() {
        let store = MemoryStore()
        let w = Wallet(store: store)
        var r = Spire.start(climber(), store: store, wallet: w)
        r.floor = 7
        r.hp = 1
        r.potions = 0
        r.def = -1000
        var dice = SeededDice(seed: 3)
        _ = Spire.enter(&r, store: store, wallet: w, dice: &dice)
        r.enemy?.hp = 1_000_000
        _ = Spire.turn(&r, .defend, store: store, wallet: w, dice: &dice)
        XCTAssertTrue(r.dead)
        XCTAssertEqual(Spire.bestFloor(store), 7)
    }
}

final class ShadowWorldTests: XCTestCase {
    func shadowRun() -> Run {
        var r = Run(character: PlayerCharacter(name: "Sh", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "The Shadow World", difficulty: .wanderer))
        r.spirit = nil
        return r
    }
    func template(_ name: String) -> EnemyTemplate {
        let t = Bestiary.enemies(for: "The Shadow World")
        return (t.t1 + t.t2 + t.t3 + t.elites + t.bosses).first { $0.name == name }!
    }

    func testUnlockAndData() {
        let store = MemoryStore()
        XCTAssertFalse(ShadowWorld.unlocked(store))
        store.setItem("dd_cleared_dungeons", "[\"The Abyssal Deep\"]")
        XCTAssertTrue(ShadowWorld.unlocked(store))
        XCTAssertEqual(Rooms.floorName(1, dungeon: "The Shadow World"), "The Place That Wasn't")
        XCTAssertEqual(Bestiary.enemies(for: "The Shadow World").t1.count, 5)
    }

    func testCorruptionHalvesDamageAndPurgeClears() {
        var r = shadowRun()
        var e = Enemy.spawn(template("Null Fragment"), floor: 1, playerLevel: 1)
        e.hp = 10_000
        e.maxHp = 10_000
        Combat.begin(&r, against: e)
        var dice = SeededDice(seed: 5)
        for _ in 0..<4 { r.hp = r.maxHp; _ = Combat.takeTurn(&r, .defend, dice: &dice) }
        XCTAssertGreaterThanOrEqual(r.shadowCorruption, 3)
        XCTAssertEqual(ShadowWorld.damageMultiplier(r), 0.5)
        r.sp = 10
        XCTAssertTrue(ShadowWorld.purge(&r).hasPrefix("✨"))
        XCTAssertEqual(r.shadowCorruption, 0)
        XCTAssertEqual(r.sp, 6)
    }

    func testTwiceDeadAndEchoBecomesShapeshifter() {
        var r = shadowRun()
        var e = Enemy.spawn(template("The Twice Dead"), floor: 7, playerLevel: 1)
        e.hp = 1
        Combat.begin(&r, against: e)
        r.atkBonus = 500
        var dice = SeededDice(seed: 9)
        let t1 = Combat.takeTurn(&r, .attack, dice: &dice)
        XCTAssertFalse(t1.enemyDied)
        XCTAssertGreaterThan(r.enemy!.hp, 0)
        r.enemy!.hp = 1
        XCTAssertTrue(Combat.takeTurn(&r, .attack, dice: &dice).enemyDied)

        r.floor = 10
        let boss = Combat.nextBoss(for: r, dice: &dice)
        XCTAssertEqual(boss.name, "The Echo")
        Combat.begin(&r, against: boss)
        r.enemy!.hp = 1
        let t2 = Combat.takeTurn(&r, .attack, dice: &dice)
        XCTAssertFalse(t2.enemyDied)
        XCTAssertEqual(r.enemy?.name, "The Shapeshifter")
        XCTAssertTrue(r.inCombat)
    }

    func testShapeshifterPhases() {
        var r = shadowRun()
        var dice = SeededDice(seed: 2)
        let s = Enemy.spawnBoss(template("The Shapeshifter"), playerLevel: 1, playerMaxAtk: r.atk.upperBound)
        Combat.begin(&r, against: s)
        r.enemy!.hp = jsRound(Double(r.enemy!.maxHp) * 0.7)
        XCTAssertNotNil(ShadowWorld.shapeshifterPhase(&r))
        XCTAssertEqual(r.bossPhase, 2)
        r.enemy!.hp = jsRound(Double(r.enemy!.maxHp) * 0.4)
        XCTAssertNotNil(ShadowWorld.shapeshifterPhase(&r))
        XCTAssertEqual(r.enemy!.maxHp, r.hp)
        r.enemy!.hp = 1
        XCTAssertTrue(ShadowWorld.shapeshifterPhase(&r)!.contains("FINAL FORM"))
        XCTAssertEqual(r.enemy!.number("corruptOnHit"), 2)
        _ = dice
    }

    func testLurkerHidesThenCrits() {
        var r = shadowRun()
        var e = Enemy.spawn(template("The Lurker"), floor: 4, playerLevel: 1)
        e.hp = 10_000
        e.maxHp = 10_000
        Combat.begin(&r, against: e)
        var dice = SeededDice(seed: 3)
        let first = Combat.takeTurn(&r, .defend, dice: &dice)
        XCTAssertEqual(first.enemyDamage, 0)
        XCTAssertTrue(first.log.contains { $0.contains("hides") })
        let second = Combat.takeTurn(&r, .defend, dice: &dice)
        XCTAssertTrue(second.log.contains { $0.contains("Critical") })
    }
}

final class AmbushTests: XCTestCase {
    func hero(_ dungeon: String = "Crypt of Malachar") -> Run {
        var r = Run(character: PlayerCharacter(name: "A", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: dungeon, difficulty: .wanderer))
        r.spirit = nil
        r.floor = 7
        return r
    }

    func testEveryoneAttacksAndNextStepsUp() {
        var r = hero()
        var dice = SeededDice(seed: 21)
        let foes = Combat.ambushers(for: r, dice: &dice)
        XCTAssertEqual(foes.count, 3)
        Combat.beginAmbush(&r, foes)
        XCTAssertEqual(r.foes.count, 2)
        r.maxHp = 100_000
        r.hp = 100_000
        // Defending: all three enemies take a turn.
        let t = Combat.takeTurn(&r, .defend, dice: &dice)
        XCTAssertEqual(r.foes.map(\.turnsTaken), [1, 1])
        XCTAssertGreaterThan(t.enemyDamage ?? 0, 0)
        // Killing the target brings the next one up; the fight goes on.
        r.enemy!.hp = 1
        r.atkBonus = 1000
        let k = Combat.takeTurn(&r, .attack, dice: &dice)
        XCTAssertTrue(k.enemyDied)
        XCTAssertTrue(k.ambushContinues)
        XCTAssertNotNil(k.defeated)
        XCTAssertTrue(r.inCombat)
        XCTAssertEqual(r.foes.count, 1)
        XCTAssertEqual(r.kills, 1)
        // The last two.
        r.enemy!.hp = 1
        _ = Combat.takeTurn(&r, .attack, dice: &dice)
        r.enemy!.hp = 1
        let last = Combat.takeTurn(&r, .attack, dice: &dice)
        XCTAssertTrue(last.enemyDied)
        XCTAssertFalse(last.ambushContinues)
        XCTAssertFalse(r.inCombat)
        XCTAssertEqual(r.kills, 3)
    }

    func testRetargetAndFleeClearsAmbush() {
        var r = hero()
        var dice = SeededDice(seed: 4)
        Combat.beginAmbush(&r, Combat.ambushers(for: r, dice: &dice))
        let second = r.foes[0]
        Combat.retarget(&r, to: 0)
        XCTAssertEqual(r.enemy, second)
        r.swiftTurns = 1
        XCTAssertTrue(Combat.takeTurn(&r, .flee, dice: &dice).fled)
        XCTAssertTrue(r.foes.isEmpty)
    }

    func testShadowEchoes() {
        var r = hero("The Shadow World")
        var dice = SeededDice(seed: 8)
        XCTAssertFalse(Combat.ambushers(for: r, dice: &dice).first?.name.hasPrefix("Echo of") ?? false)
        for name in ["The Mimic", "The Drifter"] {
            var e = Enemy.spawn(Bestiary.enemies(for: "The Shadow World").t1.first { $0.name == name }!, floor: 1, playerLevel: 1)
            e.hp = 0
            Combat.begin(&r, against: e)
            _ = Combat.killed(&r, TurnResult())
        }
        let echoes = Combat.ambushers(for: r, dice: &dice)
        XCTAssertEqual(echoes.count, 2)
        XCTAssertTrue(echoes.allSatisfy { $0.name.hasPrefix("Echo of") && $0.number("corruptOnHit") == 1 && $0.hp > 0 })
    }
}

final class StalkerTests: XCTestCase {
    func testChaseEscapeAndCatch() {
        var dice = SeededDice(seed: 3)
        var s = StalkerFloor(dice: &dice)
        s.ex = 4; s.ey = 4
        // Walking north to the edge: it follows but you get out.
        XCTAssertEqual(s.move("north"), .moved)
        XCTAssertEqual(s.move("north"), .escapedOnce)
        XCTAssertEqual(s.escapes, 1)
        XCTAssertEqual(s.px, 2)
        // Walk into it to be caught.
        s.ex = 2; s.ey = 1
        XCTAssertEqual(s.move("north"), .caught)
        XCTAssertLessThan(StalkerFloor(dice: &dice).pan, 1)
    }

    func testRewardsAndFight() {
        let store = MemoryStore()
        let w = Wallet(store: store)
        var r = Run(character: PlayerCharacter(name: "St", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "The Shadow World", difficulty: .wanderer))
        var dice = SeededDice(seed: 1)
        r.stalker = StalkerFloor(dice: &dice)
        let gold = w.gold
        let item = StalkerFloor.escaped(&r, wallet: w, dice: &dice)
        XCTAssertNil(r.stalker)
        XCTAssertEqual(w.gold, gold + 150)
        XCTAssertTrue(item!.isWeapon || item!.isArmor)
        r.stalker = StalkerFloor(dice: &dice)
        let hp = r.hp
        let dmg = StalkerFloor.caught(&r)
        XCTAssertEqual(r.hp, max(1, hp - dmg))
        r.stalker = StalkerFloor(dice: &dice)
        let e = StalkerFloor.fight(&r)
        XCTAssertEqual(e.number("corruptOnHit"), 2)
        XCTAssertNil(r.stalker)
    }
}

final class Room3DTests: XCTestCase {
    /// Every room reachable from the start, doors matching on both sides.
    private func connected(_ g: RoomGraph) -> Bool {
        var seen: Set<String> = ["0,0"]
        var queue = [(0, 0)]
        while let (x, y) = queue.popLast() {
            guard let c = g.cell(x, y) else { return false }
            for d in c.doors {
                guard let n = g.cell(x + d.dx, y + d.dy), n.has(d.opposite) else { return false }
                if seen.insert("\(n.gx),\(n.gy)").inserted { queue.append((n.gx, n.gy)) }
            }
        }
        return seen.count == g.cells.count
    }

    func testGraphsAreConnectedAndSized() {
        for seed in 1...200 {
            var dice = SeededDice(seed: UInt64(seed))
            let need = 5 + seed % 10
            var g = RoomGraph(roomsNeeded: need, dice: &dice)
            XCTAssertEqual(g.cells.count, need + 1)
            XCTAssertEqual(g.unvisited, need)
            XCTAssertTrue(connected(g))
            g.extend(3, dice: &dice)
            XCTAssertEqual(g.cells.count, need + 4)
            XCTAssertTrue(connected(g))
        }
    }

    func testWallsDoorsAndRevisits() {
        var dice = SeededDice(seed: 7)
        var g = RoomGraph(roomsNeeded: 6, dice: &dice)
        let wall = Compass.allCases.first { !g.here.has($0) }!
        XCTAssertEqual(g.move(wall), .wall)
        XCTAssertEqual(g.gx, 0)
        let door = g.here.doors[0]
        XCTAssertEqual(g.move(door), .entered(firstVisit: true))
        XCTAssertEqual(g.lastMove, door)
        XCTAssertEqual(g.move(door.opposite), .entered(firstVisit: false))
        XCTAssertEqual(g.unvisited, 5)
        XCTAssertTrue(g.exitsText.hasPrefix("A door") || g.exitsText.hasPrefix("Doors"))
    }

    func testNeverRunsOutOfRooms() {
        var dice = SeededDice(seed: 2)
        var g = RoomGraph(roomsNeeded: 2, dice: &dice)
        let d = g.here.doors[0]
        _ = g.move(d)
        g.unvisitHere()
        XCTAssertEqual(g.unvisited, 2)
        g.ensureRooms(left: 4, dice: &dice)
        XCTAssertEqual(g.unvisited, 4)
    }

    func testEchoReadsDoorsAndWhatsAhead() {
        var dice = SeededDice(seed: 4)
        let g = RoomGraph(roomsNeeded: 8, dice: &dice)
        let e = g.echo(ahead: .danger)
        XCTAssertEqual(e.open.count + e.walls.count, 4)
        XCTAssertEqual(e.open.count, g.here.doors.count)
        XCTAssertTrue(e.open.allSatisfy { $0.ahead == .danger && $0.depth >= 1 })
        XCTAssertTrue(e.summary.contains("Something dangerous stirs beyond the"))
        var r = Run(character: PlayerCharacter(name: "E", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.roomPlan = ["", "treasure"]
        r.roomsOnFloor = 1
        XCTAssertEqual(RoomGraph.ahead(r), .good)
        r.roomsOnFloor = 5
        XCTAssertNil(RoomGraph.ahead(r))
    }

    func testBetaSwitchAndSettings() {
        let store = MemoryStore()
        XCTAssertFalse(ThreeDMode.isOn(store))
        ThreeDMode.setOn(true, store: store)
        XCTAssertTrue(ThreeDMode.isOn(store))
        store.setItem("dd_3d_settings", #"{"shadows":true}"#)
        let s = ThreeDMode.settings(store)
        XCTAssertTrue(s.shadows)
        XCTAssertTrue(s.minimap)
    }

    func testStalkerStartsFarIn3D() {
        var dice = SeededDice(seed: 5)
        var s = StalkerFloor(dice: &dice, threeD: true)
        XCTAssertEqual(s.side, 7)
        XCTAssertEqual(s.distance, 6)
        XCTAssertFalse(s.creep())
        XCTAssertEqual(s.distance, 5)
        // Escaping sends it back to the far side.
        s.ex = 0; s.ey = 0; s.px = 5; s.py = 3
        XCTAssertEqual(s.move("east"), .escapedOnce)
        XCTAssertEqual(s.px, 3)
        XCTAssertEqual(s.ex, 0)
        XCTAssertEqual(s.ey, 0)
    }
}

final class SpellTests: XCTestCase {
    func fight(_ cls: String = "Wizard", spells: [String] = [], hp: Int = 10_000) -> Run {
        var r = Run(character: PlayerCharacter(name: "Sp", cls: cls, race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.spirit = nil
        r.learnedSpells = spells
        Combat.begin(&r, against: Enemy(name: "Dummy", icon: "🎯", hp: hp, maxHp: hp, atk: 10...10, gold: 1...1))
        return r
    }

    func testShopAndLearning() {
        XCTAssertEqual(Spells.scrolls.count, 48)
        XCTAssertEqual(Set(Spells.scrolls.compactMap(\.spellId)).count, 48)
        var ch = PlayerCharacter(name: "W", cls: "Wizard", race: "Human", prof: "Thief", dungeon: "Crypt of Malachar", difficulty: .wanderer)
        var dice = SeededDice(seed: 1)
        let book = Spells.shop[0]
        XCTAssertEqual(Spells.buy(book, character: &ch, gold: 50, subclass: nil, dice: &dice).0, .tooPoor)
        XCTAssertEqual(Spells.buy(book, character: &ch, gold: 500, subclass: nil, dice: &dice).0, .book)
        XCTAssertTrue(Spells.hasBook(ch))
        // Spell Weaver never fails to learn.
        let frost = Spells.entry("frost-lance")!
        XCTAssertEqual(Spells.buy(frost, character: &ch, gold: 500, subclass: "spell-weaver", dice: &dice).0, .learned)
        XCTAssertEqual(Spells.learned(ch), ["frost-lance"])
        XCTAssertEqual(Spells.buy(frost, character: &ch, gold: 500, subclass: nil, dice: &dice).0, .alreadyKnown)
        // A warrior carries the scroll instead.
        var w = PlayerCharacter(name: "X", cls: "Warrior", race: "Human", prof: "Thief", dungeon: "Crypt of Malachar", difficulty: .wanderer)
        let (res, item) = Spells.buy(frost, character: &w, gold: 500, subclass: nil, dice: &dice)
        XCTAssertEqual(res, .scroll)
        XCTAssertEqual(item?.type, "spell-scroll")
    }

    func testFrostLanceFreezesAndCooldown() {
        var r = fight(spells: ["frost-lance"])
        var dice = SeededDice(seed: 2)
        let res = Spells.cast(&r, "frost-lance", dice: &dice)
        XCTAssertTrue(res.acted)
        XCTAssertGreaterThan(res.playerDamage, 0)
        XCTAssertNil(res.enemyDamage, "casting is a free action")
        XCTAssertEqual(r.spellCooldown, 3)
        XCTAssertFalse(Spells.cast(&r, "frost-lance", dice: &dice).acted)
        let hp = r.hp
        _ = Combat.takeTurn(&r, .defend, dice: &dice)
        XCTAssertEqual(r.hp, hp, "the frozen enemy skips its attack")
        XCTAssertEqual(r.spellCooldown, 2)
    }

    func testShieldsAndPacts() {
        var dice = SeededDice(seed: 3)
        var r = fight(spells: ["blood-shield", "grave-pact", "phantom-step"])
        _ = Spells.cast(&r, "blood-shield", dice: &dice)
        let hp = r.hp
        _ = Combat.takeTurn(&r, .defend, dice: &dice)
        XCTAssertEqual(r.hp, hp)

        r = fight(spells: ["grave-pact"])
        r.enemy!.atk = 500...500
        _ = Spells.cast(&r, "grave-pact", dice: &dice)
        XCTAssertEqual(r.hp, 1)
        let before = r.fight.gravePactHp
        for _ in 0..<3 { _ = Combat.takeTurn(&r, .defend, dice: &dice) }
        XCTAssertGreaterThanOrEqual(r.hp, before, "HP comes back when the pact ends")

        r = fight(spells: ["phantom-step"])
        _ = Spells.cast(&r, "phantom-step", dice: &dice)
        let full = r.hp
        let t = Combat.takeTurn(&r, .attack, dice: &dice)
        XCTAssertEqual(t.playerDamage, 0, "can't attack while intangible")
        XCTAssertEqual(r.hp, full, "the hit passes through")
    }

    func testTimeLordAndShadowStepAndRefusals() {
        var dice = SeededDice(seed: 4)
        var r = fight("TimeMage", spells: ["time-stop"])
        r.subclass = "time-lord"
        _ = Spells.cast(&r, "time-stop", dice: &dice)
        XCTAssertEqual(r.enemy?.stunTurns, 3)
        XCTAssertGreaterThan(r.hp, 0)

        r = fight(spells: ["shadow-step"])
        XCTAssertTrue(Spells.cast(&r, "shadow-step", dice: &dice).fled)
        XCTAssertFalse(r.inCombat)

        r = fight(spells: ["the-last-word", "the-sacrifice"])
        XCTAssertFalse(Spells.cast(&r, "the-last-word", dice: &dice).acted)
        XCTAssertEqual(r.spellCooldown, 0, "a refused spell costs no cooldown")
        let kill = Spells.cast(&r, "the-sacrifice", dice: &dice)
        XCTAssertTrue(kill.enemyDied)
    }

    func testScrollsDropsAndSubclasses() {
        var dice = SeededDice(seed: 5)
        var r = fight("Warrior")
        r.inventory.append(Spells.scrollItem(Spells.entry("soulfire")!))
        let i = r.inventory.count - 1
        let res = Spells.read(&r, at: i, dice: &dice)
        XCTAssertTrue(res.acted)
        XCTAssertFalse(r.inventory.contains { $0.type == "spell-scroll" })
        XCTAssertEqual(r.spellCooldown, 0, "scrolls don't start the cooldown")

        r.subclass = "void-born"
        XCTAssertNotNil(Spells.startingScrolls(&r, dice: &dice))
        XCTAssertEqual(r.inventory.filter { $0.type == "spell-scroll" }.count, 3)

        var w = fight("Arcanist", spells: ["soulfire", "void-bolt"])
        w.subclass = "spell-weaver"
        _ = Spells.cast(&w, "soulfire", dice: &dice)
        XCTAssertEqual(w.spellCooldown, 0, "Spell Weaver casts twice before the cooldown")
        _ = Spells.cast(&w, "void-bolt", dice: &dice)
        XCTAssertEqual(w.spellCooldown, 3)

        var drops = 0
        for _ in 0..<400 { if Spells.drop(&r, dice: &dice) != nil { drops += 1 } }
        XCTAssertTrue((5...40).contains(drops))
    }
}

final class MineTests: XCTestCase {
    func miner(_ cls: String = "Warrior", level: Int = 1) -> MineRun {
        var ch = PlayerCharacter(name: "Digger", cls: cls, race: "Human", prof: "Thief", dungeon: "Crypt of Malachar", difficulty: .wanderer)
        ch.persistLevel = level
        return Mine.start(ch)
    }

    func testStartDigAndCarryLimit() {
        var m = miner(level: 6)
        XCTAssertEqual(m.maxHp, Int(Double(GameData.classInfo("Warrior").maxHp) * 1.2))
        var dice = SeededDice(seed: 1)
        var found = 0, fights = 0
        for _ in 0..<300 {
            if m.inCombat { m.enemy = nil; fights += 1; continue }
            switch Mine.dig(&m, dice: &dice) {
            case .found(let items): found += items.count
            case .handsFull:
                XCTAssertEqual(m.hand.count, Mine.maxCarry)
                if Mine.stash(&m) == 0 { m.hand = [] }
            default: break
            }
            if m.depth < 3 && m.digs > 20 { _ = Mine.descend(&m) }
        }
        XCTAssertGreaterThan(found, 20)
        XCTAssertGreaterThan(fights, 5)
        XCTAssertLessThanOrEqual(m.hand.count, Mine.maxCarry)
        XCTAssertTrue(m.hasChest)
    }

    func testMilestoneBossAndSpecials() {
        var m = miner()
        m.depth = 9
        let boss = Mine.descend(&m)
        XCTAssertEqual(boss?.name, "The Foreman's Ghost")
        XCTAssertTrue(m.inCombat)
        // The Stone Golem shrugs off the first hit.
        m.enemy = Mine.enemies.first { $0.name == "Stone Golem" }
        var dice = SeededDice(seed: 2)
        let t = Mine.act(&m, .attack, dice: &dice)
        XCTAssertTrue(t.log.contains { $0.contains("shrugs off") })
        XCTAssertEqual(m.enemy?.hp, m.enemy?.maxHp)
        // The Vein Horror heals from its hits.
        m.enemy = Mine.enemies.first { $0.name == "Vein Horror" }
        m.enemy!.hp = 10
        m.hp = 1000; m.maxHp = 1000
        m.enemy!.atk = 20...20
        _ = Mine.act(&m, .defend, dice: &dice)
        XCTAssertGreaterThan(m.enemy!.hp, 10)
    }

    func testDefeatLosesHandKeepsChest() {
        var m = miner()
        var dice = SeededDice(seed: 3)
        m.depth = 3
        m.hasChest = true
        m.chest = [Mine.healthPotion]
        m.hand = [Mine.healthPotion]
        m.enemy = Mine.enemies.first { $0.name == "Cave Troll" }
        m.enemy!.atk = 9999...9999
        let t = Mine.act(&m, .defend, dice: &dice)
        XCTAssertTrue(t.playerDied)
        XCTAssertTrue(m.hand.isEmpty)
        let h = Mine.surface(m, defeated: true)
        XCTAssertEqual(h.potions.count, 1)
    }

    func testSurfaceHaulAndParts() {
        var m = miner()
        let gold = Mine.tables[0].1[0], part = Mine.tables[0].1[1], coin = Mine.tables[0].1[3]
        m.hand = [gold, gold, part, coin]
        m.chest = [Mine.tables[2].1[0]]
        let h = Mine.surface(m, defeated: false)
        XCTAssertEqual(h.gold, 30)
        XCTAssertEqual(h.coins, 1)
        XCTAssertEqual(h.diamonds, 2)
        XCTAssertEqual(h.parts["barrel"], 1)
        let store = MemoryStore()
        Mine.storeParts(h, store: store)
        XCTAssertEqual(store.getItem("dd_gun_parts"), #"{"barrel":1}"#)
    }

    func testFightToTheEnd() {
        var dice = SeededDice(seed: 9)
        for seed in 0..<30 {
            var m = miner("Paladin", level: 5)
            m.enemy = Mine.enemies[seed % Mine.enemies.count]
            var turns = 0
            while m.inCombat && turns < 200 {
                let t = Mine.act(&m, turns % 4 == 3 ? .heavy : .attack, dice: &dice)
                if t.playerDied || t.enemyDied { break }
                turns += 1
            }
            XCTAssertLessThan(turns, 200)
        }
    }
}

final class GunTests: XCTestCase {
    func testCraftBuyEquip() {
        let store = MemoryStore()
        let w = Wallet(store: store)
        XCTAssertEqual(Guns.all.count, 13)
        XCTAssertTrue(Guns.craft("musket", store: store).hasPrefix("Not enough parts"))
        for p in ["barrel", "stock", "trigger"] { Guns.addPart(p, store: store) }
        XCTAssertTrue(Guns.craft("musket", store: store).hasPrefix("You crafted"))
        XCTAssertEqual(Guns.partCounts(store)["barrel"], 0)
        XCTAssertEqual(Guns.owned(store), ["musket"])
        XCTAssertTrue(Guns.buy("crossbow", wallet: w, store: store).hasPrefix("Not enough diamonds"))
        w.addDiamonds(20)
        XCTAssertTrue(Guns.buy("crossbow", wallet: w, store: store).hasPrefix("You bought"))
        XCTAssertEqual(w.diamonds, 8)
        Guns.equip("crossbow", store: store)
        XCTAssertEqual(Guns.equipped(store)?.name, "Crossbow")
        Guns.equip("ak47", store: store)
        XCTAssertNil(Guns.equipped(store), "can't equip a gun you don't own")
    }

    func testChargeShootReload() {
        var s = GunState()
        let g = Guns.gun("doublebarrel")!
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(s.pull(g, now: t0), .charged)
        XCTAssertEqual(s.pull(g, now: t0), .fire)
        XCTAssertEqual(s.pull(g, now: t0), .fire)
        XCTAssertEqual(s.pull(g, now: t0), .reloading(16))
        XCTAssertEqual(s.pull(g, now: t0.addingTimeInterval(10)), .reloading(6))
        XCTAssertEqual(s.pull(g, now: t0.addingTimeInterval(16)), .charged)
    }

    func testShotsInFights() {
        var dice = SeededDice(seed: 3)
        var r = Run(character: PlayerCharacter(name: "G", cls: "Warrior", race: "Human", prof: "Thief", dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.spirit = nil
        Combat.begin(&r, against: Enemy(name: "Dummy", icon: "🎯", hp: 1000, maxHp: 1000, atk: 1...1, gold: 1...1))
        let t = Guns.shoot(&r, Guns.gun("sniper")!, dice: &dice)
        XCTAssertTrue((70...100).contains(t.playerDamage))
        XCTAssertNotNil(t.enemyDamage, "the enemy answers a shot")

        var ch = PlayerCharacter(name: "M", cls: "Warrior", race: "Human", prof: "Thief", dungeon: "Crypt of Malachar", difficulty: .wanderer)
        ch.persistLevel = 1
        var m = Mine.start(ch)
        m.enemy = Mine.enemies[0]
        let mt = Mine.shoot(&m, Guns.gun("sniper")!, dice: &dice)
        XCTAssertTrue(mt.enemyDied)

        var drops = 0
        let store = MemoryStore()
        for _ in 0..<1000 { if Guns.drop(store: store, dice: &dice) != nil { drops += 1 } }
        XCTAssertTrue((50...110).contains(drops))
    }
}

final class VoidModeTests: XCTestCase {
    func testWavesCooldownsAndWin() {
        var dice = SeededDice(seed: 11)
        var wins = 0, losses = 0
        for _ in 0..<40 {
            var v = VoidMode()
            var turns = 0
            while !v.won && !v.lost && turns < 500 {
                turns += 1
                if v.waveCleared { _ = v.nextWave(); continue }
                let a: VoidMode.Action = v.hp < 250 && v.drainCooldown == 0 ? .drain
                    : v.shieldCooldown == 0 && v.hp < 350 ? .shield
                    : v.blastCooldown == 0 ? .blast : .strike
                let s = v.act(a, dice: &dice)
                XCTAssertTrue(s.acted)
            }
            XCTAssertLessThan(turns, 500)
            if v.won { wins += 1 } else { losses += 1 }
        }
        XCTAssertGreaterThan(wins, 0)

        var v = VoidMode()
        _ = v.act(.blast, dice: &dice)
        XCTAssertFalse(v.act(.blast, dice: &dice).acted, "blast is on cooldown")
    }

    func testCodes() {
        let store = MemoryStore()
        var dice = SeededDice(seed: 1)
        let code = VoidMode.newCode(store: store, dice: &dice)
        XCTAssertNotNil(VoidMode.prize(for: code))
        let r = RewardCodes.redeem(code, store: store)
        XCTAssertTrue(r.ok)
        XCTAssertFalse(RewardCodes.redeem(code, store: store).ok)
        XCTAssertFalse(RewardCodes.redeem("NOPE", store: store).ok)
        let b = RewardCodes.redeem("ddbd26", store: store)
        XCTAssertEqual(b.gold, 1000)
        XCTAssertTrue(b.sword)
        XCTAssertEqual(Blacksmith.discount(store).pct, 0.15)
        // Every prize is reachable and the 2x XP one sets up the next run.
        var seen = Set<VoidMode.Prize>()
        for _ in 0..<300 { if let p = VoidMode.prize(for: VoidMode.newCode(store: store, dice: &dice)) { seen.insert(p) } }
        XCTAssertEqual(seen.count, VoidMode.Prize.allCases.count)
    }
}

final class VoidReaperTests: XCTestCase {
    func testCycleAndFight() {
        var s = VoidReaper.State()
        let now = 1_000_000_000_000.0
        s.countdownStart = now - 86_400_000
        s.targetWakeDate = now + 86_400_000
        XCTAssertEqual(s.pct(now: now), 50)
        XCTAssertEqual(s.daysLeft(now: now), 1)
        XCTAssertEqual(VoidReaper.transition(s, now: now), .none)
        XCTAssertEqual(VoidReaper.transition(s, now: now + 86_400_001), .wake)
        s.awake = true
        s.awakenedAt = now
        XCTAssertTrue(s.isAwake(now: now + 3_600_000))
        XCTAssertEqual(s.hoursLeft(now: now + 3_600_000), 23)
        XCTAssertEqual(VoidReaper.transition(s, now: now + 25 * 3_600_000), .expire)
        s.currentHp = 20_000
        XCTAssertEqual(s.phase, 2)
        s.defeated = true
        XCTAssertEqual(VoidReaper.transition(s, now: now), .restart)
        let parsed = VoidReaper.State(["currentHp": NSNumber(value: 1234), "awake": true, "lastKiller": "Leo"])
        XCTAssertEqual(parsed.currentHp, 1234)
        XCTAssertEqual(parsed.totalHp, VoidReaper.globalHp)

        var f = VoidReaper.Fight(PlayerCharacter(name: "V", cls: "Warrior", race: "Human", prof: "Thief", dungeon: "Crypt of Malachar", difficulty: .wanderer))
        var dice = SeededDice(seed: 2)
        let full = f.hp
        let hit = VoidReaper.counter(&f, .defend, phase: 1, dice: &dice)
        XCTAssertLessThanOrEqual(hit, 12)
        XCTAssertEqual(f.hp, full - hit)
        XCTAssertNotNil(VoidReaper.heal(&f, phase: 3, dice: &dice))
        XCTAssertEqual(f.potions, 2)
    }

    func testWorldCurseMakesEnemiesStronger() {
        var r = Run(character: PlayerCharacter(name: "C", cls: "Warrior", race: "Human", prof: "Thief", dungeon: "Crypt of Malachar", difficulty: .wanderer))
        var d1 = SeededDice(seed: 5), d2 = SeededDice(seed: 5)
        let plain = Combat.nextEnemy(for: r, dice: &d1)
        r.worldCurse = true
        let cursed = Combat.nextEnemy(for: r, dice: &d2)
        XCTAssertEqual(cursed.hp, jsRound(Double(plain.hp) * 1.5))
    }
}

final class SiegeTests: XCTestCase {
    func testFortressUpgradesAndSave() {
        let store = MemoryStore()
        var f = Siege.load(store)
        XCTAssertEqual(f.maxDurability, 50)
        XCTAssertFalse(Siege.buy("reinforce", &f, gold: 100, minions: []).ok)
        XCTAssertTrue(Siege.buy("reinforce", &f, gold: 1000, minions: []).ok)
        XCTAssertEqual(f.maxDurability, 60)
        let m1 = Minion(id: "a", name: "Rat", icon: "🐀", atk: 6, tier: "common", capturedOn: 0)
        let m2 = Minion(id: "b", name: "Bat", icon: "🦇", atk: 7, tier: "common", capturedOn: 0)
        f.wavePoints = 1000
        XCTAssertTrue(Siege.buy("station", &f, gold: 1000, minions: [m1, m2]).message.hasPrefix("Rat"))
        XCTAssertTrue(Siege.buy("station", &f, gold: 1000, minions: [m1, m2]).message.hasPrefix("Bat"), "the next minion, not the same one")
        XCTAssertFalse(Siege.offered(f, minions: [m1, m2]).contains { $0.id == "station" })
        Siege.save(f, store: store)
        let back = Siege.load(store)
        XCTAssertEqual(back.level, 2)
        XCTAssertEqual(back.stationed.count, 2)
    }

    func testBattlesEnd() {
        var dice = SeededDice(seed: 8)
        var won = 0
        for (i, cls) in ["Warrior", "Paladin", "Wizard", "Berserker"].enumerated() {
            var ch = PlayerCharacter(name: "S\(i)", cls: cls, race: "Human", prof: "Thief", dungeon: "Crypt of Malachar", difficulty: .wanderer)
            ch.persistLevel = 25
            var b = Siege.start(ch, fortress: Siege.Fortress())
            XCTAssertEqual(b.maxHp, jsRound(Double(GameData.classInfo(cls).maxHp) * 1.5))
            var turns = 0
            while !b.won && b.lost == nil && turns < 500 {
                turns += 1
                if b.hp < b.maxHp / 2 && b.potions > 0 { _ = Siege.potion(&b); continue }
                _ = Siege.act(&b, .attack, dice: &dice)
            }
            XCTAssertLessThan(turns, 500)
            if b.won { won += 1 }
            XCTAssertGreaterThanOrEqual(Siege.finish(b).durability, 10)
        }
        XCTAssertGreaterThan(won, 0)
    }
}

final class ChallengeTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testDailyMatchesWeb() {
        // Worked out with the web version's own formula.
        let a = Challenges.daily(date(2026, 10, 28))
        XCTAssertEqual(a.dungeon, "The Hollow")
        XCTAssertEqual(a.mods.map(\.id), ["triple-gold", "double-hp"])
        XCTAssertEqual(a.key, "dd_daily_20261028")
        let b = Challenges.daily(date(2026, 12, 25))
        XCTAssertEqual(b.dungeon, "The Ashbound Wastes")
        XCTAssertEqual(b.mods.map(\.id), ["double-hp", "no-shop"])
    }

    func testEveryGauntletDungeonExists() {
        for d in Challenges.gauntlet { XCTAssertTrue(GameData.dungeons.contains(d), d) }
    }

    func testModifiers() {
        let ch = PlayerCharacter(name: "T", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        var run = Run(character: ch)
        var dice = SeededDice(seed: 7)
        XCTAssertEqual(Challenges.bossFloor(run), 10)
        let plain = Combat.nextBoss(for: run, dice: &dice)
        run.dailyMods = ["double-hp", "early-boss"]
        XCTAssertEqual(Challenges.bossFloor(run), 7)
        XCTAssertEqual(Rooms.roomsNeeded(floor: 7, difficulty: .wanderer, bossFloor: 7, dice: &dice), 1)
        dice = SeededDice(seed: 7)
        let tough = Combat.nextBoss(for: run, dice: &dice)
        XCTAssertEqual(tough.maxHp, plain.maxHp * 2)
        XCTAssertEqual(tough.phase1Hp, plain.phase1Hp * 2)
        run.dailyMods = ["triple-gold", "lucky"]
        XCTAssertEqual(Challenges.gold(10, run), 45)
        run.dailyMods = ["no-potions"]
        run.hp = 1
        run.inventory = [Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "")]
        XCTAssertFalse(Inventory.use(&run, at: 0).used)
        XCTAssertEqual(Challenges.time(247), "4m 07s")
    }
}

final class BountyTests: XCTestCase {
    func testBoardFlow() {
        let store = MemoryStore()
        let wallet = Wallet(store: store) { _ in }
        var dice = SeededDice(seed: 3)
        let now = Date()
        let today = Bounties.today(store, now: now, dice: &dice)
        XCTAssertEqual(today.count, 3)
        XCTAssertEqual(Set(today.map(\.id)).count, 3)
        XCTAssertEqual(Bounties.today(store, now: now, dice: &dice), today, "same three all day")
        XCTAssertTrue(Bounties.refresh(store, now: now, dice: &dice))
        XCTAssertEqual(Bounties.refreshesLeft(store, now: now), 4)

        XCTAssertNotNil(Bounties.register("kill-crypt-wraiths", store: store))
        XCTAssertNil(Bounties.register("kills-10-any", store: store), "one at a time")
        // Wrong dungeon, wrong enemy: nothing.
        XCTAssertNil(Bounties.record(.kill(name: "Wailing Wraith", elite: false, boss: false, dungeon: "The Hollow"), store: store))
        XCTAssertNil(Bounties.record(.kill(name: "Hollow Shade", elite: false, boss: false, dungeon: "Crypt of Malachar"), store: store))
        XCTAssertEqual(Bounties.progress(store), 0)
        for _ in 0..<2 { XCTAssertNil(Bounties.record(.kill(name: "Wailing Wraith", elite: false, boss: false, dungeon: "Crypt of Malachar"), store: store)) }
        let done = Bounties.record(.kill(name: "Elite Wailing Wraith", elite: true, boss: false, dungeon: "Crypt of Malachar"), store: store)
        XCTAssertEqual(done?.id, "kill-crypt-wraiths")
        let gold = wallet.gold
        Bounties.complete(done!, store: store, wallet: wallet)
        XCTAssertEqual(wallet.gold, gold + 200)
        XCTAssertEqual(store.getItem("dd_trophies"), "1")
        XCTAssertNil(Bounties.active(store))
        XCTAssertEqual(Bounties.banner(store), nil)
    }

    func testSingleRunAndNoDeaths() {
        let store = MemoryStore()
        _ = Bounties.register("kills-10-any", store: store)
        for _ in 0..<6 { _ = Bounties.record(.kill(name: "Rat", elite: false, boss: false, dungeon: "The Hollow"), store: store) }
        XCTAssertEqual(Bounties.progress(store), 6)
        _ = Bounties.record(.runStarted, store: store)
        XCTAssertEqual(Bounties.progress(store), 0, "a single run")
        Bounties.abandon(store)
        _ = Bounties.register("floor-5-any", store: store)
        XCTAssertNil(Bounties.record(.floor(5, dungeon: "The Hollow", diedThisRun: true), store: store))
        XCTAssertEqual(Bounties.record(.floor(5, dungeon: "The Hollow", diedThisRun: false), store: store)?.id, "floor-5-any")
    }

    func testDayKeyLooksLikeTheWeb() {
        let d = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!
        XCTAssertEqual(Bounties.dayKey(d), "Thu Oct 08 2026")
    }
}

final class HunterTests: XCTestCase {
    private func hunted() -> Run {
        var ch = PlayerCharacter(name: "H", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        ch.hunterMode = true
        return Run(character: ch)
    }

    func testClosesInAndAsks() {
        var r = hunted()
        XCTAssertEqual(r.hunter?.dist, 10)
        for _ in 0..<7 { _ = Hunter.advance(&r) }
        XCTAssertEqual(Hunter.advance(&r), .choose(2, Hunter.line(2)))
        r.inCombat = true
        XCTAssertEqual(Hunter.advance(&r), .closer(1, Hunter.line(1)), "no choice mid-fight")
        XCTAssertEqual(Hunter.advance(&r), .caught)
    }

    func testFloorsAndPhaseTwo() {
        var r = hunted()
        r.hunter?.dist = 4
        r.floor = 2
        XCTAssertTrue(Hunter.newFloor(&r)!.contains("faster"))
        XCTAssertEqual(r.hunter?.dist, 7)
        XCTAssertEqual(r.hunter?.phase, 2)
        r.hunter?.turns = 0
        _ = Hunter.advance(&r); _ = Hunter.advance(&r); _ = Hunter.advance(&r)
        XCTAssertEqual(r.hunter?.dist, 3, "an extra step every third turn")
        r.hunter?.dist = 9
        _ = Hunter.newFloor(&r)
        XCTAssertEqual(r.hunter?.dist, 10)
    }

    func testCaughtAndSlain() {
        var r = hunted()
        let lives = r.lives
        XCTAssertTrue(Hunter.caught(&r))
        XCTAssertEqual(r.lives, lives - 1)
        XCTAssertEqual(r.hunter?.dist, 8)
        r.lives = 1
        XCTAssertFalse(Hunter.caught(&r))
        XCTAssertEqual(r.lives, 0)
        var s = hunted()
        s.level = 3
        let e = Hunter.enemy(level: 3)
        XCTAssertEqual(e.hp, 120)
        XCTAssertTrue(e.isBoss && Hunter.isHunter(e))
        let got = Hunter.slain(&s)
        XCTAssertEqual(got.xp, 290)
        XCTAssertEqual(got.gold, 145)
        XCTAssertNil(s.hunter)
        XCTAssertEqual(s.inventory.last?.name, "Hunter's Trophy")
    }
}

final class CorruptionTests: XCTestCase {
    private func corrupted(_ c: Int) -> Run {
        var ch = PlayerCharacter(name: "C", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        ch.corruptionMode = true
        ch.corruption = c
        return Run(character: ch)
    }

    func testLivesLostAndThresholds() {
        var r = corrupted(22)
        r.floor = 5
        let got = Corruption.lifeLost(&r)
        XCTAssertEqual(got?.total, 29)
        XCTAssertTrue(got!.lines.contains { $0.contains("whisper") })
        r.corruption = 98
        r.floor = 9
        XCTAssertEqual(Corruption.lifeLost(&r)?.total, 100)
        var off = Run(character: PlayerCharacter(name: "N", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                                 dungeon: "Crypt of Malachar", difficulty: .wanderer))
        XCTAssertNil(Corruption.lifeLost(&off), "only with Corruption Mode on")
    }

    func testEffects() {
        var dice = SeededDice(seed: 11)
        var r = corrupted(100)
        r.floor = 5
        var hunters = 0, backfires = 0
        for _ in 0..<400 {
            if Corruption.hunter(for: r, dice: &dice) != nil { hunters += 1 }
            var t = r
            if Corruption.backfire(&t, skill: "Shield Bash", dice: &dice) != nil {
                backfires += 1
                XCTAssertEqual(t.hp, r.hp - jsRound(Double(r.maxHp) * 0.1))
            }
        }
        XCTAssertTrue((20...70).contains(hunters), "\(hunters)")
        XCTAssertTrue((30...100).contains(backfires), "\(backfires)")
        XCTAssertEqual(Corruption.goldMult(r), 2)
        let prize = Corruption.bossPrize(&r, dice: &dice)
        XCTAssertNotNil(prize)
        XCTAssertTrue(prize!.name.contains("Legendary") || prize!.extra["rarity"] == .string("legendary") || prize!.desc.contains("Legendary"), prize!.name)
        let low = corrupted(40)
        for _ in 0..<200 { XCTAssertNil(Corruption.hunter(for: low, dice: &dice)) }
    }
}

final class GuideTests: XCTestCase {
    func testEveryPersonalityHasEveryMoment() {
        var dice = SeededDice(seed: 5)
        let moments: [Guide.Moment] = [.dungeonStart, .levelUp, .lowHp, .bossEncounter, .victory, .death, .achievement, .hunterClose]
        for p in Guide.personalities {
            for m in moments {
                let l = Guide.line(m, personality: p, level: 7, dice: &dice)
                XCTAssertNotNil(l, "\(p) \(m)")
                XCTAssertFalse(l!.contains("{lvl}"))
            }
        }
        XCTAssertEqual(Guide.name(MemoryStore()), "Mira")
        XCTAssertEqual(Guide.name(MemoryStore(["dd_companion_name": "Rook"])), "Rook")
    }
}

final class ShadowEventTests: XCTestCase {
    private func shadowRun() -> Run {
        var r = Run(character: PlayerCharacter(name: "S", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                               dungeon: "The Shadow World", difficulty: .wanderer))
        r.floor = 4
        return r
    }

    func testSecurityRoom() {
        let w = Wallet(store: MemoryStore()) { _ in }
        var dice = SeededDice(seed: 2)
        var r = shadowRun()
        r.pendingEvent = "shadow-security-east"
        XCTAssertEqual(Encounters.event("shadow-security-east")?.choices.count, 4)
        let west = Compass.allCases.firstIndex(of: .west)!
        let ok = Encounters.choose(west, &r, dice: &dice, wallet: w)
        XCTAssertTrue(ok.message.contains("escaped"))
        XCTAssertEqual(ok.gold, 50)
        r.pendingEvent = "shadow-security-east"
        let hp = r.hp
        let late = Encounters.choose(-1, &r, dice: &dice, wallet: w)
        XCTAssertTrue(late.message.contains("Time ran out"))
        XCTAssertEqual(r.hp, hp - jsRound(Double(r.maxHp) * 0.3))
        XCTAssertEqual(r.shadowCorruption, 1)
    }

    func testCorruptionAndRelics() {
        let w = Wallet(store: MemoryStore()) { _ in }
        var dice = SeededDice(seed: 9)
        var r = shadowRun()
        r.hp = 10
        r.pendingEvent = "shadow-mirror"
        _ = Encounters.choose(0, &r, dice: &dice, wallet: w)
        XCTAssertEqual(r.hp, r.maxHp)
        XCTAssertEqual(r.shadowCorruption, 2, "the Mirror's price is Shadow Corruption")
        let key = GameContent.shared.dungeon("The Shadow World").loot.first { $0.name == "Door Key" }!
        r.inventory.append(key)
        for _ in 0..<20 {
            r.pendingEvent = "shadow-two-doors-1"
            let out = Encounters.choose(1, &r, dice: &dice, wallet: w)
            XCTAssertTrue(out.message.contains("chest"), out.message)
        }
        r.pendingEvent = "shadow-handwriting"
        _ = Encounters.choose(0, &r, dice: &dice, wallet: w)
        XCTAssertTrue(r.shadowNotes)
    }
}

final class ForestTests: XCTestCase {
    func testMeterBoxAndPotions() {
        var r = Run(character: PlayerCharacter(name: "F", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                               dungeon: "The Whispering Forest", difficulty: .wanderer))
        XCTAssertEqual(WhisperingForest.corrupt(&r, 50).first, "🌲 Warning. Corruption at 50 percent.")
        r.floor = 3
        XCTAssertNotNil(WhisperingForest.onFloor(&r))
        r.inventory.append(Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "", heal: 40))
        r.hp = 5
        _ = Inventory.use(&r, at: r.inventory.count - 1)
        XCTAssertEqual(r.forestCorruption, 40)
        let box = r.inventory.firstIndex { WhisperingForest.isMusicBox($0) }!
        XCTAssertTrue(Inventory.use(&r, at: box).used)
        XCTAssertEqual(r.forestCorruption, 0)
        r.forestCorruption = 95
        _ = WhisperingForest.corrupt(&r, 10)
        XCTAssertEqual(r.hp, 0, "the forest takes a life")
        XCTAssertEqual(r.forestCorruption, 0, "and lets go, so a revive isn't killed again")
        var elsewhere = Run(character: PlayerCharacter(name: "G", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                                       dungeon: "Crypt of Malachar", difficulty: .wanderer))
        XCTAssertTrue(WhisperingForest.corrupt(&elsewhere, 50).isEmpty)
        XCTAssertEqual(elsewhere.forestCorruption, 0)
    }
}

final class MedusaTests: XCTestCase {
    func testGazeSpareAndReunion() {
        var r = Run(character: PlayerCharacter(name: "M", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                               dungeon: "The Hollow", difficulty: .wanderer))
        r.floor = 5
        var e = Enemy(name: "Medusa", icon: "🐍", hp: 85, maxHp: 85, atk: 10...18, gold: 20...35)
        e.mechanics["medusa"] = .bool(true)
        _ = Combat.begin(&r, against: e)
        XCTAssertTrue(r.medusa.met)
        var dice = LoadedDice(chances: [true, true, true])
        var log: [String] = []
        let def = r.totalDef
        XCTAssertTrue(Medusa.gaze(&r, dice: &dice, log: &log))
        XCTAssertEqual(r.totalDef, def - 3)
        Medusa.tick(&r, log: &log); Medusa.tick(&r, log: &log)
        XCTAssertEqual(r.totalDef, def, "petrification fades after 2 turns")
        XCTAssertTrue(Medusa.gaze(&r, dice: &dice, log: &log))
        XCTAssertTrue(r.frozen)
        XCTAssertTrue(Medusa.gaze(&r, dice: &dice, log: &log))
        XCTAssertEqual(r.hp, 0, "turned to stone")

        _ = Medusa.spare(&r)
        XCTAssertTrue(Medusa.walksWithYou(r))
        _ = Combat.begin(&r, against: Enemy(name: "Rat", icon: "🐀", hp: 5, maxHp: 5, atk: 1...2, gold: 1...1))
        XCTAssertTrue(r.fight.medusaGuard)
        let store = MemoryStore()
        XCTAssertEqual(Medusa.fatherChance(store), 0.60)
        _ = Medusa.reunion(&r, store: store)
        XCTAssertFalse(Medusa.walksWithYou(r))
        XCTAssertEqual(Medusa.fatherChance(store), 0.57, accuracy: 0.0001)
    }
}

final class HuntTests: XCTestCase {
    func testRanksAndHunt() {
        let store = MemoryStore()
        XCTAssertEqual(Hunt.rank(store).name, "Scout")
        XCTAssertNil(Hunt.addXP(60, store: store))
        XCTAssertEqual(Hunt.addXP(60, store: store)?.name, "Tracker")
        XCTAssertEqual(Hunt.xp(store), 120)
        XCTAssertEqual(Hunt.next(after: Hunt.rank(store)).xpNeeded, 250)

        let ch = PlayerCharacter(name: "H", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        var h = Hunt.Hunter(ch)
        XCTAssertEqual(h.maxHp, GameData.classInfo("Sentinel").maxHp, "the character's own class stats")
        var dice = SeededDice(seed: 4)
        var gold = 0, kills = 0, finds = 0
        for _ in 0..<60 where !h.dead {
            let m = Hunt.tick(&h, rank: Hunt.ranks[3], dice: &dice)
            gold += m.gold
            if m.killed != nil { kills += 1 }
            if m.item != nil { finds += 1 }
        }
        XCTAssertEqual(gold, h.gold)
        XCTAssertEqual(kills, h.kills)
        XCTAssertGreaterThan(kills, 0)
    }
}

final class HollowEventTests: XCTestCase {
    private func hollow() -> Run {
        var r = Run(character: PlayerCharacter(name: "W", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                               dungeon: "The Hollow", difficulty: .wanderer))
        r.floor = 6
        return r
    }

    func testWeepingChildAndMother() {
        let w = Wallet(store: MemoryStore()) { _ in }
        var r = hollow()
        var dice = LoadedDice(rolls: [20], chances: [true])
        r.pendingEvent = "weeping-child"
        let calm = Encounters.choose(1, &r, dice: &dice, wallet: w)
        XCTAssertEqual(calm.stat, "wepingChildSoothed")
        XCTAssertTrue(r.weepingChildSoothed)
        XCTAssertEqual(Encounters.event("weeping-mother-child")?.choices.first, "👶 Lead Her to the Child")
        r.pendingEvent = "weeping-mother-child"
        let max = r.maxHp
        dice = LoadedDice(rolls: [35])
        let reunion = Encounters.choose(0, &r, dice: &dice, wallet: w)
        XCTAssertEqual(reunion.stat, "motherReunion")
        XCTAssertEqual(r.maxHp, max + 5)
        r.pendingEvent = "weeping-mother"
        XCTAssertEqual(Encounters.choose(1, &r, dice: &dice, wallet: w).enemy?.name, "The Weeping Mother")
        var box = Enemy(name: "The Music Box", icon: "🎵", hp: 0, maxHp: 38, atk: 7...12, gold: 8...14)
        box.mechanics["isMusicBox"] = .bool(true)
        XCTAssertNotNil(HollowEvents.onKill(box, &r))
        XCTAssertTrue(r.inventory.contains(where: HollowEvents.isBoxItem))
        r.pendingEvent = "weeping-child-box"
        dice = LoadedDice(rolls: [25], chances: [true])
        let played = Encounters.choose(2, &r, dice: &dice, wallet: w)
        XCTAssertEqual(played.music, "music-box")
        XCTAssertFalse(r.inventory.contains(where: HollowEvents.isBoxItem), "the box is used up")
    }

    func testTimeDescender() {
        var r = hollow()
        var dice = LoadedDice(chances: [true])
        let td = TimeDescender.encounter(for: r, dice: &dice)!
        _ = Combat.begin(&r, against: td)
        XCTAssertTrue(r.timeDescenderMet)
        dice = LoadedDice(chances: [true])
        XCTAssertNil(TimeDescender.encounter(for: r, dice: &dice), "once a run")
        r.enemy = TimeDescender.clock
        r.defending = true
        var d2 = LoadedDice(rolls: [28])
        XCTAssertEqual(TimeDescender.tick(&r, dice: &d2), 14, "bracing halves the tick")
        var d3 = LoadedDice(rolls: [30], chances: [false])
        _ = TimeDescender.strike(&r, heavy: true, defend: false, dice: &d3)
        XCTAssertLessThan(r.enemy!.hp, 79)
        let store = MemoryStore()
        var d4 = SeededDice(seed: 1)
        XCTAssertTrue(TimeDescender.victory(&r, store: store, dice: &d4).armor)
        XCTAssertTrue(TimeDescender.hasChronoArmor(r))
        XCTAssertFalse(TimeDescender.victory(&r, store: store, dice: &d4).armor, "Chrono Armor only once")
    }
}

final class ChimeraTests: XCTestCase {
    func testParts() {
        let store = MemoryStore()
        var r = Run(character: PlayerCharacter(name: "C", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                               dungeon: "The Whispering Forest", difficulty: .wanderer))
        r.floor = 9
        var dice = SeededDice(seed: 3)
        let parts = Chimera.spawn(r, store: store, dice: &dice)!
        XCTAssertEqual(Chimera.name(parts), "The Corrupted Chimera", "always on the forest's floor 9, the first time")
        var no = LoadedDice(chances: [false])
        XCTAssertNil(Chimera.spawn(r, store: store, dice: &no), "only the first visit is certain")
        _ = Combat.beginAmbush(&r, parts)
        XCTAssertEqual(r.foes.count, 2)
        var log: [String] = []
        Chimera.beforeAttack(&r, log: &log)
        XCTAssertEqual(r.forestCorruption, 15, "the Maw corrupts")
        r.enemy = parts[1]
        let hp = r.hp
        Chimera.reflect(&r, 40, log: &log)
        XCTAssertEqual(r.hp, hp - 10, "the Thornbound reflects a quarter")
    }
}

final class SpecialEncounterTests: XCTestCase {
    func testNPCsBoxBunnyWitness() {
        let store = MemoryStore()
        let w = Wallet(store: store) { _ in }
        var r = Run(character: PlayerCharacter(name: "N", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.floor = 3
        var dice = LoadedDice(chances: [true])
        XCTAssertNotNil(SpecialEncounters.npc(&r, dice: &dice))
        dice = LoadedDice(chances: [true])
        XCTAssertNil(SpecialEncounters.npc(&r, dice: &dice), "one a run")

        r.pendingEvent = "npc-wounded-warrior"
        r.inventory = []
        XCTAssertTrue(Encounters.choose(0, &r, dice: &dice, wallet: w).retry, "no potion: choose again")

        r.event = "friday13"
        dice = LoadedDice(chances: [true])
        XCTAssertEqual(SpecialEncounters.blackBox(&r, dice: &dice), "black-box")
        dice = LoadedDice(chances: [true])
        XCTAssertNil(SpecialEncounters.blackBox(&r, dice: &dice), "once a floor")
        r.pendingEvent = "black-box"
        let box = Encounters.choose(0, &r, dice: &dice, wallet: w)
        XCTAssertEqual(box.enemy?.name, "The Unlucky One")
        XCTAssertFalse(box.enemy!.isBoss, "beating it mustn't end the run as a victory")

        r.event = "easter"
        dice = LoadedDice(chances: [true])
        XCTAssertEqual(SpecialEncounters.easterBunny(r, earned: ["easter-bunny"], dice: &dice), "easter-bunny-owned")
        r.pendingEvent = "easter-bunny"
        XCTAssertEqual(Encounters.choose(1, &r, dice: &dice, wallet: w).spirit, "easter-bunny")

        XCTAssertTrue(SpecialEncounters.witnessJoins(store: store))
        XCTAssertFalse(SpecialEncounters.witnessJoins(store: store), "only once")
        XCTAssertTrue(Home.minions(store).contains { $0.name == "The Witness" })
    }
}

final class WeatherTests: XCTestCase {
    func testWeatherEffects() {
        var r = Run(character: PlayerCharacter(name: "W", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        let max = r.maxHp
        r.weather = Weather.byDungeon["Crypt of Malachar"]!.first { $0.id == "hallowed-ground" }
        r.maxHp += 25
        XCTAssertEqual(r.maxHp, max + 25)
        r.hp = 1
        r.inventory = [Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "", heal: 40)]
        _ = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.hp, 1 + 56, "Hallowed Ground: potions heal 40% more")
        var sd = SeededDice(seed: 2)
        Skills.start(&r, dice: &sd)
        r.weather = Weather.byDungeon["The Abyssal Deep"]!.first { $0.id == "strong-current" }
        let s = Skills.unlocked(r).first { $0.spCost >= 4 }!
        let withCurrent = Skills.cost(s, r)
        r.weather = nil
        XCTAssertEqual(Skills.cost(s, r), withCurrent + 2, "the Abyssal Deep's conditions work (they didn't on the web)")
        var dice = SeededDice(seed: 8)
        for d in GameData.dungeons {
            XCTAssertFalse(Weather.roll(for: d, dice: &dice).name.isEmpty)
        }
    }
}

final class RunModifierTests: XCTestCase {
    func testModifiers() {
        let store = MemoryStore()
        let w = Wallet(store: store) { _ in }
        var r = Run(character: PlayerCharacter(name: "R", cls: "Sentinel", race: "Human", prof: "Mercenary",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        RunModifiers.setEnabled(false, store: store)
        var dice = SeededDice(seed: 1)
        XCTAssertNil(RunModifiers.start(&r, store: store, wallet: w, dice: &dice))
        RunModifiers.setEnabled(true, store: store)
        r.modifier = "blessed"
        r.modifier = nil
        var d2 = LoadedDice(rolls: [7])
        let m = RunModifiers.start(&r, store: store, wallet: w, dice: &d2)
        XCTAssertEqual(m?.id, "blessed")
        XCTAssertEqual(r.inventory.filter { $0.name == "Health Potion" }.count, 4)
        r.modifier = "frozen"
        XCTAssertEqual(RunModifiers.rooms(8, r), 7)
        XCTAssertEqual(RunModifiers.rooms(4, r), 4)
        XCTAssertEqual(RunModifiers.rooms(1, r), 1, "the boss floor keeps its one room")
        r.modifier = "goldcurse"
        XCTAssertEqual(RunModifiers.potionCost(Item(name: "P", icon: "", type: "potion", desc: ""), 30, r), 60)
        r.modifier = "watching"
        var d3 = LoadedDice(chances: [true])
        XCTAssertNil(Encounters.rollEvent(r, dice: &d3), "The Watching: no event rooms")
        r.modifier = "phantom"
        _ = Combat.begin(&r, against: Enemy(name: "Rat", icon: "🐀", hp: 50, maxHp: 50, atk: 1...2, gold: 1...1))
        var d4 = LoadedDice(chances: [false])
        let turn = Combat.takeTurn(&r, .attack, dice: &d4)
        XCTAssertTrue(turn.crit, "Phantom Run: the first strike crits")
    }

    // MARK: Weapon Forge, Alchemy, Elixir Vendor

    private func crafter(_ cls: String = "Sentinel") -> Run {
        Run(character: PlayerCharacter(name: "F", cls: cls, race: "Human", prof: "Mercenary",
                                       dungeon: "Crypt of Malachar", difficulty: .wanderer))
    }

    func testForgeCraftsARealWeaponWithAWorkingEffect() {
        let store = MemoryStore()
        WeaponForge.add("iron-scrap", 5, store: store)
        var dice = LoadedDice(rolls: [0])  // Burning
        let w = WeaponForge.craft("iron-blade", store: store, dice: &dice)
        XCTAssertNotNil(w)
        XCTAssertEqual(WeaponForge.stash(store)["iron-scrap"], 2)
        XCTAssertEqual(w?.weaponAttack, 8...14, "the recipe's attack, not the web's 5-8 fallback")
        XCTAssertEqual(w?.forgeEffect, "burn")
        var d2 = LoadedDice(rolls: [1])
        let rr = WeaponForge.reroll(w!, store: store, dice: &d2)
        XCTAssertEqual(rr?.forgeEffect, "lifesteal")
        XCTAssertEqual(WeaponForge.stash(store)["iron-scrap"], nil)
        XCTAssertNil(WeaponForge.reroll(rr!, store: store, dice: &d2), "no scraps left")
        let kept = WeaponForge.keep(rr!, store: store)
        XCTAssertEqual(kept.name, "Iron Blade")
        WeaponForge.add("iron-scrap", 3, store: store)
        var d3 = LoadedDice(rolls: [0])
        let second = WeaponForge.keep(WeaponForge.craft("iron-blade", store: store, dice: &d3)!, store: store)
        XCTAssertEqual(second.name, "Iron Blade (Burning)", "a second blade isn't lost to the stash's one-per-name rule")
        XCTAssertEqual(WeaponForge.count(store), 2)

        // Burning in a fight: the hit sets the enemy alight.
        var r = crafter()
        r.equippedWeapon = w
        _ = Combat.begin(&r, against: Enemy(name: "Rat", icon: "🐀", hp: 500, maxHp: 500, atk: 1...1, gold: 1...1))
        var fight = LoadedDice(chances: [false, true])
        let t = Combat.takeTurn(&r, .attack, dice: &fight)
        XCTAssertTrue(t.log.contains { $0.contains("burning") }, t.log.joined(separator: "\n"))
    }

    func testForgeDropsRespectTheFloor() {
        let store = MemoryStore()
        var dice = LoadedDice(rolls: [8], chances: [true])
        let m = WeaponForge.drop(floor: 1, store: store, dice: &dice)
        XCTAssertEqual(m?.rarity, "common")
        var d2 = LoadedDice(rolls: [8], chances: [true])
        XCTAssertEqual(WeaponForge.drop(floor: 8, store: store, dice: &d2)?.id, "dragon-scale")
    }

    func testAlchemyBrewsAndTheBrewsWork() {
        let store = MemoryStore()
        let w = Wallet(store: store) { _ in }
        w.addGold(100)
        XCTAssertEqual(Alchemy.buy("blood-vial", store: store, wallet: w), "Bought Blood Vial.")
        Alchemy.add("ember-shard", store: store)
        var dice = LoadedDice(chances: [false])
        let b = Alchemy.craft("bloodfire", alchemist: false, store: store, dice: &dice)
        XCTAssertEqual(b?.potion.name, "Bloodfire Potion")
        XCTAssertEqual(Alchemy.stock(store), [:])
        XCTAssertNil(Alchemy.craft("elixir-of-life", alchemist: false, store: store, dice: &dice))

        var r = crafter()
        r.inventory = [b!.potion]
        r.hp = r.maxHp
        let used = Inventory.use(&r, at: 0)
        XCTAssertTrue(used.used, "an effect potion is worth drinking at full health")
        XCTAssertTrue(r.brews.burnNext)
        _ = Combat.begin(&r, against: Enemy(name: "Rat", icon: "🐀", hp: 50, maxHp: 50, atk: 1...1, gold: 1...1))
        XCTAssertEqual(r.enemy?.dotTurns, 3, "Bloodfire burns the next enemy")
        XCTAssertFalse(r.brews.burnNext)

        // Mirror Flask: the next hit goes back, and you take none of it.
        r.inventory = [Item(name: "Mirror Flask", icon: "🪞", type: "mirror-flask", desc: "")]
        XCTAssertTrue(Inventory.use(&r, at: 0).used)
        let hp = r.hp
        var d2 = LoadedDice()
        _ = Combat.takeTurn(&r, .defend, dice: &d2)
        XCTAssertEqual(r.hp, hp)
        XCTAssertFalse(r.brews.mirror)

        // Time Potion: the enemy loses its next turns.
        r.inventory = [Item(name: "Time Potion", icon: "⌛", type: "time-potion", desc: "")]
        _ = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.brews.timeStop, 2)
        let t = Combat.takeTurn(&r, .defend, dice: &d2)
        XCTAssertTrue(t.log.contains { $0.contains("Time stands still") })
        XCTAssertEqual(r.brews.timeStop, 1)

        // Outside a fight the tactical potions stay in the bag.
        var calm = crafter()
        calm.inventory = [Item(name: "Fog Flask", icon: "🌫️", type: "fog-flask", desc: "")]
        XCTAssertFalse(Inventory.use(&calm, at: 0).used)
        XCTAssertEqual(calm.inventory.count, 1)
    }

    func testAlchemistBrewsAreStrongerAndCarryTheirNumbers() {
        let store = MemoryStore()
        Alchemy.add("void-herb", store: store)
        Alchemy.add("moon-petal", store: store)
        var dice = LoadedDice()
        let p = Alchemy.craft("phantom-potion-r", alchemist: true, store: store, dice: &dice)!.potion
        var r = crafter("Alchemist")
        _ = Combat.begin(&r, against: Enemy(name: "Rat", icon: "🐀", hp: 50, maxHp: 50, atk: 1...1, gold: 1...1))
        r.inventory = [p]
        _ = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.brews.phantomTurns, 3, "the web always gave 2, whoever brewed it")
    }

    func testElixirVendor() {
        let store = MemoryStore()
        let w = Wallet(store: store) { _ in }
        w.addGold(60)
        var r = crafter()
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertTrue(ElixirVendor.buy(&r, store: store, wallet: w, date: day).hasPrefix("Bought"))
        XCTAssertEqual(w.gold, 5)
        XCTAssertTrue(ElixirVendor.buy(&r, store: store, wallet: w, date: day).hasPrefix("Already"))
        XCTAssertEqual(ElixirVendor.spares(r).first?.count, 1)
        XCTAssertNotNil(ElixirVendor.sell(r.inventory[0].name, &r, wallet: w))
        XCTAssertEqual(w.gold, 30)
        XCTAssertTrue(ElixirVendor.spares(r).isEmpty)
    }
}

final class RaceTests: XCTestCase {
    func newRun(_ race: String, cls: String = "Warrior", dungeon: String = "Crypt of Malachar",
                traits: Bool = true, wallet: Wallet = Wallet(store: MemoryStore())) -> Run {
        var r = Run(character: PlayerCharacter(name: "R", cls: cls, race: race, prof: "Thief",
                                               dungeon: dungeon, difficulty: .wanderer))
        r.spirit = nil
        _ = Races.start(&r, classTraits: traits, wallet: wallet)
        return r
    }

    func testEveryRaceOnTheCardIsHandled() {
        XCTAssertEqual(GameData.races.count, 15)
    }

    func testStatLines() {
        let base = Run(character: PlayerCharacter(name: "R", cls: "Warrior", race: "Human", prof: "Thief",
                                                  dungeon: "Crypt of Malachar", difficulty: .wanderer))
        let human = newRun("Human")
        XCTAssertEqual(human.atkBonus, 1)
        XCTAssertEqual(human.maxHp, base.maxHp + 5)
        XCTAssertEqual(human.defBonus, 1)
        XCTAssertEqual(human.maxSp, 23)
        let elf = newRun("Elf")
        XCTAssertEqual(elf.maxSp, 25)
        XCTAssertEqual(elf.fleeBonus, 0.05, accuracy: 1e-9)
        XCTAssertEqual(elf.critBonus, 0.03, accuracy: 1e-9)
        let dwarf = newRun("Dwarf")
        XCTAssertEqual(dwarf.atkBonus, 2)
        XCTAssertEqual(dwarf.defBonus, 2)
        let orc = newRun("Orc")
        XCTAssertEqual(orc.atkBonus, 4)
        XCTAssertEqual(orc.defBonus, -2)
        XCTAssertEqual(newRun("Orc", cls: "Wizard").defBonus, 0, "never below zero defense")
        XCTAssertEqual(newRun("Tiefling").luckBonus, 0.10, accuracy: 1e-9)
        XCTAssertEqual(newRun("Shade").fleeBonus, 0.05, accuracy: 1e-9)
        XCTAssertEqual(newRun("Golem").defBonus, 5)
        XCTAssertEqual(newRun("Gnome").maxSp, 30)
        XCTAssertEqual(newRun("Gnome", traits: false).maxSp, 20)
        XCTAssertEqual(newRun("Gnome", traits: false).luckBonus, 0.10, accuracy: 1e-9)
    }

    func testGoblinStartsWith30Gold() {
        let w = Wallet(store: MemoryStore())
        XCTAssertEqual(newRun("Goblin", wallet: w).gold, 30)
        XCTAssertEqual(w.gold, 30)
    }

    func testAbilitiesFollowClassTraits() {
        let base = newRun("Human", traits: false).maxLives
        XCTAssertEqual(newRun("Angel").maxLives, base + 1)
        XCTAssertEqual(newRun("Angel", traits: false).maxLives, base)
        let full = Run(character: PlayerCharacter(name: "R", cls: "Warrior", race: "Vampire", prof: "Thief",
                                                  dungeon: "Crypt of Malachar", difficulty: .wanderer)).maxHp
        XCTAssertEqual(newRun("Vampire").maxHp, jsRound(Double(full) * 0.8))
        XCTAssertEqual(newRun("Vampire", traits: false).maxHp, full)
        XCTAssertFalse(Races.immune(newRun("Golem", traits: false)))
        XCTAssertTrue(Races.immune(newRun("Golem")))
    }

    func testMerfolkInTheSunkenArchives() {
        let home = newRun("Merfolk", dungeon: "The Sunken Archives")
        let away = newRun("Merfolk")
        XCTAssertEqual(home.atkBonus, 3)
        XCTAssertEqual(home.maxHp, jsRound(Double(away.maxHp) * 1.1))
        XCTAssertEqual(Races.potionHeal(away, 40), 48)
        XCTAssertEqual(Races.potionHeal(newRun("Human"), 40), 40)
    }

    func testDemonDragonbornAndHalfling() {
        var log: [String] = []
        var no = LoadedDice(chances: [false])
        XCTAssertEqual(Races.attack(newRun("Demon"), 20, dice: &no, log: &log), 23)
        XCTAssertEqual(Races.incoming(newRun("Demon"), 20), 23)
        var yes = LoadedDice(chances: [true])
        XCTAssertEqual(Races.attack(newRun("Dragonborn"), 20, dice: &yes, log: &log), 26)
        let e = Enemy(name: "Dummy", icon: "", hp: 50, maxHp: 50, atk: 5...5, gold: 1...1)
        var dodge = LoadedDice(chances: [true])
        XCTAssertTrue(Races.dodges(newRun("Halfling"), e, dice: &dodge, log: &log))
        var dodgeOff = LoadedDice(chances: [true])
        XCTAssertFalse(Races.dodges(newRun("Halfling", traits: false), e, dice: &dodgeOff, log: &log))
    }

    func testVampireDrainAndAngelHeal() {
        var v = newRun("Vampire")
        v.hp = 10
        XCTAssertFalse(Races.onKill(&v).isEmpty)
        XCTAssertEqual(v.hp, 15)
        var a = newRun("Angel")
        a.hp = 10
        Races.onLevelUp(&a, levels: 2)
        XCTAssertEqual(a.hp, 40)
    }

    func testGnomeSkillsAndDwarfPrices() {
        let g = newRun("Gnome")
        XCTAssertEqual(Races.skillCostCut(g), 2)
        XCTAssertEqual(Races.skillCostCut(newRun("Gnome", traits: false)), 0)
        XCTAssertEqual(Races.shopPrice(100, newRun("Dwarf")), 90)
        XCTAssertEqual(Races.shopPrice(100, newRun("Elf")), 100)
    }

    func testGolemShrugsOffFreezeAndPoisonTraps() {
        var r = newRun("Golem")
        for _ in 0..<200 {
            r.hp = r.maxHp
            var d = SystemDice()
            _ = Inventory.triggerTrap(&r, dice: &d)
            XCTAssertFalse(r.frozen)
            if r.poisonTurns > 0 { XCTAssertEqual(r.poisonDamage, 6, "only burns get through") }
            r.poisonTurns = 0
        }
    }
}

final class DailyDescentTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testThirtyDayCycleAndBonusGold() {
        XCTAssertEqual(DailyDescent.cycle.count, 30)
        XCTAssertEqual(DailyDescent.reward(forDay: 1).gold, 25)
        XCTAssertEqual(DailyDescent.reward(forDay: 30).gold, 700)
        XCTAssertEqual(DailyDescent.reward(forDay: 31).gold, 75)
        XCTAssertEqual(DailyDescent.reward(forDay: 61).gold, 125)
        XCTAssertEqual(DailyDescent.reward(forDay: 3).parts, ["💰 55g", "✨ 5 Soul Fragments"])
    }

    func testClaimStreakAndRewards() {
        let store = MemoryStore()
        let w = Wallet(store: store)
        XCTAssertEqual(DailyDescent.claim(store: store, wallet: w, now: day(2026, 10, 1), calendar: cal)?.day, 1)
        XCTAssertNil(DailyDescent.claim(store: store, wallet: w, now: day(2026, 10, 1, hour: 23), calendar: cal))
        XCTAssertTrue(DailyDescent.status(store, now: day(2026, 10, 1), calendar: cal).claimed)
        XCTAssertEqual(DailyDescent.claim(store: store, wallet: w, now: day(2026, 10, 2, hour: 0), calendar: cal)?.day, 2)
        XCTAssertEqual(w.gold, 65)
        XCTAssertEqual(GlobalInventory(store: store).items.map(\.name), ["Health Potion"])
        _ = DailyDescent.claim(store: store, wallet: w, now: day(2026, 10, 3), calendar: cal)
        XCTAssertEqual(store.getItem("dd_soul_fragments"), "5")
        _ = DailyDescent.claim(store: store, wallet: w, now: day(2026, 10, 4), calendar: cal)
        _ = DailyDescent.claim(store: store, wallet: w, now: day(2026, 10, 5), calendar: cal)
        XCTAssertEqual(CoinShop.coins(store), 1)
        let st = DailyDescent.state(store)
        XCTAssertEqual(st.streak, 5)
        XCTAssertEqual(st.lastClaim, "2026-10-5")
        XCTAssertEqual(st.totalDays, 5)
    }

    func testMissingADayStartsOver() {
        let store = MemoryStore(["dd_daily_descent": #"{"streak":12,"lastClaim":"2026-9-28","totalDays":40}"#])
        let w = Wallet(store: store)
        XCTAssertEqual(DailyDescent.status(store, now: day(2026, 9, 29), calendar: cal).next.day, 13)
        XCTAssertEqual(DailyDescent.status(store, now: day(2026, 9, 30), calendar: cal).next.day, 1)
        XCTAssertEqual(DailyDescent.claim(store: store, wallet: w, now: day(2026, 9, 30), calendar: cal)?.day, 1)
        XCTAssertEqual(DailyDescent.state(store).totalDays, 41)
    }
}

final class DailyChallengeTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
    func newRun(_ diff: GameData.Difficulty = .wanderer) -> Run {
        var r = Run(character: PlayerCharacter(name: "D", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: diff))
        r.spirit = nil
        return r
    }

    func testTodaysChallengeUsesTheWebFormula() {
        // (2026 * 365 + 9 * 31 + 30) % 7 = 739799 % 7 = 4 → Nightmare Day
        XCTAssertEqual(DailyChallenge.today(day(2026, 10, 30), calendar: cal).id, "dc-nightmare")
        XCTAssertEqual(DailyChallenge.today(day(2026, 10, 31), calendar: cal).id, "dc-speed")
        XCTAssertEqual(DailyChallenge.today(day(2026, 11, 3), calendar: cal).id, "dc-glass")
    }

    func testOnlyAppliesWhenRegistered() {
        let store = MemoryStore()
        let w = Wallet(store: store)
        var r = newRun()
        XCTAssertNil(DailyChallenge.start(&r, store: store, wallet: w, now: day(2026, 11, 3), calendar: cal))
        XCTAssertNil(r.dailyChallenge)
        DailyChallenge.register(store, now: day(2026, 11, 3), calendar: cal)
        let full = r.maxHp
        XCTAssertNotNil(DailyChallenge.start(&r, store: store, wallet: w, now: day(2026, 11, 3), calendar: cal))
        XCTAssertEqual(r.dailyChallenge, "glassCannon")
        XCTAssertEqual(r.maxHp, full / 2)
        XCTAssertEqual(DailyChallenge.attackMult(r), 2)
        XCTAssertFalse(DailyChallenge.isRegistered(store, now: day(2026, 11, 4), calendar: cal), "registration is for one day")
    }

    func testBlessedDayAndCompletion() {
        let store = MemoryStore()
        let w = Wallet(store: store)
        let blessed = day(2026, 11, 5)
        XCTAssertEqual(DailyChallenge.today(blessed, calendar: cal).effect, "blessedDay")
        DailyChallenge.register(store, now: blessed, calendar: cal)
        var r = newRun()
        r.inventory = []
        _ = DailyChallenge.start(&r, store: store, wallet: w, now: blessed, calendar: cal)
        XCTAssertEqual(r.gold, 30)
        XCTAssertEqual(r.inventory.filter { $0.name == "Health Potion" }.count, 3)
        XCTAssertEqual(DailyChallenge.complete(r, store: store, now: blessed, calendar: cal)?.name, "Blessed Day")
        XCTAssertNil(DailyChallenge.complete(r, store: store, now: blessed, calendar: cal), "once a day")
        XCTAssertEqual(CoinShop.coins(store), 1)
        XCTAssertEqual(DailyChallenge.history(store), [DailyChallenge.Past(date: "2026-11-5", name: "Blessed Day", completed: true)])
    }

    func testEffects() {
        var r = newRun()
        r.dailyChallenge = "cursedDay"
        r.inCombat = true
        r.hp = 10
        r.inventory = [Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "", heal: 40)]
        XCTAssertFalse(Inventory.use(&r, at: 0).used)
        r.inCombat = false
        XCTAssertTrue(Inventory.use(&r, at: 0).used)

        r.dailyChallenge = "hordeDay"
        XCTAssertEqual(DailyChallenge.combatBonus(r) + Rooms.combatChance(r.difficulty), 0.70, accuracy: 1e-9)
        r.dailyChallenge = "speedRun"
        XCTAssertEqual(DailyChallenge.enemyMult(r), 1.25)
        let xp0 = r.xp
        Progression.gainXP(&r, 10)
        XCTAssertEqual(r.xp - xp0, 20)

        r.dailyChallenge = "ironDay"
        var d = SeededDice(seed: 3)
        let plain = newRun()
        var d2 = SeededDice(seed: 3)
        let a = Combat.nextEnemy(for: r, dice: &d), b = Combat.nextEnemy(for: plain, dice: &d2)
        XCTAssertEqual(a.name, b.name)
        if !a.isElite { XCTAssertEqual(a.maxHp, jsRound(Double(b.maxHp) * 1.5)) }

        r.dailyChallenge = "nightmareDay"
        var yes = LoadedDice(chances: [true])
        let nm = DailyChallenge.nightmareEnemy(for: r, dice: &yes)
        XCTAssertNotNil(nm)
        let names = Set((GameContent.shared.nightmareEnemies!.t1 + GameContent.shared.nightmareEnemies!.t2).map(\.name))
        XCTAssertTrue(names.contains(nm!.name))
    }
}

final class ClassTraitTests: XCTestCase {
    func newRun(_ cls: String, dungeon: String = "Crypt of Malachar", traits: Bool = true) -> Run {
        var r = Run(character: PlayerCharacter(name: "C", cls: cls, race: "Human", prof: "Thief",
                                               dungeon: dungeon, difficulty: .wanderer))
        r.spirit = nil
        _ = ClassTraits.start(&r, classTraits: traits)
        return r
    }
    var dummy: Enemy { Enemy(name: "Dummy", icon: "", hp: 500, maxHp: 500, atk: 10...10, gold: 1...1) }

    func testEveryClassHasATrait() {
        for c in GameData.classes { XCTAssertNotNil(ClassTraits.trait(c.id), c.id) }
    }

    func testStartEffectsAndTheSetting() {
        let full = Run(character: PlayerCharacter(name: "C", cls: "Sorcerer", race: "Human", prof: "Thief",
                                                  dungeon: "Crypt of Malachar", difficulty: .wanderer)).maxHp
        XCTAssertEqual(newRun("Sorcerer").maxHp, jsRound(Double(full) * 0.8))
        XCTAssertEqual(newRun("Sorcerer", traits: false).maxHp, full)
        XCTAssertFalse(newRun("Sorcerer", traits: false).classTraits)
        XCTAssertEqual(newRun("Berserker").atkBonus, 3)
        XCTAssertEqual(newRun("Naturalist").defBonus, 3)
        XCTAssertEqual(newRun("Shaman", dungeon: "Frosthold Abyss").defBonus, 4)
        XCTAssertEqual(newRun("Shaman").defBonus, 0)
        XCTAssertTrue(newRun("Wizard").inventory.contains { $0.name == "Spell Scroll" })
        XCTAssertEqual(newRun("Cleric").potionMult, 3)
        XCTAssertFalse(ClassTraits.canFlee(newRun("Berserker")))
        XCTAssertTrue(ClassTraits.canFlee(newRun("Berserker", traits: false)))
    }

    func testOpeningShotEveryFight() {
        for _ in 0..<2 {
            var r = newRun("Ranger")
            Combat.begin(&r, against: dummy)
            var log: [String] = []
            var d = LoadedDice()
            XCTAssertEqual(ClassTraits.attack(&r, 20, dice: &d, log: &log), 35)
            XCTAssertEqual(ClassTraits.attack(&r, 20, dice: &d, log: &log), 20)
        }
    }

    func testFirstBloodEveryFight() {
        var r = newRun("Assassin")
        Combat.begin(&r, against: dummy)
        XCTAssertTrue(ClassTraits.firstBloodCrit(&r))
        XCTAssertFalse(ClassTraits.firstBloodCrit(&r))
        Combat.begin(&r, against: dummy)
        XCTAssertTrue(ClassTraits.firstBloodCrit(&r))
    }

    func testKillsFloorsAndRooms() {
        var w = newRun("Warlock")
        w.hp = 10
        var d = LoadedDice()
        XCTAssertFalse(ClassTraits.onKill(&w, dummy, dice: &d).isEmpty)
        XCTAssertEqual(w.hp, 15)
        var n = newRun("Necromancer")
        n.hp = 10
        var yes = LoadedDice(chances: [true])
        _ = ClassTraits.onKill(&n, dummy, dice: &yes)
        XCTAssertEqual(n.raised?.name, "Dummy")
        Combat.begin(&n, against: dummy)
        XCTAssertNil(n.raised)
        XCTAssertNotNil(n.fight.ally)
        var war = newRun("Warrior")
        war.floor = 3
        _ = ClassTraits.onFloor(&war)
        XCTAssertEqual(war.atkBonus, 1)
        var dr = newRun("Druid", dungeon: "The Hollow")
        dr.hp = 10
        XCTAssertNotNil(ClassTraits.onRoom(&dr))
        XCTAssertEqual(dr.hp, 13)
    }

    func testUndyingResolveOnTheLastLife() {
        var r = newRun("DeathKnight")
        var log: [String] = []
        r.hp = 0
        r.lives = 2
        XCTAssertFalse(ClassTraits.undying(&r, log: &log))
        r.lives = 1
        XCTAssertTrue(ClassTraits.undying(&r, log: &log))
        XCTAssertEqual(r.hp, 1)
        r.hp = 0
        XCTAssertFalse(ClassTraits.undying(&r, log: &log), "once a run")
    }

    func testMonkIronBodyAndAvoids() {
        var m = newRun("Monk")
        m.def = 4
        m.hp = m.maxHp
        XCTAssertEqual(ClassTraits.defense(m), 0)
        m.hp = 1
        XCTAssertEqual(ClassTraits.defense(m), m.totalDef)
        var log: [String] = []
        var yes = LoadedDice(chances: [true])
        XCTAssertTrue(ClassTraits.avoids(m, dummy, dice: &yes, log: &log))
    }

    func testShamanDoublesTheGoodSideOfTheWeather() {
        var r = newRun("Shaman")
        r.weather = Weather("dead-calm", "Dead Calm", "", "", "Enemies have -15% attack. Gold drops +30%.") { $0.enemyAtkMult = 0.85; $0.goldMult = 1.3 }
        ClassTraits.shapeWeather(&r)
        XCTAssertEqual(r.weather!.enemyAtkMult, 0.70, accuracy: 1e-9)
        XCTAssertEqual(r.weather!.goldMult, 1.6, accuracy: 1e-9)
    }

    func testSpellsAndSkills() {
        XCTAssertEqual(Spells.cooldownFor("shadow-blast", newRun("ShadowMage")), 0)
        XCTAssertEqual(Spells.cooldownFor("time-stop", newRun("TimeMage")), 3)
        XCTAssertEqual(ClassTraits.spellPower(newRun("Elementalist"), "fireball"), 1.4)
        XCTAssertEqual(ClassTraits.skillCostCut(newRun("Sorcerer")), 3)
        XCTAssertTrue(ClassTraits.voidSure(newRun("VoidWalker"), "extraction"))
    }
}

final class DevToolsTests: XCTestCase {
    func testPasswordAndChange() {
        let store = MemoryStore()
        XCTAssertEqual(DevTools.password(store), "67")
        XCTAssertEqual(DevTools.changePassword("a", confirm: "a", store: store), "Password must be at least 2 characters.")
        XCTAssertEqual(DevTools.changePassword("abc", confirm: "abd", store: store), "Passwords do not match.")
        XCTAssertNil(DevTools.changePassword("abc", confirm: "abc", store: store))
        XCTAssertEqual(DevTools.password(store), "abc")
    }

    func testUnlockAllAndReset() {
        let store = MemoryStore()
        let roster = CharacterRoster(store: store)
        DevTools.unlockAll(store)
        XCTAssertEqual(roster.unlockedDungeons(), GameData.dungeons)
        DevTools.resetUnlocks(store)
        store.removeItem("dd_infernal_unlocked")
        store.removeItem("dd_abyssal_unlocked")
        XCTAssertEqual(roster.unlockedDungeons(), [GameData.dungeons[0]])
    }

    func testGunsAndCodes() {
        let store = MemoryStore()
        DevTools.unlockAllGuns(store)
        XCTAssertEqual(Guns.owned(store).count, Guns.all.count)
        DevTools.giveAllGunParts(store)
        XCTAssertTrue(Guns.parts.allSatisfy { Guns.partCounts(store)[$0.id] == 99 })
        var d = SeededDice(seed: 9)
        for p in VoidMode.Prize.allCases {
            XCTAssertEqual(VoidMode.prize(for: DevTools.rewardCode(for: p, dice: &d)), p)
        }
    }
}

final class BossMusicTests: XCTestCase {
    func testBossMusicByPhase() {
        XCTAssertEqual(Soundtrack.bossTrack(dungeon: "The Abyssal Deep"), "abyssal-boss")
        XCTAssertEqual(Soundtrack.bossTrack(dungeon: "The Abyssal Deep", phase: 2), "abyssal-boss-p2")
        XCTAssertEqual(Soundtrack.bossTrack(dungeon: "The Abyssal Deep", phase: 3), "abyssal-boss-p3")
        XCTAssertEqual(Soundtrack.bossTrack(dungeon: "Crypt of Malachar", phase: 3), "boss")
        for t in ["abyssal-boss-p2", "abyssal-boss-p3", "raid-victory", "battle"] { XCTAssertNotNil(Soundtrack.file(forTrack: t), t) }
    }
}

final class CharacterCodeTests: XCTestCase {
    func testRoundTripAndWebCodes() throws {
        var ch = PlayerCharacter(name: "Ana", cls: "Monk", race: "Elf", prof: "Thief", dungeon: "The Hollow", difficulty: .ironblood)
        ch.floor = 7
        ch.extra["journal"] = .array([.string("x")])
        let code = try XCTUnwrap(CharacterCode.export(ch))
        let back = try XCTUnwrap(CharacterCode.read(code))
        XCTAssertEqual(back.name, "Ana")
        XCTAssertEqual(back.dungeon, "The Hollow")
        XCTAssertEqual(back.floor, 0, "imports start fresh")
        XCTAssertEqual(back.extra["journal"], .array([.string("x")]))
        // An old web code with only a name and class: the rest is filled in.
        let web = Data(#"{"name":"Zé","cls":"Warrior"}"#.utf8).base64EncodedString()
        let old = try XCTUnwrap(CharacterCode.read(web))
        XCTAssertEqual(old.name, "Zé")
        XCTAssertEqual(old.race, "Human")
        XCTAssertEqual(old.prof, "Blacksmith")
        XCTAssertNil(CharacterCode.read("not a code"))
        let store = MemoryStore()
        let roster = CharacterRoster(store: store)
        for _ in 0..<5 { XCTAssertNotNil(try? CharacterCode.importCode(code, into: roster).get()) }
        XCTAssertEqual(CharacterCode.importCode(code, into: roster), .failure(.full))
    }
}

final class CursedModifierTests: XCTestCase {
    func testCursedModifierForcesARunModifier() {
        let store = MemoryStore(["dd_run_modifiers": "0"])
        let w = Wallet(store: store)
        var n = Events.NextRun()
        n.cursedModifier = true
        Events.saveNextRun(n, store)
        var r = Run(character: PlayerCharacter(name: "C", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        var d = SeededDice(seed: 1)
        XCTAssertNil(RunModifiers.start(&r, store: store, wallet: w, dice: &d), "modifiers are off")
        _ = Events.applyNextRun(&r, store: store)
        XCTAssertNotNil(RunModifiers.start(&r, store: store, wallet: w, dice: &d))
        XCTAssertFalse(Events.comingSoon("cursed-run-mod"))
        // An old save without the field still loads.
        store.setItem("dd_event_next_run", #"{"bonusLives":1,"xpMult":1,"xpFloors":0,"spiritBoost":false,"sparkler":false,"luckKills":0,"items":[]}"#)
        XCTAssertEqual(Events.nextRun(store).bonusLives, 1)
    }
}

final class FamiliarTests: XCTestCase {
    func testBondLevelsTitlesAndSpecies() {
        let store = MemoryStore(["dd_familiar": #"{"speciesId":"raven","bond":0,"name":""}"#])
        let book = AchievementBook(store: store, wallet: Wallet(store: store))
        var f = Familiar.load(store)
        XCTAssertEqual(f.startingSpeciesId, "raven", "older saves get their starting species")
        XCTAssertEqual(f.displayName, "your Raven")
        XCTAssertNil(Familiar.gainBond(29, store: store, achievements: book))
        XCTAssertEqual(Familiar.gainBond(1, store: store, achievements: book), "your Raven grows closer to you. Bond level 2.")
        XCTAssertEqual(book.stat("familiarBondLevel"), 2)
        Familiar.gainBond(120, store: store, achievements: book)
        f = Familiar.load(store)
        XCTAssertEqual(f.level, 6)
        XCTAssertEqual(f.title, "the Bonded")
        XCTAssertEqual(f.menuBadge, "🐦‍⬛ ✦ Lv.6")
        XCTAssertFalse(Familiar.choose("imp", store: store, achievements: book), "locked")
        store.setItem("dd_trophies", "100")
        XCTAssertTrue(Familiar.choose("imp", store: store, achievements: book))
        Familiar.rename("  Pip  ", store: store)
        XCTAssertEqual(Familiar.load(store).displayName, "Pip")
        XCTAssertTrue(Familiar.choose("raven", store: store, achievements: book), "the starting species is always open")
    }

    func testNewPlayersGetOne() {
        let store = MemoryStore()
        var d = SeededDice(seed: 4)
        let f = Familiar.load(store, dice: &d)
        XCTAssertEqual(f.bond, 0)
        XCTAssertEqual(Familiar.load(store).speciesId, f.speciesId, "saved")
    }
}

final class SeasonalItemTests: XCTestCase {
    func newRun() -> Run {
        var r = Run(character: PlayerCharacter(name: "S", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.spirit = nil
        r.inventory = []
        return r
    }
    var foe: Enemy { Enemy(name: "Dummy", icon: "", hp: 300, maxHp: 300, atk: 5...5, gold: 1...1) }

    func testShopPutsThemInTheNextRun() {
        XCTAssertFalse(Events.comingSoon("liberty-cannon"))
        XCTAssertFalse(Events.comingSoon("liberty-title"))
        XCTAssertEqual(SeasonalItems.all.count, 10)
    }

    func testCombatItems() {
        var r = newRun()
        r.inventory = [SeasonalItems.all["liberty-cannon"]!]
        XCTAssertFalse(Inventory.use(&r, at: 0).used, "combat only")
        Combat.begin(&r, against: foe)
        XCTAssertTrue(Inventory.use(&r, at: 0).enemyDied)
        XCTAssertTrue(r.inventory.isEmpty)

        Combat.begin(&r, against: foe)
        r.inventory = [SeasonalItems.all["liberty-firework"]!, SeasonalItems.all["stpat-rainbow"]!, SeasonalItems.all["val-love-potion"]!]
        _ = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.enemy?.hp, 300 - 85)
        _ = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.fight.shield, 40)
        _ = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.fight.controlled, 2)
    }

    func testBuffsAndPotions() {
        var r = newRun()
        r.hp = 10
        r.poisonTurns = 3
        r.inventory = [SeasonalItems.all["liberty-potion"]!, SeasonalItems.all["val-rose"]!, SeasonalItems.all["val-cupid-arrow"]!]
        _ = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.hp, min(r.maxHp, 110))
        XCTAssertEqual(r.poisonTurns, 0)
        XCTAssertTrue(r.debuffImmune)
        var log: [String] = []
        for _ in 0..<3 { Combat.tickEffects(&r, log: &log) }
        XCTAssertFalse(r.debuffImmune, "3 turns")
        _ = Inventory.use(&r, at: 0)
        XCTAssertEqual(r.tempAtk, 8)
        _ = Inventory.use(&r, at: 0)
        XCTAssertTrue(r.markedKill)
    }
}

final class BatchFiveTests: XCTestCase {
    func testTitles() {
        let store = MemoryStore(["dd_mystery_coins": "12"])
        XCTAssertEqual(Titles.current(store), "Wanderer")
        XCTAssertTrue(Titles.select("Undying", store: store), "free")
        XCTAssertFalse(Titles.select("Ancient", store: store), "not bought")
        XCTAssertTrue(Titles.buy("Ancient", store: store))
        XCTAssertEqual(CoinShop.coins(store), 2)
        XCTAssertEqual(Titles.current(store), "Ancient")
        XCTAssertFalse(Titles.buy("Ember", store: store), "can't afford")
        XCTAssertEqual(Titles.grantSeasonal("val-title", store: store), "Beloved")
        XCTAssertTrue(Titles.listed(store).contains { $0.tag == "Beloved" })
        XCTAssertTrue(Titles.select("Beloved", store: store))
    }

    func testRiddles() {
        var r = Run(character: PlayerCharacter(name: "R", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        var boss = Enemy(name: "Boss", icon: "", hp: 100, maxHp: 100, atk: 10...20, gold: 1...1)
        boss.isBoss = true
        Combat.begin(&r, against: boss)
        var d = SeededDice(seed: 2)
        var q: BossRiddles.Riddle?
        for _ in 0..<60 where q == nil { q = BossRiddles.roll(&r, dice: &d) }
        let riddle = try! XCTUnwrap(q)
        XCTAssertNil(BossRiddles.roll(&r, dice: &d), "once a fight")
        XCTAssertEqual(riddle.answers.count, 3)
        r.hp = 10
        XCTAssertTrue(BossRiddles.answer(&r, riddle, choice: riddle.correct).right)
        XCTAssertEqual(r.hp, 69)
        XCTAssertFalse(BossRiddles.answer(&r, riddle, choice: nil).right)
        XCTAssertEqual(r.enemy?.atk, 13...25)
    }

    func testDungeonNewsOnce() {
        let store = MemoryStore()
        XCTAssertNil(DungeonUnlockNews.next(unlocked: ["Crypt of Malachar"], store: store))
        XCTAssertEqual(DungeonUnlockNews.next(unlocked: ["Crypt of Malachar", "The Hollow"], store: store)?.dungeon, "The Hollow")
        XCTAssertNil(DungeonUnlockNews.next(unlocked: ["Crypt of Malachar", "The Hollow"], store: store))
    }

    func testLaterBirthdayCodes() {
        let store = MemoryStore()
        let y2030 = Calendar.current.date(from: DateComponents(year: 2030, month: 3, day: 23))!
        XCTAssertTrue(RewardCodes.redeem("DDBD30", store: store, now: y2030).ok)
        XCTAssertFalse(RewardCodes.redeem("DDBD31", store: store, now: y2030).ok)
    }
}

final class BossTimerTests: XCTestCase {
    func testTimerLengthEnrageAndMinionFallsWithBoss() {
        var r = Run(character: PlayerCharacter(name: "B", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "The Hollow", difficulty: .insane))
        XCTAssertEqual(BossTimer.seconds(for: r), 120)
        r.dungeon = "Crypt of Malachar"
        r.difficulty = .wanderer
        XCTAssertEqual(BossTimer.seconds(for: r), 300)
        var boss = Enemy(name: "Boss", icon: "", hp: 100, maxHp: 100, atk: 10...20, gold: 1...1)
        boss.isBoss = true
        Combat.begin(&r, against: boss)
        XCTAssertFalse(BossTimer.beaten(r))
        var d = SeededDice(seed: 5)
        XCTAssertNotNil(BossTimer.enrage(&r, dice: &d))
        XCTAssertEqual(r.enemy?.atk, 13...25)
        XCTAssertEqual(r.foes.first?.name, "Crypt Stalker")
        // Kill the boss: the minion goes with it.
        r.enemy?.hp = 1
        var dice = LoadedDice(rolls: [99], chances: [])
        _ = Combat.takeTurn(&r, .attack, dice: &dice)
        XCTAssertTrue(r.foes.isEmpty)
    }
}

final class ShadowRealmTests: XCTestCase {
    func testWavesBossesAndTheBoard() {
        var ch = PlayerCharacter(name: "Nyx", cls: "Warrior", race: "Human", prof: "Thief", dungeon: "Crypt of Malachar", difficulty: .wanderer)
        ch.persistLevel = 3
        var s = ShadowRealm.start(ch, weapon: nil, armor: nil)
        XCTAssertEqual(s.maxHp, GameData.classInfo("Warrior").maxHp + 30)
        XCTAssertEqual(s.atk, 14)
        var d = SeededDice(seed: 8)
        _ = ShadowRealm.spawn(&s, dice: &d)
        XCTAssertFalse(s.enemy!.isBoss)
        s.wave = 10
        _ = ShadowRealm.spawn(&s, dice: &d)
        XCTAssertEqual(s.enemy?.name, "Shadow Sovereign")
        XCTAssertEqual(s.enemy?.hp, 280)
        s.enemy?.hp = 1
        let t = ShadowRealm.act(&s, .attack, dice: &d)
        XCTAssertTrue(t.killed)
        XCTAssertEqual(s.kills, 1)
        XCTAssertNotNil(ShadowRealm.drink(&s))
        XCTAssertEqual(s.potions, 2)
        let store = MemoryStore()
        for w in [3, 12, 7] { var r = s; r.wave = w; ShadowRealm.record(r, store: store) }
        XCTAssertEqual(ShadowRealm.board(store).map(\.wave), [12, 7, 3])
    }
}

final class ItemAuditTests: XCTestCase {
    func newRun(_ dungeon: String = "Crypt of Malachar") -> Run {
        var r = Run(character: PlayerCharacter(name: "I", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: dungeon, difficulty: .wanderer))
        r.spirit = nil
        r.inventory = []
        return r
    }

    func testCursedVialAndWardingBell() {
        var r = newRun()
        r.inventory = [Item(name: "Cursed Vial", icon: "🌀", type: "cursed", desc: "")]
        var d = LoadedDice(rolls: [5])
        let out = Inventory.use(&r, at: 0, dice: &d)
        XCTAssertTrue(out.used)
        XCTAssertEqual(out.gold, 40)
        XCTAssertTrue(r.inventory.isEmpty)
        r.inventory = [Item(name: "Warding Bell", icon: "🔔", type: "warding-bell", desc: "")]
        XCTAssertTrue(Inventory.use(&r, at: 0).used)
        XCTAssertEqual(r.wardingBell, 1)
        // A trap is sensed and the bell is spent.
        r.firstSearchDone = true
        var trap = LoadedDice(rolls: [], chances: [false, true])
        let f = Inventory.search(&r, dice: &trap, wallet: Wallet(store: MemoryStore()))
        XCTAssertEqual(f.trap, "avoided")
        XCTAssertEqual(r.wardingBell, 0)
    }

    func testEnchanterIsKeptAndExplained() {
        var r = newRun()
        r.inventory = [Drops.enchanter()]
        let out = Inventory.use(&r, at: 0)
        XCTAssertFalse(out.used)
        XCTAssertTrue(out.message.contains("3 charges"))
        var d = LoadedDice(chances: [true])
        XCTAssertNotNil(Drops.rollEnchanter(&r, dice: &d))
    }

    func testDrownedKingRisesOnce() {
        var r = newRun("The Abyssal Deep")
        var king = Enemy(name: "The Drowned King", icon: "👑", hp: 5, maxHp: 90, atk: 1...1, gold: 1...1)
        king.mechanics["resurrect"] = .bool(true)
        Combat.begin(&r, against: king)
        var d = LoadedDice(rolls: [99])
        let t1 = Combat.takeTurn(&r, .attack, dice: &d)
        XCTAssertFalse(t1.enemyDied)
        XCTAssertEqual(r.enemy?.hp, 1)
        var d2 = LoadedDice(rolls: [99])
        XCTAssertTrue(Combat.takeTurn(&r, .attack, dice: &d2).enemyDied)
    }

    func testPreBossMinions() {
        var r = newRun()
        r.difficulty = .nightmare
        var d = SeededDice(seed: 3)
        let m = PreBossGauntlet.minion(for: r, wave: 1, of: 2, dice: &d)
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.number("preBossWave"), 1)
        XCTAssertFalse(m!.isElite)
    }
}

final class SkillOrbTests: XCTestCase {
    func testFallenCharacterLeavesOrbsForSameClass() {
        let store = MemoryStore(["dd_global_gold": "1000"])
        let w = Wallet(store: store)
        _ = Home.upgradeSkill(cls: "Warrior", name: "Shield Bash", store: store, wallet: w, now: 0)
        _ = Home.upgradeSkill(cls: "Warrior", name: "Shield Bash", store: store, wallet: w, now: 0)
        XCTAssertEqual(Home.makeSkillOrbs(fromChar: "Brom", store: store), 1)
        XCTAssertTrue(Home.skillLevels(store).isEmpty)
        let orbs = Home.skillOrbs(store)
        XCTAssertEqual(orbs.first?.skillName, "Shield Bash")
        XCTAssertEqual(orbs.first?.className, "Warrior")
        XCTAssertEqual(orbs.first?.level, 3)
        XCTAssertFalse(Home.useSkillOrb(at: 0, cls: "Mage", store: store).used)
        XCTAssertTrue(Home.useSkillOrb(at: 0, cls: "Warrior", store: store).used)
        XCTAssertEqual(Home.skillLevels(store)["Warrior_Shield_Bash"], 3)
        XCTAssertTrue(Home.skillOrbs(store).isEmpty)
        XCTAssertEqual(Home.makeSkillOrbs(fromChar: "Brom", store: store), 1)
    }
}

final class ShapeshifterMaskTests: XCTestCase {
    func testMaskCopiesAbilityOncePerRun() {
        var r = Run(character: PlayerCharacter(name: "M", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        var mask = Item(name: "Shapeshifter's Mask", icon: "🎭", type: "consumable", desc: "")
        mask.extra["shadowItem"] = .string("shapeshifterMask")
        r.inventory = [mask, mask]
        XCTAssertFalse(Inventory.use(&r, at: 0).used)
        var e = Enemy(name: "Reflection", icon: "🪞", hp: 50, maxHp: 50, atk: 5...5, gold: 0...0)
        e.mechanics["reflection"] = .bool(true)
        r.enemy = e
        r.inCombat = true
        let out = Inventory.use(&r, at: 0)
        XCTAssertTrue(out.used)
        XCTAssertTrue(out.message.contains("reflection"))
        XCTAssertFalse(Inventory.use(&r, at: 0).used)
        var log: [String] = []
        XCTAssertEqual(ShapeshifterMask.incoming(&r, 12, log: &log), 0)
        XCTAssertEqual(r.enemy?.hp, 38)
        XCTAssertEqual(ShapeshifterMask.incoming(&r, 12, log: &log), 12)
    }

    func testSecondLife() {
        var r = Run(character: PlayerCharacter(name: "M", cls: "Warrior", race: "Human", prof: "Thief",
                                               dungeon: "Crypt of Malachar", difficulty: .wanderer))
        r.fight.mask = "twiceDead"
        r.hp = 5
        var log: [String] = []
        XCTAssertEqual(ShapeshifterMask.incoming(&r, 20, log: &log), 0)
        XCTAssertEqual(r.hp, r.maxHp / 2)
    }
}

final class DungeonTipsTests: XCTestCase {
    func testEachTipShowsOnce() {
        let store = MemoryStore()
        XCTAssertNotNil(DungeonTips.take("first-boss", store: store))
        XCTAssertNil(DungeonTips.take("first-boss", store: store))
        XCTAssertNil(DungeonTips.take("nope", store: store))
        XCTAssertEqual(DungeonTips.seen(store), ["first-boss"])
    }
}

final class LegacyAndJuly4Tests: XCTestCase {
    func testLegacyCarriesLevelAndScalesByTier() {
        var ch = PlayerCharacter(name: "L", cls: "Warrior", race: "Human", prof: "Thief",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer, runMode: "legacy")
        var r = Run(character: ch)
        r.level = 7
        r.unlockedSkills = ["a"]
        XCTAssertNotNil(Legacy.cleared(&ch, run: r))
        XCTAssertEqual(ch.dungeonTier, 2)
        XCTAssertEqual(ch.persistLevel, 7)
        var next = Run(character: ch)
        XCTAssertEqual(Legacy.start(&next, ch).count, 2)
        XCTAssertEqual(next.level, 7)
        XCTAssertEqual(next.levelPoints, 18)
        XCTAssertEqual(next.unlockedSkills, ["a"])
        var e = Enemy(name: "X", icon: "x", hp: 100, maxHp: 100, atk: 10...20, gold: 10...10)
        Legacy.shape(&e, next)
        XCTAssertEqual(e.hp, 120)
        XCTAssertEqual(e.atk, 11...22)
        XCTAssertEqual(e.gold.lowerBound, 12)
    }

    func testClassicNeverScales() {
        let ch = PlayerCharacter(name: "C", cls: "Warrior", race: "Human", prof: "Thief",
                                 dungeon: "Crypt of Malachar", difficulty: .wanderer)
        var r = Run(character: ch)
        XCTAssertTrue(Legacy.start(&r, ch).isEmpty)
        XCTAssertEqual(r.legacyTier, 1)
    }

    func testIndependenceTournamentOncePerYear() {
        let store = MemoryStore()
        let w = Wallet(store: store)
        let july = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 7, day: 3, hour: 12).date!
        var d = LoadedDice(rolls: [0])
        XCTAssertNil(IndependenceTournament.start(level: 1, store: store, dice: &d, now: Date(timeIntervalSince1970: 0)))
        XCTAssertNotNil(IndependenceTournament.start(level: 1, store: store, dice: &d, now: july))
        XCTAssertEqual(IndependenceTournament.state(store).target, 600)
        for _ in 0..<23 { XCTAssertNil(IndependenceTournament.kill(store: store, wallet: w, now: july)) }
        XCTAssertNotNil(IndependenceTournament.kill(store: store, wallet: w, now: july))
        XCTAssertEqual(w.gold, 500)
        XCTAssertEqual(store.getItem("dd_trophies"), "5")
        var d2 = LoadedDice(rolls: [0])
        XCTAssertNil(IndependenceTournament.start(level: 1, store: store, dice: &d2, now: july))
    }
}

final class CommandCenterTests: XCTestCase {
    let acct = CommandCenter.Account(gold: 120, characters: 2, fragments: 3, coins: 4)

    func testCommands() {
        var cc = CommandCenter()
        XCTAssertEqual(cc.run("gold", account: acct, scheduled: false).spoken, "You have 120 gold.")
        if case .go(let d)? = cc.run("go hall of records", account: acct, scheduled: false).action { XCTAssertEqual(d, "hall of records") } else { XCTFail() }
        XCTAssertNil(cc.run("go nowhere", account: acct, scheduled: false).action)
        if case .redeem(let c)? = cc.run("redeem ddbd26", account: acct, scheduled: false).action { XCTAssertEqual(c, "DDBD26") } else { XCTFail() }
        XCTAssertNil(cc.run("cancel schedule", account: acct, scheduled: false).action)
        XCTAssertEqual(cc.run("blah", account: acct, scheduled: false).lines.last?.kind, .err)
    }

    func testParseTime() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 22))!
        XCTAssertEqual(CommandCenter.parseTime("12am", now: now, calendar: cal), cal.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 0)))
        XCTAssertEqual(CommandCenter.parseTime("11:30pm", now: now, calendar: cal), cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 30)))
        XCTAssertEqual(CommandCenter.parseTime("7:05", now: now, calendar: cal), cal.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 7, minute: 5)))
        XCTAssertNil(CommandCenter.parseTime("noonish", now: now, calendar: cal))
        XCTAssertNil(CommandCenter.parseTime("25:00", now: now, calendar: cal))
    }

    func testTerminalCreator() {
        var cc = CommandCenter()
        _ = cc.run("create character", account: acct, scheduled: false)
        XCTAssertTrue(cc.creating)
        XCTAssertEqual(cc.run("zzz", account: acct, scheduled: false).lines.last?.kind, .err)
        for s in ["1", "elf", "3", "frost", "1", "Aria"] { _ = cc.run(s, account: acct, scheduled: false) }
        let r = cc.run("no", account: acct, scheduled: false)
        guard case .create(let ch, let afk)? = r.action else { return XCTFail() }
        XCTAssertFalse(afk)
        XCTAssertEqual(ch.name, "Aria")
        XCTAssertEqual(ch.cls, GameData.classes[0].id)
        XCTAssertEqual(ch.race, "Elf")
        XCTAssertEqual(ch.dungeon, "Frosthold Abyss")
        XCTAssertFalse(cc.creating)
    }
}
