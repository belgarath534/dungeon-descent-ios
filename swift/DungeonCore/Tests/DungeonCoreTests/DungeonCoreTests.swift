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
