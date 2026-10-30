import Foundation

/// XP, level-ups, level points, kill rewards and lives.
/// Ports of gainXP / checkLevelUp / LP_STATS / enemyDead's payout / handleDeath.
public enum Progression {
    /// XP needed to go from each level to the next (XP_TABLE).
    public static let xpTable = [0, 100, 220, 380, 580, 820, 1100, 1430, 1810, 2240, 9999]

    public enum Tier: String, Sendable { case t1, t2, t3, boss }

    public static func xp(for tier: Tier) -> Int {
        switch tier {
        case .t1: return 15
        case .t2: return 28
        case .t3: return 45
        case .boss: return 120
        }
    }

    /// Like getEnemyTier(): anything not in tier 1, tier 2 or the bosses counts as tier 3.
    public static func tier(of name: String, in dungeon: String, difficulty: GameData.Difficulty = .wanderer) -> Tier {
        let pool = Bestiary.enemies(for: dungeon, difficulty: difficulty)
        if pool.t1.contains(where: { $0.name == name }) { return .t1 }
        if pool.t2.contains(where: { $0.name == name }) { return .t2 }
        if pool.bosses.contains(where: { $0.name == name }) { return .boss }
        return .t3
    }

    public static func xpNeeded(atLevel level: Int) -> Int {
        xpTable[min(level, xpTable.count - 1)]
    }

    /// Adds XP and levels up as far as it reaches. Returns how many levels
    /// were gained. Each batch of level-ups gives 3 level points, once.
    @discardableResult
    public static func gainXP(_ run: inout Run, _ amount: Int) -> Int {
        guard amount > 0 else { return 0 }
        var amount = amount
        if run.pilgrimProf { amount = jsRound(Double(amount) * 1.15) }
        // Ancient Knowledge: the web version sold it but never applied it.
        if run.has("cu-xp-boost") { amount = jsRound(Double(amount) * 1.15) }
        if run.backstoryXPBonus > 0 { amount = jsRound(Double(amount) * (1 + run.backstoryXPBonus)) }
        if let ev = Events.bonuses(run.event), ev.xpMult != 1 { amount = jsRound(Double(amount) * ev.xpMult) }
        if DailyChallenge.xpMult(run) != 1 { amount = jsRound(Double(amount) * DailyChallenge.xpMult(run)) }
        if run.xpBoostFloors > 0 { amount = jsRound(Double(amount) * run.xpBoostMult) }
        run.xp += amount
        guard run.level < run.levelCap else { return 0 }
        var needed = xpNeeded(atLevel: run.level)
        var gained = 0
        while run.xp >= needed && run.level < run.levelCap {
            run.xp -= needed
            run.level += 1
            gained += 1
            needed = xpNeeded(atLevel: run.level)
        }
        if gained > 0 { run.levelPoints += 3 }
        Races.onLevelUp(&run, levels: gained)
        if gained > 0 && run.backstorySPBonus > 0 {
            run.maxSp += run.backstorySPBonus * gained
            run.sp = min(run.maxSp, run.sp + run.backstorySPBonus * gained)
        }
        return gained
    }

    /// Stats a level point can be spent on (LP_STATS).
    public enum Stat: String, CaseIterable, Sendable {
        case strength, stamina, defense, intelligence, agility, luck

        public var label: String {
            switch self {
            case .strength: return "Strength"
            case .stamina: return "Stamina"
            case .defense: return "Defense"
            case .intelligence: return "Intelligence"
            case .agility: return "Agility"
            case .luck: return "Luck"
            }
        }

        public var summary: String {
            switch self {
            case .strength: return "+2 ATK — hit harder"
            case .stamina: return "+10 max HP — survive longer"
            case .defense: return "+2 DEF — reduce damage taken"
            case .intelligence: return "+5 max SP — more skill energy"
            case .agility: return "+3% crit chance and +5% flee chance"
            case .luck: return "+10% gold drops and better loot"
            }
        }
    }

    /// Spends one level point. Returns false if there are none left.
    @discardableResult
    public static func spend(_ run: inout Run, on stat: Stat) -> Bool {
        guard run.levelPoints > 0 else { return false }
        switch stat {
        case .strength: run.atkBonus += 2
        case .stamina: run.maxHp += 10; run.hp = min(run.maxHp, run.hp + 10)
        case .defense: run.defBonus += 2
        case .intelligence: run.maxSp += 5; run.sp = min(run.maxSp, run.sp + 5)
        case .agility: run.fleeBonus += 0.05; run.critBonus += 0.03
        case .luck: run.luckBonus += 0.10
        }
        run.levelPoints -= 1
        return true
    }

    public struct KillReward: Equatable, Sendable {
        public var gold: Int
        public var xp: Int
        public var levelsGained: Int
        public var message: String
    }

    /// Pays out for a defeated enemy: gold into the run and the shared wallet, then XP.
    public static func rewardKill(_ run: inout Run, _ enemy: Enemy, dice: inout some Dice, wallet: Wallet) -> KillReward {
        var g = dice.roll(enemy.gold)
        if run.race == "Goblin" { g = jsRound(Double(g) * 1.25) }
        if run.graveRobberLoot { g = jsRound(Double(g) * 1.20) }
        if run.luckBonus != 0 { g = jsRound(Double(g) * (1 + run.luckBonus)) }
        if run.runeFortune { g = jsRound(Double(g) * 1.25) }
        if run.weaponEffect == "fortune" { g = jsRound(Double(g) * 1.25) }
        if run.has("cu-night-blessing") && CoinShop.isNightNow() { g = jsRound(Double(g) * 1.10) }
        if run.dreamGoldMult != 1 { g = jsRound(Double(g) * run.dreamGoldMult) }
        // Event gold bonuses: the web version listed them but never paid them.
        if let ev = Events.bonuses(run.event), ev.goldMult != 1 { g = jsRound(Double(g) * ev.goldMult) }
        g = Challenges.gold(g, run) * Corruption.goldMult(run)
        if let w = run.weather, w.goldMult != 1 { g = jsRound(Double(g) * w.goldMult) }
        let mg = RunModifiers.goldMult(run)
        if mg != 1 { g = jsRound(Double(g) * mg) }
        g += WeaponForge.gold(run)
        var spiritLog: [String] = []
        g = CustomSpirits.gold(run, g, dice: &dice, log: &spiritLog)
        if run.weaponEffect == "soulbound" { run.sp = min(run.maxSp, run.sp + 5) }
        var luckNote = ""
        if run.luckKills > 0 {
            g *= 2
            run.luckKills -= 1
            if run.luckKills == 0 { luckNote = " 🍀 Lucky Potion wore off." }
        }
        run.gold += g
        wallet.addGold(g)
        var xp = Progression.xp(for: tier(of: enemy.name, in: run.dungeon, difficulty: run.difficulty))
        if Challenges.has(run, "double-xp") { xp *= 2 }
        xp *= RunModifiers.xpMult(run)
        xp = CustomSpirits.xp(run, xp)
        let drain = Races.onKill(&run) + ClassTraits.onKill(&run, enemy, dice: &dice)
        let levels = gainXP(&run, xp)
        return KillReward(gold: g, xp: xp, levelsGained: levels,
                          message: "\(enemy.name) is defeated! You gain \(g) gold and \(xp) XP.\(luckNote)\(drain)")
    }

    public enum DeathOutcome: Equatable, Sendable {
        /// A Phoenix Feather burned instead; the fight goes on at 30% HP.
        case phoenix
        /// A resurrection skill brought you back at 50% HP.
        case resurrected
        /// An Undying weapon or Sanctuary armor refused death; you're at 1 HP.
        case gearSaved
        /// Malachar's Crown Fragment: back at 20% HP.
        case crown
        /// Came back at 40% HP with this many lives left.
        case revived(livesLeft: Int)
        /// Second Wind (Coin Shop): back at 1 HP with one life, once per run.
        case secondWind
        case runOver
    }

    /// Loses a life. Revives at 40% HP if any are left. Hardcore and the
    /// cheat-death items and skills are not ported yet.
    public static func handleDeath(_ run: inout Run) -> DeathOutcome {
        run.diedThisRun = true
        if !run.gearSavedThisFloor && (run.weaponEffect == "undying" || run.armorEffect == "sanctuary") {
            run.gearSavedThisFloor = true
            run.hp = 1
            return .gearSaved
        }
        var cd = SystemDice()
        if BossRelics.crownSaves(&run, dice: &cd) { return .crown }
        if Inventory.usePhoenixFeather(&run) { return .phoenix }
        if run.resurrection {
            run.resurrection = false
            run.hp = jsRound(Double(run.maxHp) * 0.5)
            return .resurrected
        }
        // Hardcore: once every cheat-death is spent, the first death is the last.
        if run.hardcore {
            run.lives = 0
            run.inCombat = false
            return .runOver
        }
        run.lives = max(0, run.lives - 1)
        run.inCombat = false
        run.bargainStrike = 0
        // Second Wind: once per run, back at 1 HP with one life.
        if run.lives <= 0 && run.secondWind {
            run.secondWind = false
            run.lives = 1
            run.hp = 1
            run.enemy = nil
            return .secondWind
        }
        // Death's Bargain: one last strike for twice your top attack.
        if run.lives <= 0 && run.deathsBargain, var e = run.enemy, e.hp > 0 {
            run.deathsBargain = false
            let dmg = run.atk.upperBound * 2
            e.hp = max(0, e.hp - dmg)
            run.enemy = e
            run.bargainStrike = dmg
        }
        if run.lives <= 0 { return .runOver }
        run.hp = jsRound(Double(run.maxHp) * 0.4)
        run.enemy = nil
        return .revived(livesLeft: run.lives)
    }
}
