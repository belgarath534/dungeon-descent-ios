import Foundation

/// The Shadow World (dungeon 9): Shadow Corruption, its enemies' tricks,
/// The Echo that becomes The Shapeshifter, and its loot.
public enum ShadowWorld {
    public static let name = "The Shadow World"
    public static let purgeCost = 4

    static func inShadow(_ run: Run) -> Bool { run.dungeon == name }

    /// isShadowWorldUnlocked: finishing The Abyssal Deep breaks the seal.
    public static func unlocked(_ store: GameStore) -> Bool {
        if store.getItem("dd_dev_mode") == "1" || store.getItem("dd_shadowworld_unlocked") == "1" { return true }
        if let s = store.getItem("dd_cleared_dungeons"), s.contains("The Abyssal Deep") {
            store.setItem("dd_shadowworld_unlocked", "1")
            return true
        }
        return false
    }

    // MARK: Corruption

    /// addShadowCorruption
    static func corrupt(_ run: inout Run, _ stacks: Int, source: String, log: inout [String]) {
        guard inShadow(run), stacks > 0 else { return }
        run.shadowCorruption += stacks
        log.append("🌑 Shadow Corruption +\(stacks) (\(source)). Stacks: \(run.shadowCorruption)."
                   + (run.shadowCorruption >= 3 ? " Your attacks deal half damage. Use Purge to clear it." : ""))
    }

    /// getCorruptionDamageMult: half damage from 3 stacks, a quarter from 9.
    static func damageMultiplier(_ run: Run) -> Double {
        run.shadowCorruption >= 9 ? 0.25 : run.shadowCorruption >= 3 ? 0.5 : 1
    }

    /// purgeCorruption: 4 SP clears every stack. A free action.
    public static func purge(_ run: inout Run) -> String {
        guard run.shadowCorruption > 0 else { return "No corruption to purge." }
        guard run.sp >= purgeCost else { return "Not enough SP to purge. Need \(purgeCost) SP." }
        run.sp -= purgeCost
        let n = run.shadowCorruption
        run.shadowCorruption = 0
        return "✨ Shadow Purge — \(n) corruption stack\(n > 1 ? "s" : "") cleared! Costs \(purgeCost) SP."
    }

    // MARK: Your attacks

    /// Fear and corruption on your attack roll (doFight).
    static func attackRoll(_ run: inout Run, _ base: Int, log: inout [String]) -> Int {
        var a = base
        if run.fight.fearTurns > 0 {
            a = jsRound(Double(a) * 0.8)
            run.fight.fearTurns -= 1
            log.append(run.fight.fearTurns == 0 ? "😤 The fear fades. Your damage returns to normal."
                       : "😨 Sorrow Hound fear — damage reduced 20%. \(run.fight.fearTurns) turn\(run.fight.fearTurns != 1 ? "s" : "") remaining.")
        }
        if inShadow(run) && run.shadowCorruption >= 3 {
            a = jsRound(Double(a) * damageMultiplier(run))
            log.append("🌑 Corrupted — half damage! Use Purge to clear stacks.")
        }
        return a
    }

    /// Damage landing on a Shadow World enemy.
    static func onHit(_ run: inout Run, _ dmg: Int, basic: Bool, heavy: Bool, log: inout [String]) -> Int {
        guard dmg > 0, var e = run.enemy else { return dmg }
        var d = Double(dmg)
        // The Unborn never existed in the physical world: weapons do half.
        if basic && e.flag("spiritOnly") { d *= 0.5 }
        if let w = run.equippedWeapon, w.name == "Shadow Blade" { d += Double(e.maxHp - e.hp) * 0.10 }
        if (e.flag("isEcho") || e.flag("isShapeshifter") || e.name.hasPrefix("Echo of")),
           run.inventory.contains(where: { $0.extra["shadowItem"] == .string("echoBone") }) { d *= 1.25 }
        if heavy && e.mechanics["webActive"] == .bool(true) {
            e.mechanics["webActive"] = .bool(false)
            log.append("🕸️ Your heavy strike tears the shadow web apart!")
            run.enemy = e
        }
        return jsRound(d)
    }

    // MARK: The enemy's turn

    struct Turn { var skip = false; var multiplier = 1.0 }

    /// applyShadowEnemyMechanics, before the enemy swings.
    static func beforeAttack(_ run: inout Run, log: inout [String]) -> Turn {
        guard var e = run.enemy else { return Turn() }
        var t = Turn()
        defer { run.enemy = e }
        let first = e.turnsTaken == 1
        // Void Weaver: the web burns until a Heavy Strike tears it.
        if e.flag("corruptWeb") && first {
            e.mechanics["webActive"] = .bool(true)
            log.append("🕸️ \(e.name) weaves a shadow web! 8 passive damage per turn until destroyed by Heavy Strike.")
        }
        if e.mechanics["webActive"] == .bool(true) {
            run.hp = max(0, run.hp - 8)
            log.append("🕸️ Void Web deals 8 shadow damage!")
        }
        if e.flag("fearHowl") && first {
            run.fight.fearTurns = 3
            log.append("🐕 \(e.name) howls! Your damage is reduced 20% for 3 turns.")
        }
        if e.flag("mimicSurprise") && first {
            t.multiplier *= 2
            log.append("📦 The Mimic reveals itself! A surprise attack!")
        }
        // The Lurker hides on its first turn and strikes with a critical on
        // the second. (The web version hid and struck on the same turn.)
        if e.flag("lurkerHide") {
            if first {
                log.append("👁️ \(e.name) hides in the shadows. It will strike with full power next turn.")
                t.skip = true
                return t
            }
            if e.turnsTaken == 2 {
                t.multiplier *= 2.5
                log.append("👁️ The Lurker strikes from the shadows! Critical hit!")
            }
        }
        // The Reflection mirrors a defend by healing instead of attacking.
        if e.flag("reflection") && run.defending {
            e.hp = min(e.maxHp, e.hp + 15)
            log.append("🪞 The Reflection mirrors your defense — it heals 15 HP!")
            t.skip = true
            return t
        }
        if e.flag("shadowCommand") { t.multiplier *= 1.15 }
        return t
    }

    /// After the enemy's hit: corruption.
    static func afterAttack(_ run: inout Run, log: inout [String]) {
        guard let e = run.enemy else { return }
        var stacks = Int(e.number("corruptOnHit") ?? 0)
        if e.name == "Null Sovereign" { stacks = 2 }
        corrupt(&run, stacks, source: e.name, log: &log)
    }

    /// Shadow armor against a hit: the Shadow Cloak's phase and the Null
    /// Shield's first-hit block. Returns true when the hit is avoided.
    static func armorAvoids(_ run: inout Run, dice: inout some Dice, log: inout [String]) -> Bool {
        guard let a = run.equippedArmor else { return false }
        if a.name == "Shadow Cloak" && dice.chance(0.25) {
            log.append("🌫️ Your Shadow Cloak phases you through the attack!")
            return true
        }
        if a.name == "The Null Shield" && !run.fight.nullShieldUsed {
            run.fight.nullShieldUsed = true
            log.append("🛡️ The Null Shield absorbs the first hit completely!")
            return true
        }
        return false
    }

    /// Void Cloth: +1 defense per corruption stack.
    static func armorDefense(_ run: Run) -> Int {
        run.equippedArmor?.name == "Void Cloth" ? run.shadowCorruption : 0
    }

    // MARK: Deaths that don't stay

    /// When a Shadow World enemy reaches 0 HP: The Twice Dead and The Hollow
    /// Echo come back, a Shadow Pup's pair takes its place, and The Echo gives
    /// way to The Shapeshifter. Returns log lines if the fight goes on.
    static func refusesDeath(_ run: inout Run) -> [String]? {
        guard var e = run.enemy, e.isDead, inShadow(run) else { return nil }
        if e.flag("twiceDead") && e.mechanics["revived"] == nil {
            e.mechanics["revived"] = .bool(true)
            e.hp = jsRound(Double(e.maxHp) * 0.5)
            run.enemy = e
            return ["💀 \(e.name) refuses to stay dead! Returns at \(e.hp) HP!"]
        }
        if e.name == "The Hollow Echo" && e.mechanics["revived"] == nil {
            e.mechanics["revived"] = .bool(true)
            e.hp = e.maxHp
            run.enemy = e
            return ["🔄 The Hollow Echo returns from the dark at full strength!"]
        }
        // Shadow Pups come in pairs (the web version had no way to field two).
        if e.flag("spawnsPair") && e.mechanics["pairDone"] == nil {
            e.mechanics["pairDone"] = .bool(true)
            e.hp = e.maxHp
            e.turnsTaken = 0
            run.enemy = e
            return ["🐾 A second Shadow Pup leaps out of the dark!"]
        }
        if e.isBoss && e.flag("isEcho"),
           let t = Bestiary.enemies(for: name, difficulty: run.difficulty).bosses.first(where: { $0.mechanics["isShapeshifter"] == .bool(true) }) {
            var s = Enemy.spawnBoss(t, playerLevel: run.level, playerMaxAtk: run.atk.upperBound)
            s.mechanics["isShapeshifter"] = .bool(true)
            run.enemy = s
            run.bossPhase = 1
            run.inCombat = true
            return ["🌑 The Echo dissolves... but something else stirs in the dark.",
                    "🌑 THE SHAPESHIFTER EMERGES — wearing your face. Using your name."]
        }
        return nil
    }

    /// The Shapeshifter's four phases: your weapon at 75% HP, your HP at
    /// 50%, then everything you have.
    static func shapeshifterPhase(_ run: inout Run) -> String? {
        guard var e = run.enemy, e.flag("isShapeshifter"), !e.isDead else { return nil }
        defer { run.enemy = e }
        if run.bossPhase == 1 && e.hp <= jsRound(Double(e.maxHp) * 0.75) {
            run.bossPhase = 2
            e.atk = (run.atk.lowerBound + 5)...(run.atk.upperBound + 8)
            return "🌑 PHASE 2 — " + (e.phaseMsg2 ?? "The Shapeshifter copies your equipped weapon — attacks now deal your weapon damage!")
        }
        if run.bossPhase == 2 && e.hp <= jsRound(Double(e.maxHp) * 0.50) {
            run.bossPhase = 3
            e.hp = max(1, run.hp)
            e.maxHp = max(1, run.hp)
            return "🌑 PHASE 3 — " + (e.phaseMsg3 ?? "Phase 3 — The Shapeshifter matches your current HP. It will not let you outlast it.")
        }
        if run.bossPhase == 3 && e.hp <= jsRound(Double(e.maxHp) * 0.50) {
            run.bossPhase = 4
            e.mechanics["corruptOnHit"] = .number(2)
            e.atk = jsRound(Double(e.atk.lowerBound) * 1.5)...jsRound(Double(e.atk.upperBound) * 1.5)
            return "💀 FINAL FORM — " + (e.mechanics["phaseMsg4"].flatMap { if case .string(let s) = $0 { return s }; return nil }
                                        ?? "Final Form — The Shapeshifter uses ALL your skills. Fight yourself.")
                + " Every hit adds 2 corruption. Use Purge."
        }
        return nil
    }

    /// The Shapeless (elite) copies your weapon's damage.
    static func combatStart(_ run: inout Run, log: inout [String]) {
        guard var e = run.enemy, inShadow(run) else { return }
        if e.name == "The Shapeless", let w = run.equippedWeapon {
            e.atk = w.weaponAttack
            run.enemy = e
            log.append("🌫️ The Shapeless copies your \(w.name)!")
        }
    }

    // MARK: Items

    /// Null Potion and Mirror Fragment clear corruption.
    public static func cleanses(_ item: Item) -> Bool {
        item.name == "Null Potion" || item.extra["shadowItem"] == .string("mirrorFragment")
    }
}
