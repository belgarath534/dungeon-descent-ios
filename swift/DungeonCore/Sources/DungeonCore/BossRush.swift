import Foundation

/// Boss Rush (BOSS RUSH ENGINE): nine bosses back to back with a small heal
/// between fights, Mystery Coins after the 3rd, 6th and 9th.
public struct BossRush: Codable, Sendable {
    public struct Boss: Codable, Sendable {
        public let name: String
        public let icon: String
        public let hp: Int
        public let atk: ClosedRange<Int>
        public let dungeon: String
    }

    /// ALL_BOSSES
    public static let bosses: [Boss] = [
        Boss(name: "Malachar the Undying", icon: "👑", hp: 140, atk: 15...25, dungeon: "crypt"),
        Boss(name: "The Bone Sovereign", icon: "💀", hp: 130, atk: 14...23, dungeon: "crypt"),
        Boss(name: "The Void Walker", icon: "🌑", hp: 135, atk: 15...24, dungeon: "crypt"),
        Boss(name: "The Eternal Pyre", icon: "🔥", hp: 160, atk: 16...26, dungeon: "ashbound"),
        Boss(name: "The Ashen Throne", icon: "👑", hp: 150, atk: 15...25, dungeon: "ashbound"),
        Boss(name: "The Cinder Colossus", icon: "🌋", hp: 170, atk: 14...24, dungeon: "ashbound"),
        Boss(name: "The Eternal Winter", icon: "❄️", hp: 165, atk: 15...26, dungeon: "frosthold"),
        Boss(name: "The Frozen King", icon: "👑", hp: 155, atk: 14...25, dungeon: "frosthold"),
        Boss(name: "The Void Below", icon: "🌑", hp: 170, atk: 14...24, dungeon: "frosthold"),
    ]

    public var bossIndex = 0
    public var bossHp: Int
    public var hp: Int
    public let maxHp: Int
    public let atk: ClosedRange<Int>
    public let def: Int
    public let atkBonus: Int
    public var defBonus = 0
    public var sp: Int
    public let maxSp: Int
    public var potions: Int
    public var defending = false
    public var markedKill = false
    public var coinsEarned = 0
    public let cls: String
    public var done = false
    public var won = false
    public let startedAt: Double

    public var boss: Boss { Self.bosses[min(bossIndex, Self.bosses.count - 1)] }

    /// beginBossRush: stats from the character's level, saved gear and coin upgrades.
    public init(character ch: PlayerCharacter, weapon: Item?, armor: Item?, upgrades: Set<String>,
                now: Double = Date().timeIntervalSince1970) {
        let info = GameData.classInfo(ch.cls)
        let level = ch.persistLevel ?? 1
        maxHp = info.maxHp + (upgrades.contains("cu-hp-boost") ? 10 : 0) + (level - 1) * 10
        hp = maxHp
        var weaponBonus = upgrades.contains("cu-starting-blade") ? 2 : 0
        if let w = weapon { weaponBonus += (w.weaponAttack.lowerBound + w.weaponAttack.upperBound) / 2 }
        atk = info.atk
        def = info.def + (armor?.armorDefense ?? 0)
        atkBonus = weaponBonus + (level - 1) / 2
        // The SP boost raises current SP above the maximum, like the web version.
        sp = 20 + (level - 1) * 2 + (upgrades.contains("cu-sp-boost") ? 5 : 0)
        maxSp = 20 + (level - 1) * 2
        potions = 2 + level / 3
        cls = ch.cls
        bossHp = Self.bosses[0].hp
        startedAt = now
    }

    public struct Turn: Sendable {
        public var log: [String] = []
        public var spoken: [String] = []
        public var sounds: [String] = []
        public var bossDefeated: String?
        public var coins = 0
        public var acted = true
    }

    /// The boss's counter-attack (inside brFight's timeout).
    private mutating func bossStrikes(_ t: inout Turn, dice: inout some Dice, wasDefending: Bool) {
        let raw = dice.roll(boss.atk)
        let blocked = min(def + defBonus + (wasDefending ? 4 : 0), raw * 55 / 100)
        let taken = max(1, raw - blocked)
        hp = max(0, hp - taken)
        t.sounds.append("sfx-hurt")
        t.log.append("\(boss.name) strikes for \(taken). HP: \(hp)/\(maxHp).")
        t.spoken.append("\(boss.name) dealt \(taken). HP: \(hp).")
        if hp <= 0 {
            done = true
            t.sounds.append("sfx-gameover")
        }
    }

    /// A boss falls: coins at 3, 6 and 9, then a heal before the next one.
    private mutating func bossDown(_ t: inout Turn) {
        t.sounds.append("sfx-victory")
        t.bossDefeated = boss.name
        t.log.append("\(boss.name) defeated!")
        t.spoken.append("\(boss.name) defeated! Boss \(bossIndex + 1) of 9 down!")
        bossIndex += 1
        let coins = bossIndex == 3 ? 1 : bossIndex == 6 ? 2 : bossIndex == 9 ? 3 : 0
        if coins > 0 {
            coinsEarned += coins
            t.coins = coins
            t.log.append("✦ \(coins) Mystery Coin\(coins > 1 ? "s" : "") earned!")
            t.spoken.append("\(coins) Mystery Coin\(coins > 1 ? "s" : "") earned!")
        }
        if bossIndex >= Self.bosses.count {
            done = true
            won = true
            return
        }
        let heal = jsRound(Double(maxHp) * 0.25)
        hp = min(maxHp, hp + heal)
        sp = min(maxSp, sp + 5)
        defending = false
        bossHp = boss.hp
        t.log.append("You recover \(heal) HP and 5 SP before the next battle.")
        t.spoken.append("Recovered \(heal) HP. Next boss: \(boss.name).")
        t.log.append("Boss \(bossIndex + 1) of 9: \(boss.name) emerges!")
        t.spoken.append("Boss \(bossIndex + 1) of 9: \(boss.name). HP: \(boss.hp). Fight!")
    }

    public enum Action { case attack, heavy, defend, potion }

    /// brFight
    public mutating func fight(_ action: Action, dice: inout some Dice) -> Turn {
        var t = Turn()
        guard !done else { t.acted = false; return t }
        let base = dice.roll(atk) + atkBonus
        let wasDefending = defending
        defending = false
        var dmg = 0
        switch action {
        case .attack:
            let crit = dice.chance(0.10) || markedKill
            if markedKill { markedKill = false; t.log.append("Marked Kill activates!") }
            dmg = crit ? jsRound(Double(base) * 1.8) : base
            t.sounds.append(crit ? "sfx-crit" : "sfx-attack")
            t.log.append(crit ? "CRITICAL HIT for \(dmg)!" : "You attack for \(dmg).")
        case .heavy:
            if dice.chance(0.30) {
                t.sounds.append("sfx-heavy-miss")
                t.log.append("Heavy strike misses!")
            } else {
                dmg = jsRound(Double(base) * 1.7)
                t.sounds.append("sfx-heavy-hit")
                t.log.append("Heavy strike: \(dmg)!")
            }
        case .defend:
            defending = true
            dmg = jsRound(Double(base) * 0.5)
            t.log.append("You defend, dealing \(dmg).")
        case .potion:
            guard potions > 0 else {
                defending = wasDefending
                t.acted = false
                t.log.append("No potions!")
                t.spoken.append("No potions.")
                return t
            }
            let heal = jsRound(Double(maxHp) * 0.35)
            hp = min(maxHp, hp + heal)
            potions -= 1
            t.sounds.append("sfx-potion")
            t.log.append("Potion: +\(heal) HP. Potions left: \(potions).")
            t.spoken.append("Healed \(heal). HP: \(hp). Potions: \(potions).")
            return t
        }
        if dmg > 0 { bossHp = max(0, bossHp - dmg) }
        if bossHp <= 0 { bossDown(&t); return t }
        bossStrikes(&t, dice: &dice, wasDefending: wasDefending)
        return t
    }

    /// Boss Rush offers the class's first two common skills (getBRSkills).
    public var skills: [Skill] {
        let all = Skills.all(for: cls)
        let common = all.filter { $0.tier == "common" }.prefix(2)
        return common.isEmpty ? Array(all.prefix(2)) : Array(common)
    }

    /// brUseSkill: a few skills have their own effect; the rest hit for normal damage.
    public mutating func useSkill(_ index: Int, dice: inout some Dice) -> Turn {
        var t = Turn()
        let list = skills
        guard !done, list.indices.contains(index) else { t.acted = false; return t }
        let s = list[index]
        guard sp >= s.spCost else {
            t.acted = false
            t.spoken.append("Not enough SP.")
            return t
        }
        sp -= s.spCost
        let base = dice.roll(atk) + atkBonus
        var dmg = 0
        var msg = ""
        switch s.effect {
        case "shield-bash": dmg = jsRound(Double(base) * 0.9); defBonus += 3; msg = "Shield Bash! \(dmg) dmg!"
        case "swift-strike": dmg = base + dice.roll(atk); msg = "Swift Strike! \(dmg)!"
        case "holy-strike": dmg = base; hp = min(maxHp, hp + 20); msg = "Holy Strike! \(dmg) dmg +20 HP!"
        case "backstab":
            if dice.chance(0.35) { msg = "Backstab missed!" } else { dmg = base * 3; msg = "BACKSTAB! \(dmg)!" }
        case "entangle":
            // The boss loses its attack (the web version's damage line never runs).
            t.log.append("Entangle roots the boss!")
            t.spoken.append("Boss cannot attack this turn!")
            return t
        case "arcane-bolt": dmg = jsRound(Double(base) * 1.8); msg = "Arcane Bolt! \(dmg)!"
        default: dmg = base; msg = "\(s.name)! \(dmg) damage!"
        }
        if dmg > 0 { bossHp = max(0, bossHp - dmg) }
        t.log.append(msg)
        t.spoken.append(msg)
        if bossHp <= 0 { bossDown(&t); return t }
        // Skills don't count the defend bonus.
        bossStrikes(&t, dice: &dice, wasDefending: false)
        return t
    }
}

/// The ten best Boss Rush runs ("dd_br_scores"): most bosses, then fastest.
public struct BossRushScore: Codable, Sendable {
    public var bosses: Int
    public var time: Int
    public var timeStr: String
    public var cls: String
    public var date: String

    public static func save(_ entry: BossRushScore, store: GameStore) {
        var list = load(store)
        list.append(entry)
        list.sort { $0.bosses != $1.bosses ? $0.bosses > $1.bosses : $0.time < $1.time }
        if let d = try? JSONEncoder().encode(Array(list.prefix(10))), let s = String(data: d, encoding: .utf8) {
            store.setItem("dd_br_scores", s)
        }
    }

    public static func load(_ store: GameStore) -> [BossRushScore] {
        guard let s = store.getItem("dd_br_scores"), let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([BossRushScore].self, from: d)) ?? []
    }
}
