import Foundation

/// The Daily Raid (RAID ENGINE): five waves of enemies, the last ending with
/// The Undying Legion. Winning pays Mystery Coins by raid tier, once a day.
public struct Raid: Codable, Sendable {
    /// An RPOOL entry or RAID_BOSS_TEMPLATE.
    public struct Foe: Codable, Sendable {
        public let name: String
        public let icon: String
        public let hp: Int
        public let atk: [Int]
        public let gold: [Int]
    }

    /// One enemy in the current wave.
    public struct Enemy: Codable, Sendable {
        public let name: String
        public let icon: String
        public var hp: Int
        public let maxHp: Int
        public let atk: ClosedRange<Int>
        public let gold: ClosedRange<Int>
        public var alive: Bool { hp > 0 }
    }

    public var wave = 1
    public var hp: Int
    public let maxHp: Int
    public let atk: ClosedRange<Int>
    public let def: Int
    public let atkBonus: Int
    public var defBonus: Int
    public var defending = false
    public var gold = 0
    public var potions: Int
    public var sp: Int
    public let maxSp: Int
    public var enemies: [Enemy] = []
    public var markedKill = false
    public var divineShield = false
    public var manaShield = 0
    public var venomTurns = 0
    public let hard: Bool
    public let cls: String
    public var done = false
    public var won = false

    /// beginRaid. Armor counts twice, in defense and in the defense bonus,
    /// exactly like the web version.
    public init(character ch: PlayerCharacter, weapon: Item?, armor: Item?, upgrades: Set<String>, hard: Bool,
                dice: inout some Dice) {
        let info = GameData.classInfo(ch.cls)
        let level = ch.persistLevel ?? 1
        maxHp = info.maxHp + (level - 1) * 10
        hp = maxHp
        atk = info.atk
        let armorDef = armor?.armorDefense ?? 0
        def = info.def + armorDef
        defBonus = armorDef
        var weaponBonus = 0
        if let w = weapon { weaponBonus = (w.weaponAttack.lowerBound + w.weaponAttack.upperBound) / 2 }
        atkBonus = weaponBonus + (level - 1) / 2
        potions = 4 + (upgrades.contains("cu-raid-boost") ? 1 : 0)
        sp = 20 + (level - 1) * 2
        maxSp = sp
        self.hard = hard
        cls = ch.cls
        startWave(dice: &dice)
    }

    /// startWave: 5–7 enemies (5–10 on Hard), 18% stronger each wave, the
    /// Legion closing wave 5.
    public mutating func startWave(dice: inout some Dice) {
        defending = false
        let count = hard ? dice.roll(5...10) : dice.roll(5...7)
        let scale = 1 + Double(wave - 1) * 0.18
        let pool = GameContent.shared.raidPool
        enemies = (0..<count).map { i in
            if wave == 5 && i == count - 1 {
                let b = GameContent.shared.raidBoss
                return Enemy(name: b.name, icon: b.icon, hp: b.hp, maxHp: b.hp,
                             atk: b.atk[0]...b.atk[1], gold: b.gold[0]...b.gold[1])
            }
            let f = pool[dice.roll(0...(pool.count - 1))]
            let hp = jsRound(Double(f.hp) * scale)
            let lo = jsRound(Double(f.atk[0]) * scale), hi = jsRound(Double(f.atk[1]) * scale)
            return Enemy(name: f.name, icon: f.icon, hp: hp, maxHp: hp, atk: lo...max(lo, hi), gold: f.gold[0]...f.gold[1])
        }
    }

    /// The first enemy still standing (getActiveEnemy).
    public var current: Int? { enemies.firstIndex { $0.alive } }
    public var remaining: Int { enemies.filter(\.alive).count }

    public struct Turn: Sendable {
        public var log: [String] = []
        public var spoken: [String] = []
        public var sounds: [String] = []
        public var kills: [String] = []
        public var newWave = false
        public var acted = true
    }

    public enum Action { case attack, heavy, defend, potion }

    /// raidFight
    public mutating func fight(_ action: Action, dice: inout some Dice) -> Turn {
        var t = Turn()
        guard !done else { t.acted = false; return t }
        guard let i = current else { waveComplete(&t, dice: &dice); return t }
        let base = dice.roll(atk) + atkBonus
        let wasDefending = defending
        defending = false
        var dmg = 0
        let name = enemies[i].name
        switch action {
        case .attack:
            // Like raidFight, an attack ignores Marked Kill.
            let crit = dice.chance(0.10)
            dmg = crit ? jsRound(Double(base) * 1.8) : base
            t.sounds.append(crit ? "sfx-crit" : "sfx-attack")
            t.log.append(crit ? "CRITICAL HIT on \(name) for \(dmg)!" : "You attack \(name) for \(dmg).")
        case .heavy:
            if dice.chance(0.30) {
                t.sounds.append("sfx-heavy-miss")
                t.log.append("Heavy strike misses \(name)!")
            } else {
                dmg = jsRound(Double(base) * 1.7)
                t.sounds.append("sfx-heavy-hit")
                t.log.append("Heavy strike hits \(name) for \(dmg)!")
            }
        case .defend:
            defending = true
            dmg = jsRound(Double(base) * 0.4)
            t.log.append("You defend, striking \(name) for \(dmg).")
        case .potion:
            defending = wasDefending
            guard potions > 0 else {
                t.acted = false
                t.log.append("No potions left!")
                t.spoken.append("No potions remaining.")
                return t
            }
            let heal = jsRound(Double(maxHp) * 0.35)
            hp = min(maxHp, hp + heal)
            potions -= 1
            t.sounds.append("sfx-potion")
            t.log.append("You drink a potion. +\(heal) HP. Potions left: \(potions).")
            t.spoken.append("Healed \(heal) HP. HP: \(hp). Potions: \(potions).")
            return t
        }
        if dmg > 0 { enemies[i].hp = max(0, enemies[i].hp - dmg) }
        if !enemies[i].alive {
            enemyDown(i, &t, dice: &dice, hardBonus: true)
            return t
        }
        strike(i, &t, dice: &dice, block: def + defBonus + (wasDefending ? 4 : 0))
        return t
    }

    private mutating func enemyDown(_ i: Int, _ t: inout Turn, dice: inout some Dice, hardBonus: Bool) {
        let e = enemies[i]
        t.sounds.append("sfx-enemy-die")
        t.kills.append(e.name)
        var g = dice.roll(e.gold)
        if hardBonus && hard { g = jsRound(Double(g) * 1.5) }
        gold += g
        t.log.append("\(e.name) falls! +\(g)g")
        if remaining == 0 {
            waveComplete(&t, dice: &dice)
        } else if let n = current {
            let next = enemies[n]
            t.log.append("\(remaining) \(remaining == 1 ? "enemy" : "enemies") remaining. Now facing \(next.name)!")
            t.spoken.append("\(e.name) defeated. \(remaining) remaining. Now facing \(next.name). HP: \(next.hp).")
        }
    }

    private mutating func strike(_ i: Int, _ t: inout Turn, dice: inout some Dice, block: Int) {
        let e = enemies[i]
        let raw = dice.roll(e.atk)
        var taken = max(1, raw - min(block, raw * 55 / 100))
        if manaShield > 0 {
            let absorbed = min(manaShield, taken)
            taken -= absorbed
            manaShield -= absorbed
            t.log.append("Mana Shield absorbs \(absorbed). You take \(taken).")
        }
        hp = max(0, hp - taken)
        t.sounds.append("sfx-hurt")
        t.log.append("\(e.name) strikes you for \(taken) damage. HP: \(hp)/\(maxHp).")
        t.spoken.append("\(e.name) dealt \(taken). Your HP: \(hp).")
        if hp <= 0 {
            done = true
            t.sounds.append("sfx-gameover")
        }
    }

    /// waveComplete: a heal and a potion between waves; wave 5 wins the raid.
    private mutating func waveComplete(_ t: inout Turn, dice: inout some Dice) {
        guard remaining == 0 else { return }
        t.log.append("Wave \(wave) cleared! All enemies defeated.")
        t.spoken.append("Wave \(wave) cleared!")
        if wave >= 5 {
            done = true
            won = true
            return
        }
        wave += 1
        let heal = jsRound(Double(maxHp) * 0.20)
        hp = min(maxHp, hp + heal)
        potions += 1
        t.log.append("Wave cleared. You recover \(heal) HP and find a potion. Wave \(wave) incoming...")
        t.spoken.append("Healed \(heal) HP and received 1 potion. Potions: \(potions).")
        startWave(dice: &dice)
        t.newWave = true
        t.log.append("Wave \(wave) begins! \(enemies.count) enemies surge forward.")
        t.spoken.append("Wave \(wave) of 5. \(enemies.count) enemies in this wave. Currently facing: \(enemies[0].name).")
    }

    /// Raids offer the class's first three common skills.
    public var skills: [Skill] {
        let all = Skills.all(for: cls)
        let common = all.filter { $0.tier == "common" }.prefix(3)
        return common.isEmpty ? Array(all.prefix(3)) : Array(common)
    }

    /// raidUseSkill
    public mutating func useSkill(_ index: Int, dice: inout some Dice) -> Turn {
        var t = Turn()
        let list = skills
        guard !done, list.indices.contains(index) else { t.acted = false; return t }
        let s = list[index]
        guard sp >= s.spCost else { t.acted = false; t.spoken.append("Not enough SP."); return t }
        sp -= s.spCost
        guard let i = current else { waveComplete(&t, dice: &dice); return t }
        let base = dice.roll(atk) + atkBonus
        var dmg = 0
        var skip = false
        var msg = ""
        func only(_ log: String, _ say: String) -> Turn {
            var u = Turn()
            u.log.append(log)
            u.spoken.append(say)
            return u
        }
        switch s.effect {
        case "shield-bash": dmg = jsRound(Double(base) * 0.9); defBonus += 3; msg = "Shield Bash! \(dmg) damage, +3 defense!"
        case "war-cry": dmg = base * 2; msg = "War Cry! \(dmg) damage!"
        case "last-stand": dmg = Double(hp) <= Double(maxHp) * 0.30 ? base * 3 : base; msg = "Last Stand! \(dmg) damage!"
        case "swift-strike":
            let h2 = dice.roll(atk) + atkBonus
            dmg = base + h2
            msg = "Swift Strike! \(base)+\(h2)=\(dmg)!"
        case "inner-focus":
            hp = min(maxHp, hp + 15)
            sp = min(maxSp, sp + 10)
            return only("Inner Focus. +15 HP, +10 SP.", "Inner Focus. HP: \(hp). SP: \(sp).")
        case "pressure-point": dmg = base + def + defBonus; msg = "Pressure Point! \(dmg) ignoring defense!"
        case "backstab":
            if dice.chance(0.35) { msg = "Backstab missed!" } else { dmg = base * 3; msg = "BACKSTAB! \(dmg)!" }
        case "smoke-bomb": return only("Smoke Bomb! But you cannot flee a raid!", "Smoke Bomb has no effect in raids.")
        case "marked-kill": markedKill = true; return only("Marked Kill set.", "Next attack guaranteed crit.")
        case "holy-strike": dmg = base; hp = min(maxHp, hp + 20); msg = "Holy Strike! \(dmg) damage +20 HP!"
        case "divine-shield": divineShield = true; return only("Divine Shield raised.", "Divine Shield active.")
        case "smite": dmg = jsRound(Double(base) * 2.5); msg = "SMITE! \(dmg)!"
        case "entangle": skip = true; dmg = jsRound(Double(base) * 0.5); msg = "Entangle! \(dmg) enemy cannot counterattack!"
        case "venom": venomTurns = 3; return only("Venom applied, 3 turns.", "Venom active.")
        case "call-wild": dmg = base * 2; msg = "Call of Wild! \(dmg)!"
        case "arcane-bolt": dmg = jsRound(Double(base) * 1.8); msg = "Arcane Bolt! \(dmg)!"
        case "mana-shield": manaShield = 25; return only("Mana Shield raised.", "Mana Shield active.")
        case "obliterate": dmg = sp * 4 + base; sp = 0; msg = "OBLITERATE! \(dmg)!"
        default:
            // The web version had no rule for most skills, so they cost SP and did nothing.
            dmg = base
            msg = "\(s.name)! \(dmg) damage!"
        }
        if dmg > 0 { enemies[i].hp = max(0, enemies[i].hp - dmg) }
        t.log.append(msg)
        t.spoken.append(msg)
        if !enemies[i].alive {
            enemyDown(i, &t, dice: &dice, hardBonus: false)
            return t
        }
        if skip {
            t.log.append("Enemy rooted, cannot attack!")
            return t
        }
        if divineShield {
            divineShield = false
            t.log.append("Divine Shield absorbs!")
            t.spoken.append("Shield blocked all.")
            return t
        }
        if venomTurns > 0 {
            enemies[i].hp = max(0, enemies[i].hp - 8)
            venomTurns -= 1
            if !enemies[i].alive {
                t.kills.append(enemies[i].name)
                waveComplete(&t, dice: &dice)
                return t
            }
        }
        strike(i, &t, dice: &dice, block: def + defBonus)
        return t
    }
}

/// The raid save ("dd_raid"): today's win, raids won, coins and gold.
public struct RaidSave {
    let store: GameStore
    public init(store: GameStore) { self.store = store }

    private var data: [String: JSONValue] {
        get {
            guard let s = store.getItem("dd_raid"), let d = s.data(using: .utf8),
                  let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) else { return [:] }
            return v
        }
        nonmutating set {
            if let d = try? JSONEncoder().encode(newValue), let s = String(data: d, encoding: .utf8) { store.setItem("dd_raid", s) }
        }
    }

    public static func todayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 2026)-\(c.month ?? 1)-\(c.day ?? 1)"
    }

    public func doneToday(_ date: Date = Date()) -> Bool {
        if case .string(let d)? = data["completedDate"] { return d == Self.todayKey(date) }
        return false
    }

    public var totalWon: Int { if case .number(let n)? = data["totalRaidsWon"] { return Int(n) }; return 0 }

    /// raidVictory: records the win and returns the raid tier, which is also
    /// the Mystery Coins earned (paid with GameModel.addMysteryCoins).
    @discardableResult
    public func recordWin(gold: Int, date: Date = Date()) -> Int {
        var d = data
        d["completedDate"] = .string(Self.todayKey(date))
        let won = totalWon + 1
        d["totalRaidsWon"] = .number(Double(won))
        let tier = won >= 5 ? 3 : won >= 3 ? 2 : 1
        var total = 0.0
        if case .number(let n)? = d["totalGold"] { total = n }
        d["totalGold"] = .number(total + Double(gold))
        data = d
        return tier
    }

    /// Keeps the raid save's coin count matching "dd_mystery_coins" (addMysteryCoin).
    public func syncCoins(_ total: Int) {
        var d = data
        d["mysteryCoins"] = .number(Double(total))
        data = d
    }
}
