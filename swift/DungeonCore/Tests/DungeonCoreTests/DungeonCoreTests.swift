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
        Run(character: PlayerCharacter(name: "T", cls: cls, race: "Human", prof: prof,
                                 dungeon: "Crypt of Malachar", difficulty: diff))
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
        Run(character: PlayerCharacter(name: "P", cls: cls, race: race, prof: prof,
                                 dungeon: "Crypt of Malachar", difficulty: diff))
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
        Run(character: PlayerCharacter(name: "I", cls: cls, race: "Human", prof: prof,
                                       dungeon: "Crypt of Malachar", difficulty: .wanderer))
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
        a.hp = 1
        a.inventory = [item("Health Potion")]
        _ = Inventory.use(&a, at: 0)
        XCTAssertEqual(a.hp, 55)   // round(40 × 1.35) = 54, +1

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

        let g = newRun("Warrior", race: "Gnome")
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
        XCTAssertEqual(abyss, ["abyssal-singing", "abyssal-crack", "abyssal-ship", "abyssal-shrine"])
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
        last.dungeon = "The Abyssal Deep"
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
