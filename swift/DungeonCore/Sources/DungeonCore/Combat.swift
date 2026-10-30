import Foundation

public enum PlayerAction: String, Sendable {
    case attack, heavy, defend, flee
}

/// What happened in one combat turn. `log` lines are worded like the web
/// version's combat log; `announcement` is the short line for VoiceOver.
public struct TurnResult: Equatable, Sendable {
    public var playerDamage = 0
    public var crit = false
    public var missed = false
    public var fled = false
    /// nil when the enemy didn't get to attack.
    public var enemyDamage: Int? = nil
    public var enemyDied = false
    public var playerDied = false
    /// Set when a boss moved to a new phase this turn (it skips its counter).
    public var bossPhaseMessage: String? = nil
    /// False when a skill couldn't be used (not enough SP …); nothing happened.
    public var acted = true
    /// A cowardly enemy ran away, dropping this much gold.
    public var enemyFled = false
    public var goldGained = 0
    /// The enemy this turn killed (the target), and any ambusher that fell to
    /// reflected damage on its own turn.
    public var defeated: Enemy? = nil
    public var alsoDefeated: [Enemy] = []
    /// The target fell but the rest of the ambush fights on.
    public var ambushContinues = false
    public var log: [String] = []
    public var announcement: String? = nil
}

/// The fight loop from doFight() and useSkill(): your action, then the enemy's
/// turn. Weapon rarity effects, spirits and enemy special abilities are not
/// ported yet.
public enum Combat {
    public struct Options: Sendable {
        /// Accessibility setting "class traits" (on by default in the web version).
        public var classTraits = true
        public init(classTraits: Bool = true) { self.classTraits = classTraits }
    }

    /// Returns log lines from the spirit's combat-start effect.
    @discardableResult
    public static func begin(_ run: inout Run, against enemy: Enemy) -> [String] {
        run.enemy = enemy
        run.foes = []
        run.inCombat = true
        run.defending = false
        run.fight = FightEffects()
        run.fight.huntersMarkReady = run.has("cu-hunters-mark")
        run.fight.phantomCrit = RunModifiers.firstStrikeCrit(run)
        if enemy.isBoss { run.bossPhase = 1 }
        var log: [String] = []
        if TimeDescender.isDescender(enemy) && !TimeDescender.isClock(enemy) {
            run.timeDescenderMet = true
            log.append("⏳ Time fractures. The Time Descender emerges, unbound by the dungeon's usual rules.")
        }
        if Medusa.isMedusa(enemy) {
            run.medusa.met = true
            run.devMedusa = false
            log.append("A rare figure steps from the shadows of the Hollow. Medusa. Her eyes are closed. For now. Her gaze can petrify you.")
        }
        if Medusa.walksWithYou(run) {
            run.fight.medusaGuard = true
            log.append("🐍 Medusa stands beside you. Serpent Guard — she will absorb one attack this fight.")
        }
        Alchemy.combatStart(&run, log: &log)
        Spirits.combatStart(&run, log: &log)
        ShadowWorld.combatStart(&run, log: &log)
        Spells.combatStart(&run, log: &log)
        ClassTraits.combatStart(&run, log: &log)
        return log
    }

    /// Picks and scales the next normal enemy for the current floor.
    public static func nextEnemy(for run: Run, dice: inout some Dice) -> Enemy {
        let tables = Bestiary.enemies(for: run.dungeon, difficulty: run.difficulty)
        // 15% elite chance from floor 4 (enterRoom)
        let elite = run.floor >= 4 && !tables.elites.isEmpty && dice.chance(0.15)
        let pool = elite ? tables.elites : tables.pool(forFloor: run.floor)
        if !elite, var td = TimeDescender.encounter(for: run, dice: &dice) {
            if run.worldCurse { cursed(&td) }
            Challenges.shape(&td, run)
            return td
        }
        if !elite, var special = Medusa.encounter(for: run, dice: &dice) {
            if run.worldCurse { cursed(&special) }
            Challenges.shape(&special, run)
            return special
        }
        if !elite, var shade = WhisperingForest.shade(for: run, dice: &dice) {
            if run.worldCurse { cursed(&shade) }
            Challenges.shape(&shade, run)
            return shade
        }
        if !elite, var stalker = Corruption.hunter(for: run, dice: &dice) {
            if run.worldCurse { cursed(&stalker) }
            Challenges.shape(&stalker, run)
            return stalker
        }
        if !elite, var nm = DailyChallenge.nightmareEnemy(for: run, dice: &dice) {
            if run.worldCurse { cursed(&nm) }
            Challenges.shape(&nm, run)
            return nm
        }
        if !elite, var ce = CommunityEnemies.spawn(for: run, dice: &dice) {
            Legacy.shape(&ce, run)
            return ce
        }
        if !elite, var seasonal = Events.seasonalEnemy(run, dice: &dice) {
            Challenges.shape(&seasonal, run)
            return seasonal
        }
        let t = pool[dice.roll(0...(pool.count - 1))]
        var e = Enemy.spawn(t, floor: run.floor, playerLevel: run.level,
                            ngPlusCount: ngCount(run), endless: run.difficulty == .endless)
        // The event's enemy strength scales normal enemies too.
        if !elite, let m = Events.bonuses(run.event)?.enemyMult, m != 1 {
            e.hp = jsRound(Double(e.hp) * m)
            e.maxHp = e.hp
            let lo = jsRound(Double(e.atk.lowerBound) * m), hi = jsRound(Double(e.atk.upperBound) * m)
            e.atk = lo...max(lo, hi)
        }
        // The Hollow's Full Moon: 20% stronger.
        if let m = run.weather?.enemyMult, m != 1 {
            e.hp = jsRound(Double(e.hp) * m)
            e.maxHp = e.hp
            let lo = jsRound(Double(e.atk.lowerBound) * m), hi = jsRound(Double(e.atk.upperBound) * m)
            e.atk = lo...max(lo, hi)
        }
        if !elite { DailyChallenge.shape(&e, run) }
        if run.worldCurse { cursed(&e) }
        Challenges.shape(&e, run)
        Legacy.shape(&e, run)
        return e
    }

    /// The Void Curse (a Void Reaper left standing): 50% more HP and attack.
    static func cursed(_ e: inout Enemy) {
        e.hp = jsRound(Double(e.hp) * 1.5)
        e.maxHp = e.hp
        let lo = jsRound(Double(e.atk.lowerBound) * 1.5), hi = jsRound(Double(e.atk.upperBound) * 1.5)
        e.atk = lo...max(lo, hi)
    }

    /// Floor 10's Elite Guardian before the boss (startEliteGauntlet): a tier 3
    /// enemy of the dungeon with 50% more HP and 30% more attack.
    public static func eliteGuardian(for run: Run, dice: inout some Dice) -> Enemy {
        let pool = Bestiary.enemies(for: run.dungeon, difficulty: run.difficulty).t3
        let t = pool[dice.roll(0...(pool.count - 1))]
        let ng = run.ngPlus ? 1.20 : 1.0
        let diff: Double = run.difficulty == .nightmare ? 1.5 : run.difficulty == .forsaken ? 1.3
            : run.difficulty == .condemned ? 1.15 : 1.0
        let hp = jsRound(Double(t.hp) * 1.5 * ng * diff)
        let lo = jsRound(Double(t.atk.lowerBound) * 1.3 * ng)
        let hi = jsRound(Double(t.atk.upperBound) * 1.3 * ng)
        var e = Enemy(name: t.name, icon: t.icon, hp: hp, maxHp: hp, atk: lo...max(lo, hi), gold: t.gold)
        e.isElite = true
        e.mechanics["guardian"] = .bool(true)
        Challenges.shape(&e, run)
        Legacy.shape(&e, run)
        return e
    }

    /// Picks and scales the boss for the run's dungeon.
    public static func nextBoss(for run: Run, dice: inout some Dice) -> Enemy {
        var pool = Bestiary.enemies(for: run.dungeon, difficulty: run.difficulty).bosses
        // The Shadow World's floor 10 is The Echo; The Shapeshifter comes after it.
        if run.dungeon == ShadowWorld.name {
            let echoes = pool.filter { $0.mechanics["isEcho"] == .bool(true) }
            if !echoes.isEmpty { pool = echoes }
        }
        let t = pool[dice.roll(0...(pool.count - 1))]
        var b = Enemy.spawnBoss(t, playerLevel: run.level, playerMaxAtk: run.atk.upperBound, ngPlusCount: ngCount(run))
        if run.worldCurse { cursed(&b) }
        Challenges.shape(&b, run)
        Legacy.shape(&b, run)
        return b
    }

    /// Your attack roll for this turn: class range plus every bonus.
    static func attackRoll(_ run: Run, dice: inout some Dice) -> Int {
        var a = dice.roll(run.atk) + run.totalAtkBonus
        if let w = run.weather, w.playerAtkMult != 1 { a = jsRound(Double(a) * w.playerAtkMult) }
        let am = RunModifiers.attackMult(run)
        if am != 1 { a = jsRound(Double(a) * am) }
        // Blood Moon and the Liberty Shop's Sparkler.
        if let ev = Events.bonuses(run.event), ev.atkBoost > 0 { a = jsRound(Double(a) * (1 + ev.atkBoost)) }
        if run.sparkler { a = jsRound(Double(a) * 1.30) }
        let dc = DailyChallenge.attackMult(run)
        if dc != 1 { a = jsRound(Double(a) * dc) }
        return a
    }

    /// Bonuses that apply to every hit you land: vulnerability and masteries.
    static func scaleDamage(_ run: Run, _ dmg: Int, skill: Bool = false) -> Int {
        guard dmg > 0 else { return 0 }
        var m = 1 + run.allDamageBonus
        if skill { m += run.skillDamageBonus + Subclasses.skillDamageBonus(run) + ClassTraits.skillDamageBonus(run) }
        if run.fight.vulnerableTurns > 0 { m += run.fight.vulnerable }
        return jsRound(Double(dmg) * m)
    }

    /// One full turn: the player's action, then the enemy's turn if it survived.
    public static func takeTurn(_ run: inout Run, _ action: PlayerAction, dice: inout some Dice,
                                options: Options = Options()) -> TurnResult {
        guard run.inCombat, run.enemy != nil else { return TurnResult() }
        var r = TurnResult()
        Spells.tick(&run, log: &r.log)
        if Spells.realityLost(run, now: Date()) {
            run.hp = 0
            run.inCombat = false
            r.log.append("🌀 Time is up. You cease to exist.")
            r.playerDied = true
            r.announcement = r.log.last
            return r
        }

        var baseAtk = attackRoll(run, dice: &dice)
        run.defending = false
        // Coin Shop upgrades (doFight)
        if run.has("cu-berserker-mark") && Double(run.hp) <= Double(run.maxHp) * 0.5 { baseAtk += 3 }
        if run.fight.huntersMarkReady {
            baseAtk = jsRound(Double(baseAtk) * 1.5)
            run.fight.huntersMarkReady = false
            r.log.append("🏹 Hunter's Mark — critical first strike!")
        } else if run.shadowNotes {
            baseAtk = jsRound(Double(baseAtk) * 1.5)
            run.shadowNotes = false
            r.log.append("📝 Your notes were right. Critical hit!")
        }
        if run.has("cu-night-blessing") && CoinShop.isNightNow() { baseAtk += 5 }
        baseAtk = Subclasses.attackBonus(&run, baseAtk, dice: &dice, log: &r.log)
        baseAtk = ShadowWorld.attackRoll(&run, baseAtk, log: &r.log)
        baseAtk = ShapeshifterMask.attackRoll(&run, baseAtk, log: &r.log)
        if action == .attack || action == .heavy { baseAtk = Alchemy.rage(&run, baseAtk, log: &r.log) }

        if run.frozen {
            run.frozen = false
            r.log.append("You are frozen and cannot act this turn!")
        } else {
            switch action {
            case .attack:
                // Rolled first, like `Math.random() < p || markedKill` in the web version.
                // The Unlucky One: your luck is zero.
                let unlucky = run.enemy?.flag("unlucky") == true
                let rolledCrit = dice.chance(0.10 + run.critBonus + CustomSpirits.crit(run) + (run.weaponEffect == "keen" ? 0.05 : 0) + WeaponForge.critBonus(run)) && !unlucky
                let firstBlood = ClassTraits.firstBloodCrit(&run)
                let firstStrike = Subclasses.firstStrikeCrit(&run) || firstBlood
                let phantom = run.fight.phantomCrit
                run.fight.phantomCrit = false
                r.crit = rolledCrit || run.markedKill || firstStrike || phantom
                if run.markedKill {
                    run.markedKill = false
                    r.log.append("Marked Kill activates — guaranteed critical!")
                }
                var dmg = r.crit ? jsRound(Double(baseAtk) * Subclasses.critMultiplier(run)) : baseAtk
                dmg = Subclasses.afterRoll(&run, dmg, log: &r.log)
                dmg = empowered(&run, dmg, log: &r.log)
                dmg = gearDamage(&run, dmg, log: &r.log)
                r.playerDamage = ClassTraits.attack(&run, Races.attack(run, scaleDamage(run, dmg), dice: &dice, log: &r.log), dice: &dice, log: &r.log)
                r.log.append(r.crit ? "CRITICAL HIT! You strike for \(r.playerDamage) damage!"
                                    : "You attack for \(r.playerDamage) damage.")
            case .heavy:
                if run.weaponEffect != "weighted" && run.subclass != "hawkeye" && run.fight.bloodOath == 0 && dice.chance(0.30) {
                    r.missed = true
                    r.log.append("Your heavy strike misses! The enemy sidesteps.")
                } else {
                    var dmg = empowered(&run, jsRound(Double(baseAtk) * 1.7), log: &r.log)
                    if let e = run.enemy, run.subclass == "crusader", Bestiary.undeadNames.contains(e.name) { dmg = jsRound(Double(dmg) * 1.5) }
                    dmg = gearDamage(&run, dmg, log: &r.log)
                    r.playerDamage = ClassTraits.attack(&run, Races.attack(run, scaleDamage(run, dmg), dice: &dice, log: &r.log), dice: &dice, log: &r.log)
                    r.log.append("Heavy strike lands for \(r.playerDamage) damage!")
                }
            case .defend:
                run.defending = true
                r.playerDamage = scaleDamage(run, jsRound(Double(baseAtk) * 0.5))
                r.log.append("You defend, dealing \(r.playerDamage) and bracing for the counter.")
            case .flee where !ClassTraits.canFlee(run):
                r.log.append("No Retreat — Berserkers cannot flee.")
                r.announcement = "No Retreat. Berserkers do not run."
                r.acted = false
                return r
            case .flee:
                let guaranteed = run.swiftTurns > 0 || run.runeSpeed
                if run.swiftTurns > 0 { run.swiftTurns -= 1 }
                let chance = guaranteed ? 1.0 : (run.hasFleeRing ? 0.75 : 0.45) + run.fleeBonus + CustomSpirits.flee(run)
                    + (run.armorEffect == "light-step" ? 0.10 : 0)
                if dice.chance(chance) {
                    r.fled = true
                    run.inCombat = false
                    run.enemy = nil
                    run.foes = []
                    let msg = guaranteed ? "💨 Swift as a ghost — you vanish before they can react."
                                         : "You slip into the shadows. The enemy's howl fades behind you."
                    r.log.append(msg)
                    r.announcement = "You successfully fled!"
                    return r
                }
                r.log.append("You attempt to flee — but there is nowhere to go.")
            }
        }

        if (action == .attack || action == .heavy) && r.playerDamage > 0 {
            r.playerDamage = Spells.shapeAttack(&run, r.playerDamage, heavy: action == .heavy, log: &r.log)
            if r.playerDamage > 0 { run.fight.lastAttack = r.playerDamage }
        }
        // Weapon wear (degradeWeapon): worn-out blades hit softer.
        if (action == .attack || action == .heavy) && r.playerDamage > 0 {
            let m = Blacksmith.damageMultiplier(run)
            if m != 1 { r.playerDamage = jsRound(Double(r.playerDamage) * m) }
            Blacksmith.degrade(&run, by: action == .heavy ? 2 : 1, log: &r.log)
        }
        // Thunderfist
        if action == .attack, r.playerDamage > 0, case .number(let p)? = run.equippedWeapon?.extra["stunChance"],
           var e = run.enemy, dice.chance(p) {
            e.stunTurns = max(e.stunTurns, 1)
            run.enemy = e
            r.log.append("⚡ Thunderfist stuns \(e.name)! They skip their next attack.")
        }
        r.playerDamage = EnemyAbilities.onPlayerHit(&run, r.playerDamage, basic: true, dice: &dice, log: &r.log)
        r.playerDamage = ShadowWorld.onHit(&run, r.playerDamage, basic: true, heavy: action == .heavy, log: &r.log)
        dealDamage(&run, r.playerDamage, log: &r.log)
        Alchemy.corrupt(&run, log: &r.log)
        if action == .attack || action == .heavy {
            Alchemy.leech(&run, r.playerDamage, log: &r.log)
            afterGearHit(&run, r.playerDamage, dice: &dice, log: &r.log)
            Subclasses.onHit(&run, r.playerDamage, dice: &dice, log: &r.log)
        }
        if action == .attack { Spirits.attack(&run, base: baseAtk, dice: &dice, log: &r.log) }
        minionAttack(&run, dice: &dice, log: &r.log)
        ClassTraits.allyAttack(&run, dice: &dice, log: &r.log)
        Subclasses.companionAttack(&run, dice: &dice, log: &r.log)
        return finishTurn(&run, r, skipEnemy: false, dice: &dice, options: options)
    }

    /// Weapon and armor rarity effects on your attacks.
    static func gearDamage(_ run: inout Run, _ dmg: Int, log: inout [String]) -> Int {
        guard let e = run.enemy else { return dmg }
        var d = Double(dmg)
        let firstHit = !run.fight.firstHitDone
        run.fight.firstHitDone = true
        switch run.weaponEffect {
        case "swift" where firstHit: d *= 1.20; log.append("⚔ Swift blade strikes first — +20% opening damage!")
        case "cursed": d *= 1.40
        case "apocalypse": d *= 1.60
        case "godslayer" where e.isBoss: d *= 2
        case "executioner" where Double(e.hp) / Double(max(1, e.maxHp)) < 0.25:
            d *= 1.50
            log.append("💀 Executioner strikes the weakened foe — +50% damage!")
        default: break
        }
        if run.armorEffect == "aegis" { d *= 0.80 }
        return WeaponForge.damage(run, jsRound(d), log: &log)
    }

    /// Effects that follow a landed hit: second strikes, stuns and healing.
    static func afterGearHit(_ run: inout Run, _ dmg: Int, dice: inout some Dice, log: inout [String]) {
        WeaponForge.afterHit(&run, dmg, dice: &dice, log: &log)
        guard dmg > 0, var e = run.enemy, !e.isDead else { return }
        switch run.weaponEffect {
        case "serrated" where dice.chance(0.15):
            e.hp = max(0, e.hp - dmg)
            log.append("🗡 Serrated edge — you strike twice for another \(dmg)!")
        case "thundering" where dice.chance(0.25):
            e.stunTurns = max(e.stunTurns, 1)
            log.append("⚡ Thunder rolls — \(e.name) is stunned!")
        case "vampiric":
            run.hp = min(run.maxHp, run.hp + 3)
        case "lifesteal":
            let h = jsRound(Double(dmg) * 0.15)
            run.hp = min(run.maxHp, run.hp + h)
            if h > 0 { log.append("Lifesteal heals \(h) HP.") }
        default: break
        }
        run.enemy = e
    }

    /// Applies empowered-attack bonuses (Sacred Blade, War Ballad …) to a basic attack.
    static func empowered(_ run: inout Run, _ dmg: Int, log: inout [String]) -> Int {
        guard run.fight.empowerCount > 0 else { return dmg }
        run.fight.empowerCount -= 1
        return jsRound(Double(dmg) * run.fight.empower)
    }

    /// Damage to the enemy, plus healing from Holy Crusade.
    /// minionCombatAttack: your minion strikes after you each round, for
    /// its attack plus 0–3; an elite one has a 10% chance to hit double.
    static func minionAttack(_ run: inout Run, dice: inout some Dice, log: inout [String]) {
        guard let m = run.minion, var e = run.enemy, !e.isDead else { return }
        var dmg = m.atk + dice.roll(0...3)
        if m.tier == "elite" && dice.chance(0.10) {
            dmg *= 2
            log.append("⭐ \(m.name) lands a devastating critical for \(dmg) damage!")
        } else {
            log.append("👾 \(m.name) attacks for \(dmg) damage!")
        }
        e.hp = max(0, e.hp - dmg)
        run.enemy = e
    }

    static func dealDamage(_ run: inout Run, _ dmg: Int, log: inout [String]) {
        guard dmg > 0, var e = run.enemy else { return }
        e.hp = max(0, e.hp - dmg)
        run.enemy = e
        if run.fight.crusadeTurns > 0 && run.fight.crusadeHeal > 0 {
            run.hp = min(run.maxHp, run.hp + run.fight.crusadeHeal)
            log.append("Holy Crusade heals \(run.fight.crusadeHeal) HP.")
        }
    }

    /// After your action: check for a kill, a boss phase change, then the enemy's turn.
    static func finishTurn(_ run: inout Run, _ result: TurnResult, skipEnemy: Bool,
                           dice: inout some Dice, options: Options) -> TurnResult {
        var r = result
        guard let e = run.enemy else { return r }
        if e.isDead {
            if let lines = ShadowWorld.refusesDeath(&run) {
                r.log += lines
                r.announcement = lines.joined(separator: " ")
                return r
            }
            if let line = resurrects(&run) {
                r.log.append(line)
                r.announcement = line
                return r
            }
            return afterKill(&run, killed(&run, r), dice: &dice, options: options)
        }
        if let msg = checkBossPhase(&run) {
            r.bossPhaseMessage = msg
            r.log.append(msg)
            r.announcement = msg
            return r
        }
        if skipEnemy {
            r.announcement = r.log.last
            return r
        }
        if run.foes.isEmpty, let g = EnemyAbilities.cowardFlees(&run, dice: &dice, log: &r.log) {
            r.enemyFled = true
            r.goldGained = g
            run.kills += 1
            run.inCombat = false
            run.enemy = nil
            r.announcement = r.log.last
            return r
        }

        if Alchemy.timeStopped(&run, log: &r.log) {
            tickEffects(&run, log: &r.log)
            r.announcement = r.log.last
            return r
        }
        let taken = enemiesTurn(&run, &r, dice: &dice, options: options)
        if let dead = run.enemy, dead.isDead {
            if let lines = ShadowWorld.refusesDeath(&run) {
                r.log += lines
                r.announcement = lines.joined(separator: " ")
                return r
            }
            if let line = resurrects(&run) {
                r.log.append(line)
                r.announcement = line
                return r
            }
            return afterKill(&run, killed(&run, r), dice: &dice, options: options)
        }
        r.enemyDamage = taken
        tickEffects(&run, log: &r.log)
        r.announcement = taken > 0
            ? "\(e.name) dealt \(taken) damage. Your HP: \(run.hp) of \(run.maxHp)."
            : "Your HP: \(run.hp) of \(run.maxHp)."
        if run.isDead {
            r.playerDied = true
            run.inCombat = false
        }
        return r
    }

    /// Bomb Thrower: once per floor, 60 damage that ignores everything. It
    /// takes your turn.
    public static func throwBomb(_ run: inout Run, dice: inout some Dice, options: Options = Options()) -> TurnResult {
        var r = TurnResult()
        guard Subclasses.canBomb(run), var e = run.enemy else { r.acted = false; return r }
        run.bombReady = false
        e.hp = max(0, e.hp - 60)
        run.enemy = e
        r.playerDamage = 60
        r.log.append("💣 You throw a bomb! It explodes for 60 damage!")
        return finishTurn(&run, r, skipEnemy: false, dice: &dice, options: options)
    }

    // MARK: Ambushes (MULTI-ENEMY COMBAT SYSTEM)

    /// spawnAmbush: two enemies from floor 3, three from floor 7, from the
    /// floor's pool. (The Shadow World raises echoes instead; see below.)
    public static func ambushers(for run: Run, dice: inout some Dice) -> [Enemy] {
        if run.dungeon == ShadowWorld.name && run.shadowKilled.count >= 2 {
            let count = min(run.shadowKilled.count, run.floor >= 7 ? 3 : 2)
            var pool = run.shadowKilled
            var out: [Enemy] = []
            while out.count < count && !pool.isEmpty {
                var e = pool.remove(at: dice.roll(0...(pool.count - 1)))
                e.name = "Echo of " + e.name
                e.maxHp = max(1, jsRound(Double(e.maxHp) * 0.75))
                e.hp = e.maxHp
                e.turnsTaken = 0
                e.hitsTaken = 0
                e.mechanics["corruptOnHit"] = .number(1)
                out.append(e)
            }
            return out
        }
        let count = run.floor >= 7 ? 3 : 2
        let tables = Bestiary.enemies(for: run.dungeon, difficulty: run.difficulty)
        let pool = tables.pool(forFloor: run.floor)
        guard pool.count >= 1 else { return [] }
        // Ambushers come at their base strength (no floor or level scaling),
        // as in the web version; there are two or three of them.
        return (0..<count).map { _ in Enemy.spawn(pool[dice.roll(0...(pool.count - 1))], floor: 1, playerLevel: 1) }
    }

    /// startMultiCombat: the first enemy is your target; the rest wait their turn.
    @discardableResult
    public static func beginAmbush(_ run: inout Run, _ enemies: [Enemy]) -> [String] {
        guard let first = enemies.first else { return [] }
        var log = begin(&run, against: first)
        run.foes = Array(enemies.dropFirst())
        log.insert("⚡ AMBUSH! \(enemies.count) enemies attack at once: " + enemies.map(\.name).joined(separator: ", ") + "!", at: 0)
        return log
    }

    /// Points your next action at another enemy of the ambush.
    public static func retarget(_ run: inout Run, to index: Int) {
        guard run.foes.indices.contains(index), let current = run.enemy else { return }
        run.enemy = run.foes[index]
        run.foes[index] = current
    }

    /// Every enemy still standing takes its turn: your target, then the rest.
    /// An ambusher that dies on its own turn (thorns, reflection) falls.
    static func enemiesTurn(_ run: inout Run, _ r: inout TurnResult, dice: inout some Dice, options: Options) -> Int {
        var total = enemyTurn(&run, dice: &dice, options: options, log: &r.log)
        var i = 0
        while i < run.foes.count && !run.isDead {
            let target = run.enemy
            run.enemy = run.foes[i]
            total += enemyTurn(&run, dice: &dice, options: options, log: &r.log)
            let foe = run.enemy
            run.enemy = target
            if let foe, !foe.isDead {
                run.foes[i] = foe
                i += 1
            } else {
                run.foes.remove(at: i)
                if let foe {
                    run.kills += 1
                    r.alsoDefeated.append(foe)
                    r.log.append("☠ \(foe.name) falls!")
                }
            }
        }
        return total
    }

    /// After the target dies in an ambush, the next enemy steps up and the
    /// rest take their turns.
    static func afterKill(_ run: inout Run, _ result: TurnResult, dice: inout some Dice, options: Options) -> TurnResult {
        var r = result
        guard !run.foes.isEmpty, !run.isDead else { return r }
        r.ambushContinues = true
        run.enemy = run.foes.removeFirst()
        run.inCombat = true
        let taken = enemiesTurn(&run, &r, dice: &dice, options: options)
        r.enemyDamage = taken
        tickEffects(&run, log: &r.log)
        let left = 1 + run.foes.count
        r.announcement = "\(r.defeated?.name ?? "The enemy") defeated! \(left) \(left == 1 ? "enemy remains" : "enemies remain"). "
            + (taken > 0 ? "You take \(taken) damage. " : "") + "Your HP: \(run.hp) of \(run.maxHp)."
        if run.isDead {
            r.playerDied = true
            run.inCombat = false
        }
        return r
    }

    /// checkAbyssalResurrect: the Drowned King rises once at 1 HP.
    static func resurrects(_ run: inout Run) -> String? {
        guard var e = run.enemy, e.isDead, e.flag("resurrect"), !e.flag("resurrected") else { return nil }
        e.hp = 1
        e.mechanics["resurrected"] = .bool(true)
        run.enemy = e
        return "👑 \(e.name) RESURRECTS at 1 HP! The undead do not yield easily!"
    }

    static func killed(_ run: inout Run, _ result: TurnResult) -> TurnResult {
        var r = result
        r.enemyDied = true
        if run.enemy?.isBoss == true, run.foes.contains(where: { $0.flag("bossMinion") }) {
            run.foes.removeAll { $0.flag("bossMinion") }
            r.log.append("With its master gone, the boss's minion fades into the dark.")
        }
        r.defeated = run.enemy
        if let e = run.enemy, run.dungeon == ShadowWorld.name, !e.isBoss, !e.name.hasPrefix("Echo of") {
            run.shadowKilled.append(e)
            if run.shadowKilled.count > 10 { run.shadowKilled.removeFirst() }
        }
        run.inCombat = false
        run.kills += 1
        if run.fight.warlord {
            run.hp = min(run.maxHp, run.hp + 10)
            run.sp = min(run.maxSp, run.sp + 3)
            r.log.append("Warlord: +10 HP and +3 SP.")
        }
        if run.has("cu-blood-pact") { run.hp = min(run.maxHp, run.hp + 2) }
        if run.equippedWeapon?.extra["soulDrinker"] == .bool(true) {
            run.hp = min(run.maxHp, run.hp + 5)
            r.log.append("🩸 Soul Drinker feeds — you heal 5 HP!")
        }
        if let e = run.enemy { Subclasses.onKill(&run, e, log: &r.log) }
        if let e = run.enemy { var d = SystemDice(); Spells.onKill(&run, e, dice: &d, log: &r.log) }
        r.announcement = "\(run.enemy?.name ?? "The enemy") defeated."
        return r
    }

    /// Standard three-phase bosses: phase 2 at 66% HP hits 25% harder, the
    /// final phase at 33% hits 35% harder. The boss skips its counter on the
    /// turn it changes phase (checkBossPhase).
    static func checkBossPhase(_ run: inout Run) -> String? {
        if let m = ShadowWorld.shapeshifterPhase(&run) { return m }
        guard var e = run.enemy, e.isBoss, !e.isDead, !e.flag("isShapeshifter") else { return nil }
        func scale(_ m: Double) {
            let lo = jsRound(Double(e.atk.lowerBound) * m), hi = jsRound(Double(e.atk.upperBound) * m)
            e.atk = lo...max(lo, hi)
        }
        var msg: String?
        if run.bossPhase == 1 && e.hp <= e.phase1Hp {
            run.bossPhase = 2
            scale(1.25)
            msg = "⚡ PHASE TRANSITION — " + (e.phaseMsg2 ?? "The boss enters phase 2 — it grows more powerful!")
        } else if run.bossPhase == 2 && e.hp <= e.phase2Hp && e.flag("fourPhase") {
            // The Abyssal Deep's four-phase bosses: phase 4 at 15%.
            run.bossPhase = 3
            scale(1.3)
            msg = "⚡ PHASE 3 — " + (e.phaseMsg3 ?? "Phase 3 — the boss grows desperate!")
        } else if run.bossPhase == 2 && e.hp <= e.phase2Hp {
            run.bossPhase = 3
            scale(1.35)
            msg = "⚡ FINAL PHASE — " + (e.phaseMsg3 ?? "Final phase — the boss unleashes everything!")
        } else if run.bossPhase == 3 && e.flag("fourPhase") && e.hp <= jsRound(Double(e.maxHp) * 0.15) {
            run.bossPhase = 4
            scale(1.5)
            var m4 = "The abyss awakens. This is the final phase."
            if case .string(let s)? = e.mechanics["phaseMsg4"] { m4 = s }
            msg = "💀 THE ABYSS AWAKENS — " + m4
            run.fight.rhythmDue = true
        }
        run.enemy = e
        return msg
    }

    /// The enemy's turn: damage over time, then its attack unless it's stunned,
    /// dodged or misses. Defense blocks at most 60% of a hit, and every hit
    /// does at least 1 damage. Returns the damage you took.
    static func enemyTurn(_ run: inout Run, dice: inout some Dice,
                          options: Options, log: inout [String]) -> Int {
        guard var e = run.enemy else { return 0 }

        if e.dotTurns > 0 {
            e.dotTurns -= 1
            e.hp = max(0, e.hp - e.dotDamage)
            log.append("\(e.name) takes \(e.dotDamage) damage over time. (\(e.dotTurns) turns left)")
            if e.isDead { run.enemy = e; return 0 }
        }
        if run.fight.stickyBomb > 0 {
            let boom = run.fight.stickyBomb
            run.fight.stickyBomb = 0
            e.hp = max(0, e.hp - boom)
            log.append("💥 The sticky bomb explodes for \(boom) damage!")
            if e.isDead { run.enemy = e; return 0 }
        }
        if run.fight.decayTurns > 0 {
            run.fight.decayTurns -= 1
            let lo = max(1, e.atk.lowerBound - run.fight.decay), hi = max(1, e.atk.upperBound - run.fight.decay)
            e.atk = lo...max(lo, hi)
            log.append("Death and Decay saps \(e.name)'s strength.")
        }
        run.enemy = e
        ShapeshifterMask.enemyTurn(&run, log: &log)
        if run.enemy?.isDead == true { return 0 }

        if Spells.beforeEnemy(&run, log: &log) { return 0 }
        guard let after = run.enemy, !after.isDead else { return 0 }
        e = after
        if e.stunTurns > 0 {
            e.stunTurns -= 1
            run.enemy = e
            log.append("\(e.name) cannot act this turn!")
            return 0
        }
        if run.fight.dodges > 0 {
            run.fight.dodges -= 1
            log.append("You avoid \(e.name)'s attack completely!")
            return 0
        }
        if Alchemy.avoids(&run, e, dice: &dice, log: &log) { return 0 }
        if Races.dodges(run, e, dice: &dice, log: &log) { return 0 }
        if ClassTraits.avoids(run, e, dice: &dice, log: &log) { return 0 }
        if run.fight.enemyMiss > 0 {
            let p = run.fight.enemyMiss
            run.fight.enemyMiss = 0
            if dice.chance(p) {
                log.append("\(e.name) misses you!")
                return 0
            }
        }
        if run.fight.confuseTurns > 0 && dice.chance(run.fight.confuse) {
            let selfHit = dice.roll(e.currentAtk)
            e.hp = max(0, e.hp - selfHit)
            run.enemy = e
            log.append("\(e.name) is lost in a nightmare and strikes itself for \(selfHit)!")
            return 0
        }

        if run.armorEffect == "regenerating" && run.hp > 0 {
            run.hp = min(run.maxHp, run.hp + 3)
            log.append("💚 Regenerating armor heals 3 HP.")
        }
        let move = EnemyAbilities.beforeAttack(&run, dice: &dice, log: &log)
        if move.skipAttack { return 0 }
        let shadow = ShadowWorld.beforeAttack(&run, log: &log)
        if shadow.skip || run.hp <= 0 { return 0 }
        if run.armorEffect == "sturdy" && dice.chance(0.05) {
            log.append("🛡️ Sturdy armor fully blocks the attack!")
            return 0
        }
        var raw = dice.roll(e.currentAtk) + EnemyAbilities.secondStrike(e, dice: &dice, log: &log)
        raw = jsRound(Double(raw) * move.multiplier * shadow.multiplier) + move.extra
        if Alchemy.gravity(&run, log: &log) { raw = 1 }
        if run.fight.softenHits > 0 {
            run.fight.softenHits -= 1
            raw = jsRound(Double(raw) * run.fight.soften)
        }
        raw = jsRound(Double(raw) * run.difficulty.enemyDamageMultiplier)
        if let w = run.weather { raw = jsRound(Double(raw) * w.enemyAtkMult * w.damageTaken) }
        let rm = RunModifiers.enemyMult(run)
        if rm != 1 { raw = jsRound(Double(raw) * rm) }
        let dcm = DailyChallenge.enemyMult(run)
        if dcm != 1 { raw = jsRound(Double(raw) * dcm) }
        if run.undeadRes && Bestiary.undeadNames.contains(e.name) {
            raw = jsRound(Double(raw) * 0.65)
        }
        let maxBlock = move.ignoreDefense ? 0 : Int((Double(raw) * 0.60).rounded(.down))
        let defVal = run.totalDef + ClassTraits.defense(run) + (run.defending ? 4 : 0)
        let blocked = min(defVal, maxBlock)
        var taken = max(1, raw - blocked)
        if run.has("cu-ember-ward") { taken = max(1, taken - 2) }
        // Ancient Curse: one more, whatever your defense.
        if run.weather?.cursedArmor == true { taken += 1 }
        // Burning Dungeon: every hit burns.
        taken += RunModifiers.fire(run)
        if options.classTraits {
            switch run.cls {
            case "Paladin": taken = max(1, jsRound(Double(taken) * 0.85))
            case "DeathKnight": taken = max(1, jsRound(Double(taken) * 0.80))
            case "Sentinel": taken = max(1, jsRound(Double(taken) * 0.75))
            default: break
            }
        }
        taken = Races.incoming(run, taken)
        if run.fight.reduceTurns > 0 {
            run.fight.reduceTurns -= 1
            taken = max(1, jsRound(Double(taken) * (1 - run.fight.reduce)))
        }
        if run.fight.capTurns > 0 {
            run.fight.capTurns -= 1
            taken = min(taken, run.fight.cap)
        }
        switch run.armorEffect {
        case "fortified": taken = max(1, jsRound(Double(taken) * 0.85))
        case "aegis": taken = max(1, jsRound(Double(taken) * 0.60))
        case "unbreakable": taken = min(taken, max(1, run.maxHp / 4))
        default: break
        }
        // Blood Moon: you take 25% more (the web version never applied it).
        if let ev = Events.bonuses(run.event), ev.takesMore > 0 { taken = jsRound(Double(taken) * (1 + ev.takesMore)) }
        let hpBefore = run.hp
        taken = Alchemy.incoming(&run, taken, log: &log)
        taken = Subclasses.incoming(&run, taken, dice: &dice, log: &log)
        taken = Spells.incoming(&run, taken, log: &log)
        taken = ShapeshifterMask.incoming(&run, taken, log: &log)
        taken = CustomSpirits.incoming(run, taken)
        if taken == 0 || Spirits.guards(&run, dice: &dice, log: &log) || ShadowWorld.armorAvoids(&run, dice: &dice, log: &log) { return 0 }
        if run.fight.shield > 0 {
            let absorbed = min(run.fight.shield, taken)
            run.fight.shield -= absorbed
            taken -= absorbed
            log.append(taken > 0 ? "Your shield absorbs \(absorbed). You take \(taken) damage."
                                 : "Your shield absorbs all \(absorbed) damage!")
        } else if blocked > 0 {
            log.append("\(e.name) strikes for \(raw) — you absorb \(blocked). You take \(taken) damage.")
        } else {
            log.append("\(e.name) attacks for \(taken) damage.")
        }
        run.hp = max(0, run.hp - taken)
        if run.hp <= 0 && run.fight.gravePact > 0 {
            run.hp = 1
            log.append("⚰️ The Grave Pact holds. You cannot die.")
        }
        if run.hp <= 0 && run.fight.unstoppableTurns > 0 {
            run.hp = 1
            log.append("Unstoppable! Death refused.")
        }
        if run.hp <= 0 { _ = Subclasses.cheatDeath(&run, hpBefore: hpBefore, log: &log) }
        if run.hp <= 0 { _ = ClassTraits.undying(&run, log: &log) }
        run.fight.damageTaken += taken
        run.fight.recentHits.append(taken)
        if run.fight.recentHits.count > 3 { run.fight.recentHits.removeFirst() }

        // Thornmail reflects 20%; the Ghost Shroud sometimes phases you out.
        if taken > 0, case .number(let p)? = run.equippedArmor?.extra["thornReflect"], var e = run.enemy, !e.isDead {
            let back = Int((Double(taken) * p).rounded(.down))
            if back > 0 {
                e.hp = max(0, e.hp - back)
                run.enemy = e
                log.append("🌵 Thornmail reflects \(back) back at \(e.name)!")
            }
        }
        if taken > 0, case .number(let p)? = run.equippedArmor?.extra["ghostDodge"], dice.chance(p) {
            run.hp = min(run.maxHp, run.hp + taken)
            log.append("👻 Ghost Shroud — you phase out! You take no damage!")
        }
        let thorned = run.armorEffect == "thorned"
        let vengeful = run.armorEffect == "vengeful" && taken > 0 && dice.chance(0.20)
        if taken > 0 && (run.fight.thornsTurns > 0 || run.fight.retaliate > 0 || thorned || vengeful || WeaponForge.thorns(run, taken: taken) > 0), var hurt = run.enemy {
            var back = run.fight.retaliate
            if run.fight.thornsTurns > 0 { back += jsRound(Double(taken) * run.fight.thorns) }
            if thorned { back += jsRound(Double(taken) * 0.15) }
            back += WeaponForge.thorns(run, taken: taken)
            if vengeful {
                let counter = attackRoll(run, dice: &dice)
                back += counter
                log.append("⚔️ Vengeful armor counters for \(counter) damage!")
            }
            hurt.hp = max(0, hurt.hp - back)
            run.enemy = hurt
            if back > 0 { log.append("\(back) damage is reflected back at \(hurt.name)!") }
        }
        EnemyAbilities.afterAttack(&run, taken: taken, dice: &dice, log: &log)
        ShadowWorld.afterAttack(&run, log: &log)
        WhisperingForest.afterAttack(&run, log: &log)
        if var c = run.enemy, c.cursedTurns > 0 {
            c.cursedTurns -= 1
            if c.cursedTurns == 0 { log.append("The curse on \(c.name) fades.") }
            run.enemy = c
        }
        return taken
    }

    /// Counts down timed effects once per turn and applies regeneration and poison.
    public static func tickEffects(_ run: inout Run, log: inout [String]) {
        Medusa.tick(&run, log: &log)
        if run.freedomTurns > 0 {
            run.freedomTurns -= 1
            if run.freedomTurns == 0 { run.debuffImmune = false; log.append("The Freedom Potion's protection fades.") }
        }
        if run.tempAtkTurns > 0 {
            run.tempAtkTurns -= 1
            if run.tempAtkTurns == 0 { run.tempAtk = 0; log.append("Your attack boost fades.") }
        }
        if run.tempDefTurns > 0 {
            run.tempDefTurns -= 1
            if run.tempDefTurns == 0 { run.tempDef = 0; log.append("Your defense boost fades.") }
        }
        if run.inCombat && run.weaponEffect == "cursed" && run.hp > 1 {
            run.hp = max(1, run.hp - 3)
            log.append("Your cursed weapon drains 3 HP.")
        }
        if run.subclass == "death-knight-sub" { run.poisonTurns = 0 }
        if run.inCombat { Spells.tickFight(&run, log: &log) }
        Subclasses.turnHeal(&run, log: &log)
        if run.poisonTurns > 0 && run.hp > 0 {
            run.poisonTurns -= 1
            run.hp = max(0, run.hp - run.poisonDamage)
            log.append("Poison deals \(run.poisonDamage) damage. (\(run.poisonTurns) turns left)")
        }
        var f = run.fight
        if f.regenTurns > 0 && run.hp > 0 {
            f.regenTurns -= 1
            run.hp = min(run.maxHp, run.hp + f.regen)
            log.append("You regenerate \(f.regen) HP.")
        }
        if f.buffTurns > 0 {
            f.buffTurns -= 1
            if f.buffTurns == 0 { log.append("Your skill's boost fades.") }
        }
        if f.vulnerableTurns > 0 { f.vulnerableTurns -= 1 }
        if f.unstoppableTurns > 0 { f.unstoppableTurns -= 1 }
        if f.thornsTurns > 0 { f.thornsTurns -= 1 }
        if f.crusadeTurns > 0 { f.crusadeTurns -= 1 }
        if f.confuseTurns > 0 { f.confuseTurns -= 1 }
        run.fight = f
    }

    /// New Game+ count as the web version reads it (`ngPlusCount || 1`), or nil outside NG+.
    static func ngCount(_ run: Run) -> Int? {
        guard run.ngPlus else { return nil }
        let n = run.ngPlusCount ?? 1
        return n == 0 ? 1 : n
    }
}
