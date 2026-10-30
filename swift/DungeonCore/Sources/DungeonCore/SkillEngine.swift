import Foundation

/// Learning and using class skills. Ports of initSkillPool, offerSkillChoices,
/// pickSkill and useSkill.
public enum Skills {
    /// The class's whole skill list.
    public static func all(for cls: String) -> [Skill] {
        GameContent.shared.classSkills[cls] ?? []
    }

    public static func skill(_ effect: String, cls: String) -> Skill? {
        // Street Rat's Smoke Bomb works for any class.
        all(for: cls).first { $0.effect == effect }
            ?? (effect == "smoke-bomb" ? all(for: "Assassin").first { $0.effect == effect } : nil)
    }

    /// The skills this run has unlocked, in the order they were learned.
    public static func unlocked(_ run: Run) -> [Skill] {
        run.unlockedSkills.compactMap { skill($0, cls: run.cls) }
    }

    /// Sets up the run's skill pool and grants the starting skill. Classes the
    /// web version gives no (or a missing) starting skill get their first one.
    public static func start(_ run: inout Run, dice: inout some Dice) {
        // Skills already known (Legacy Mode's saved ones, Street Rat's Smoke
        // Bomb) are kept and left out of the pool.
        let kept = run.unlockedSkills
        var pool = all(for: run.cls).map(\.effect)
        for i in stride(from: pool.count - 1, to: 0, by: -1) {
            pool.swapAt(i, dice.roll(0...i))
        }
        let mapped = GameContent.shared.startingSkills[run.cls]
        let first = mapped.flatMap { m in pool.contains(m) ? m : nil } ?? all(for: run.cls).first?.effect
        if let s = first, let i = pool.firstIndex(of: s) {
            pool.remove(at: i)
            run.unlockedSkills = [s] + kept.filter { $0 != s }
        }
        pool.removeAll { kept.contains($0) }
        run.skillPool = pool
    }

    /// Up to 3 new skills to choose from at a level-up: one of each tier when
    /// possible, then random ones (offerSkillChoices).
    public static func offer(_ run: inout Run, dice: inout some Dice) {
        var pool = run.skillPool
        var picks: [String] = []
        for tier in ["common", "rare", "legendary"] where picks.count < 3 {
            let inTier = pool.filter { skill($0, cls: run.cls)?.tier == tier }
            guard !inTier.isEmpty else { continue }
            let p = inTier[dice.roll(0...(inTier.count - 1))]
            picks.append(p)
            pool.removeAll { $0 == p }
        }
        while picks.count < 3 && !pool.isEmpty {
            picks.append(pool.remove(at: dice.roll(0...(pool.count - 1))))
        }
        run.skillChoices = picks
    }

    /// Learns one of the offered skills. The others are gone for this run.
    @discardableResult
    public static func pick(_ run: inout Run, _ effect: String) -> Skill? {
        guard run.skillChoices.contains(effect) else { return nil }
        run.unlockedSkills.append(effect)
        run.skillPool.removeAll { run.skillChoices.contains($0) }
        run.skillChoices = []
        return skill(effect, cls: run.cls)
    }

    /// SP a skill costs right now, after discounts.
    public static func cost(_ s: Skill, _ run: Run) -> Int {
        if run.freeSkills > 0 || run.weaponEffect == "apocalypse" { return 0 }
        var c = s.spCost
        c -= Races.skillCostCut(run)
        c -= ClassTraits.skillCostCut(run)
        c -= Professions.skillCostCut(run)
        c -= BossRelics.skillCostCut(run)
        if run.has("cu-soul-surge") { c -= 1 }
        c -= Subclasses.skillCostCut(run)
        c -= run.weather?.spDiscount ?? 0
        if run.halfCostSkills { c /= 2 }
        return max(0, c)
    }

    /// Uses an unlocked skill in combat, then gives the enemy its turn unless
    /// the skill is a free action or stuns it.
    public static func use(_ run: inout Run, _ effect: String, dice: inout some Dice,
                           options: Combat.Options = Combat.Options()) -> TurnResult {
        var r = TurnResult()
        guard run.inCombat, run.enemy != nil else {
            r.acted = false
            r.announcement = "Skills can only be used in combat."
            return r
        }
        guard run.unlockedSkills.contains(effect), let skill = skill(effect, cls: run.cls) else {
            r.acted = false
            r.announcement = "You don't know that skill."
            return r
        }
        var spec = SkillTable.spec(cls: run.cls, effect: effect)
        if spec.oncePerRun && run.usedOncePerRun.contains(effect) {
            r.acted = false
            r.announcement = "\(skill.name) can only be used once per run."
            return r
        }
        let price = cost(skill, run)
        guard run.sp >= price else {
            r.acted = false
            r.announcement = "Not enough SP. You need \(price) SP but have \(run.sp)."
            return r
        }
        // Battle Hymn: every skill sings +5 ATK into your next 3 attacks.
        if run.subclass == "battle-hymn" { run.battleHymnTurns = 3 }
        run.sp -= price
        if run.freeSkills > 0 { run.freeSkills -= 1 }
        if spec.oncePerRun { run.usedOncePerRun.append(effect) }
        if !run.skillsUsed.contains(effect) { run.skillsUsed.append(effect) }
        run.defending = false
        if let line = Corruption.backfire(&run, skill: skill.name, dice: &dice) {
            r.log.append(line)
            return Combat.finishTurn(&run, r, skipEnemy: false, dice: &dice, options: options)
        }

        // Spell Echo repeats the last skill for free.
        if spec.special == "spell-echo" {
            guard let last = run.lastSkill, last != effect else {
                r.log.append("Spell Echo has nothing to repeat yet.")
                return Combat.finishTurn(&run, r, skipEnemy: true, dice: &dice, options: options)
            }
            spec = SkillTable.spec(cls: run.cls, effect: last)
            r.log.append("Spell Echo repeats \(Self.skill(last, cls: run.cls)?.name ?? "your last skill")!")
        } else {
            run.lastSkill = effect
        }

        let base = Combat.attackRoll(run, dice: &dice)
        var e = run.enemy!
        var dmg = 0
        var skipEnemy = spec.isFree
        var msg = "\(skill.icon) \(skill.name)!"

        // Damage
        if spec.playerMiss > 0 && dice.chance(spec.playerMiss) {
            msg += " It misses!"
        } else {
            var mult = spec.dmg
            if spec.lowHp > 0 { mult = Double(run.hp) <= Double(run.maxHp) * spec.lowHp ? spec.lowHpDmg : spec.dmg }
            if spec.execute > 0 && Double(e.hp) <= Double(e.maxHp) * spec.execute { mult = spec.executeDmg }
            if spec.aboveHp > 0 && Double(e.hp) >= Double(e.maxHp) * spec.aboveHp { mult = spec.aboveHpDmg }
            if mult > 0 {
                if spec.hits > 1 {
                    dmg = jsRound(Double(base) * mult) * spec.hits
                } else {
                    dmg = jsRound(Double(base) * mult)
                }
            }
            dmg += jsRound(Double(e.maxHp) * spec.pctEnemyMax)
            dmg += jsRound(Double(e.hp) * spec.pctEnemyHp)
            dmg += jsRound(Double(e.maxHp - e.hp) * spec.pctEnemyMissing)
            dmg += spec.flat
            if spec.killBelow > 0 && Double(e.hp) <= Double(e.maxHp) * spec.killBelow {
                dmg = max(dmg, e.hp)
                msg += " Instant kill!"
            }
            if let sp = spec.special {
                let s = specialDamage(sp, &run, base: base, enemy: &e, dice: &dice, msg: &msg, skip: &skipEnemy)
                dmg += s
            }
            if spec.marksCrit { run.markedKill = true }
            if spec.empowerCount > 0 {
                run.fight.empower = spec.empower
                run.fight.empowerCount = spec.empowerCount
            }
            dmg = Combat.scaleDamage(run, dmg, skill: true)
            // Home skill upgrades: +10% damage per level above 1 (the web
            // version saved the level and never read it).
            if let lvl = run.skillLevels[Home.skillKey(cls: run.cls, name: skill.name)], lvl > 1, dmg > 0 {
                dmg = jsRound(Double(dmg) * (1 + 0.10 * Double(lvl - 1)))
            }
            if dmg > 0 {
                msg += spec.hits > 1 ? " \(spec.hits) hits for \(dmg) damage." : " \(dmg) damage."
            }
        }
        run.enemy = e

        // Your side
        if spec.selfDamage != 0 { run.hp = max(1, run.hp - spec.selfDamage); msg += " Costs \(spec.selfDamage) HP." }
        if spec.selfDamageShare > 0 && dmg > 0 {
            let back = jsRound(Double(dmg) * spec.selfDamageShare)
            run.hp = max(1, run.hp - back)
            msg += " \(back) damage rebounds on you."
        }
        var healed = spec.heal + jsRound(Double(dmg) * spec.healShare) + jsRound(Double(run.maxHp) * spec.healMaxShare)
        healed = min(healed, run.maxHp - run.hp)
        if healed > 0 { run.hp += healed; msg += " +\(healed) HP." }
        if spec.sp > 0 || spec.fillsSP {
            let before = run.sp
            run.sp = spec.fillsSP ? run.maxSp : min(run.maxSp, run.sp + spec.sp)
            if run.sp > before { msg += " +\(run.sp - before) SP." }
        }
        if spec.drainsSP { run.sp = 0; msg += " All SP consumed." }
        if spec.permAtk != 0 || spec.permDef != 0 || spec.permMaxHp != 0 || spec.permMaxSp != 0 {
            run.atkBonus += spec.permAtk
            run.defBonus += spec.permDef
            run.maxHp = max(1, run.maxHp + spec.permMaxHp)
            run.hp = min(run.maxHp, spec.permMaxHp > 0 ? run.hp + spec.permMaxHp : run.hp)
            run.maxSp += spec.permMaxSp
            run.sp = min(run.maxSp, run.sp + max(0, spec.permMaxSp))
            msg += " Permanent: " + [
                spec.permAtk != 0 ? "\(spec.permAtk > 0 ? "+" : "")\(spec.permAtk) attack" : nil,
                spec.permDef != 0 ? "+\(spec.permDef) defense" : nil,
                spec.permMaxHp != 0 ? "\(spec.permMaxHp > 0 ? "+" : "")\(spec.permMaxHp) max HP" : nil,
                spec.permMaxSp != 0 ? "+\(spec.permMaxSp) max SP" : nil,
            ].compactMap { $0 }.joined(separator: ", ") + "."
        }
        if spec.fightAtk != 0 || spec.fightDef != 0 {
            run.fight.atk += spec.fightAtk
            run.fight.def += spec.fightDef
            msg += " " + [spec.fightAtk != 0 ? "+\(spec.fightAtk) attack" : nil,
                          spec.fightDef != 0 ? "+\(spec.fightDef) defense" : nil].compactMap { $0 }.joined(separator: " and ") + " this fight."
        }
        if spec.buffTurns > 0 {
            run.fight.buffAtk = spec.buffAtk
            run.fight.buffDef = spec.buffDef
            run.fight.buffTurns = spec.buffTurns
            msg += " " + [spec.buffAtk != 0 ? "+\(spec.buffAtk) attack" : nil,
                          spec.buffDef != 0 ? "+\(spec.buffDef) defense" : nil].compactMap { $0 }.joined(separator: " and ") + " for \(spec.buffTurns) turns."
        }
        if spec.shield > 0 { run.fight.shield += spec.shield; msg += " Shield absorbs up to \(run.fight.shield) damage." }
        if spec.dodges > 0 { run.fight.dodges += spec.dodges; msg += spec.dodges == 1 ? " The next attack will miss you." : " The next \(spec.dodges) attacks will miss you." }
        if spec.enemyMiss > 0 { run.fight.enemyMiss = spec.enemyMiss; msg += " \(Int(spec.enemyMiss * 100))% chance the enemy misses." }
        if spec.reduceTurns > 0 { run.fight.reduce = spec.reduce; run.fight.reduceTurns = spec.reduceTurns; msg += " Damage taken -\(Int(spec.reduce * 100))% for \(spec.reduceTurns) turns." }
        if spec.capTurns > 0 { run.fight.cap = spec.cap; run.fight.capTurns = spec.capTurns; msg += " No hit can do more than \(spec.cap) for \(spec.capTurns) turns." }
        if spec.unstoppable > 0 { run.fight.unstoppableTurns = spec.unstoppable; msg += " You cannot die for \(spec.unstoppable) turn\(spec.unstoppable == 1 ? "" : "s")." }
        if spec.grantsResurrection { run.resurrection = true; msg += " You will rise once at 50% HP." }
        if spec.regenTurns > 0 { run.fight.regen = spec.regen; run.fight.regenTurns = spec.regenTurns; msg += " Regenerating \(spec.regen) HP per turn." }
        if spec.thorns > 0 { run.fight.thorns = spec.thorns; run.fight.thornsTurns = spec.thornsTurns; msg += " \(Int(spec.thorns * 100))% of damage reflected." }
        if spec.retaliate > 0 { run.fight.retaliate = spec.retaliate; msg += " Attackers take \(spec.retaliate) damage." }
        if spec.crusade > 0 { run.fight.crusadeHeal = spec.crusade; run.fight.crusadeTurns = spec.crusadeTurns; msg += " Each hit heals \(spec.crusade) HP." }
        if spec.freeSkills > 0 { run.freeSkills += spec.freeSkills; msg += " Next \(spec.freeSkills == 1 ? "skill costs" : "\(spec.freeSkills) skills cost") 0 SP." }
        if spec.grantsWarlord { run.fight.warlord = true; msg += " Kills this fight restore 10 HP and 3 SP." }
        if spec.skillBonus > 0 || spec.allBonus > 0 || spec.halfCost {
            run.skillDamageBonus += spec.skillBonus
            run.allDamageBonus += spec.allBonus
            if spec.halfCost { run.halfCostSkills = true }
            msg += " Empowered for the rest of the run."
        }
        if spec.grantsDebuffImmunity { run.debuffImmune = true; run.poisonTurns = 0; run.frozen = false; msg += " Immune to debuffs." }
        if spec.escapes {
            run.inCombat = false
            run.enemy = nil
            r.fled = true
            r.log.append(msg + " You escape!")
            r.announcement = r.log.last
            return r
        }

        // The enemy's side
        if var en = run.enemy {
            if spec.stun > 0 && dice.chance(spec.stunChance) {
                en.stunTurns = max(en.stunTurns, spec.stun)
                msg += spec.stun == 1 ? " \(en.name) is stunned!" : " \(en.name) loses \(spec.stun) turns!"
            }
            if spec.dotTurns > 0 && dice.chance(spec.dotChance) {
                en.dotDamage = spec.dot
                en.dotTurns = spec.dotTurns
                msg += " \(spec.dot) damage per turn for \(spec.dotTurns) turns."
            }
            if spec.weaken < 1 || spec.weakenFlat > 0 {
                let lo = max(1, jsRound(Double(en.atk.lowerBound) * spec.weaken) - spec.weakenFlat)
                let hi = max(1, jsRound(Double(en.atk.upperBound) * spec.weaken) - spec.weakenFlat)
                en.atk = lo...max(lo, hi)
                msg += " \(en.name)'s attack is weakened."
            }
            if spec.shrinkEnemy > 0 {
                en.maxHp = max(1, en.maxHp - spec.shrinkEnemy)
                en.hp = min(en.hp, en.maxHp)
            }
            run.enemy = en
            if spec.softenHits > 0 {
                run.fight.soften = spec.soften
                run.fight.softenHits = spec.softenHits
                msg += " Its next \(spec.softenHits == 1 ? "hit is" : "\(spec.softenHits) hits are") weakened."
            }
            if spec.vulnerableTurns > 0 && dice.chance(spec.vulnerableChance) {
                run.fight.vulnerable = spec.vulnerable
                run.fight.vulnerableTurns = spec.vulnerableTurns
                msg += " It takes \(Int(spec.vulnerable * 100))% more damage" + (spec.vulnerableTurns >= 99 ? "." : " for \(spec.vulnerableTurns) turns.")
            }
            if spec.confuseTurns > 0 { run.fight.confuse = spec.confuse; run.fight.confuseTurns = spec.confuseTurns; msg += " Its mind is clouded." }
            if spec.decayTurns > 0 { run.fight.decay = spec.decay; run.fight.decayTurns = spec.decayTurns; msg += " It weakens every turn." }
            if spec.reveals {
                msg += " \(en.name): \(en.hp) of \(en.maxHp) HP, hits for \(en.currentAtk.lowerBound) to \(en.currentAtk.upperBound)."
            }
        }

        r.log.append(msg)
        r.playerDamage = EnemyAbilities.onPlayerHit(&run, dmg, basic: false, dice: &dice, log: &r.log)
        r.playerDamage = ShadowWorld.onHit(&run, r.playerDamage, basic: false, heavy: false, log: &r.log)
        Combat.dealDamage(&run, r.playerDamage, log: &r.log)
        // A stun that lands this turn also stops this turn's counter-attack.
        if let en = run.enemy, en.stunTurns > 0, !skipEnemy {
            var s = en
            s.stunTurns -= 1
            run.enemy = s
            skipEnemy = true
        }
        return Combat.finishTurn(&run, r, skipEnemy: skipEnemy, dice: &dice, options: options)
    }

    /// Skills whose damage or effect needs its own rule.
    static func specialDamage(_ id: String, _ run: inout Run, base: Int, enemy e: inout Enemy,
                              dice: inout some Dice, msg: inout String, skip: inout Bool) -> Int {
        switch id {
        case "pressure-point":
            return base + run.totalDef
        case "judgment":
            return run.totalDef * 5
        case "obliterate":
            let d = jsRound(Double(run.sp * 4 + base))
            run.sp = 0
            msg += " All remaining SP channeled."
            return d
        case "blood-frenzy":
            let missing = 1 - Double(run.hp) / Double(max(1, run.maxHp))
            return jsRound(Double(base) * (1 + missing))
        case "death-wish":
            return (run.maxHp - run.hp) * 3
        case "transmute":
            if run.gold >= 10 {
                run.gold -= 10
                msg += " 10 gold transmuted."
                return jsRound(Double(base) * 1.5)
            }
            msg += " Not enough gold — a normal strike."
            return base
        case "unstable-formula":
            let m = dice.roll(1...6)
            msg += " \(m)x multiplier!"
            return base * m
        case "discord":
            return jsRound(Double(e.atk.upperBound) * 1.8)
        case "lethal-tempo":
            run.fight.lethalTempo += 0.15
            return jsRound(Double(base) * (1 + run.fight.lethalTempo))
        case "philosopher-stone":
            let convert = min(20, run.hp - 1)
            run.hp -= convert
            run.sp = min(run.maxSp, run.sp + jsRound(Double(convert) / 2))
            msg += " Converted \(convert) HP to \(jsRound(Double(convert) / 2)) SP."
            skip = true
            return 0
        case "life-tap":
            let t = min(15, run.hp - 1)
            run.hp -= t
            run.sp = min(run.maxSp, run.sp + t)
            msg += " \(t) HP converted to SP."
            skip = true
            return 0
        case "vein-tap":
            run.hp = min(run.maxHp, run.hp + 15)
            msg += " Stole 15 HP."
            skip = true
            return 15
        case "final-pact":
            let d = (run.hp - 1) * 3
            run.hp = 1
            msg += " All HP sacrificed."
            return d
        case "sticky-bomb":
            run.fight.stickyBomb = jsRound(Double(base) * 1.8)
            msg += " A bomb is planted. It explodes next turn for \(run.fight.stickyBomb)."
            skip = true
            return 0
        case "battlecry":
            run.fight.atk += jsRound(Double(run.atk.upperBound) * 0.5)
            msg += " Attack doubled for the rest of the fight."
            return 0
        case "archangel", "lich-form", "elder-invocation", "avatar-nature":
            let extra = id == "avatar-nature" || id == "elder-invocation" ? base * 2 : base
            run.fight.buffAtk = extra
            run.fight.buffDef = id == "avatar-nature" ? 8 : 5
            run.fight.buffTurns = id == "lich-form" ? 3 : 2
            msg += " Power surges for \(run.fight.buffTurns) turns."
            return 0
        case "berserker-god":
            run.fight.unstoppableTurns = max(run.fight.unstoppableTurns, 1)
            run.fight.atk += jsRound(Double(base) * 1.5)
            msg += " Immune to death next turn and massively empowered."
            return 0
        case "wrath-incarnate":
            run.fight.def -= run.totalDef - run.def
            msg += " All bonus defense sacrificed."
            return jsRound(Double(base) * 4)
        case "epic-tale":
            run.fight.atk += min(20, run.kills)
            msg += " Your legend grows: +\(min(20, run.kills)) attack this fight."
            return base
        case "soul-storm":
            return base + run.kills * 2
        case "killshot":
            return jsRound(Double(base) * 4 * (1 + Double(run.floor) * 0.05))
        case "retribution":
            msg += " Payback for \(run.fight.damageTaken) damage taken."
            return run.fight.damageTaken
        case "rewind":
            let back = min(15, run.fight.damageTaken)
            run.hp = min(run.maxHp, run.hp + back)
            msg += " \(back) damage undone."
            skip = true
            return 0
        case "rewrite":
            let back = run.fight.recentHits.reduce(0, +)
            run.hp = min(run.maxHp, run.hp + back)
            run.fight.recentHits = []
            msg += " The last 3 hits are rewritten: +\(back) HP."
            skip = true
            return 0
        case "colossus":
            run.fight.buffDef = run.totalDef * 2
            run.fight.buffTurns = 2
            let h = min(run.maxHp - run.hp, jsRound(Double(run.maxHp) * 0.25))
            run.hp += h
            msg += " Defense tripled for 2 turns, +\(h) HP."
            skip = true
            return 0
        case "elemental-burst":
            switch dice.roll(0...2) {
            case 0: e.stunTurns = max(e.stunTurns, 1); msg += " Frost: the enemy is frozen!"
            case 1: e.dotDamage = 10; e.dotTurns = 3; msg += " Fire: burning for 3 turns!"
            default: run.fight.vulnerable = 0.3; run.fight.vulnerableTurns = 2; msg += " Lightning: the enemy is shocked!"
            }
            return jsRound(Double(base) * 3)
        case "spell-steal":
            run.fight.buffAtk = e.atk.upperBound / 2
            run.fight.buffTurns = 1
            msg += " You steal \(e.name)'s power."
            return jsRound(Double(base) * 1.2)
        case "mana-burn":
            return jsRound(Double(e.maxHp) * 0.2)
        case "omnimancy":
            switch dice.roll(0...3) {
            case 0: msg += " Destruction!"; return base * 3
            case 1:
                let h = min(30, run.maxHp - run.hp); run.hp += h; msg += " Restoration: +\(h) HP."
            case 2: run.fight.shield += 30; msg += " Protection: a 30-point shield."
            default: e.stunTurns = max(e.stunTurns, 1); msg += " Control: the enemy is frozen in place."
            }
            return 0
        default:
            return base
        }
    }
}
