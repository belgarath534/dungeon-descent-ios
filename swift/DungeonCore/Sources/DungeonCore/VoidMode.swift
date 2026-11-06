import Foundation

/// A hero of Void Mode (VOID_HEROES).
public struct VoidHero: Equatable, Sendable {
    public var name: String
    public var icon: String
    public var hp: Int
    public var maxHp: Int
    public var atk: ClosedRange<Int>
    public var desc: String
    public var isElite = false
    public var isLegendary = false
    var healEvery = 0
    var healAmt = 0
    var enrageBelow = 0
    var canCrit = false
    var voidBane = false

    init(_ name: String, _ icon: String, _ hp: Int, _ atk: ClosedRange<Int>, _ desc: String, _ f: (inout VoidHero) -> Void = { _ in }) {
        self.name = name; self.icon = icon; self.hp = hp; maxHp = hp; self.atk = atk; self.desc = desc
        f(&self)
    }

    public var title: String { "\(icon) \(name)" + (isLegendary ? " ⭐ LEGENDARY" : isElite ? " ★ ELITE" : "") }
}

/// VOID MODE: you are the Void Commander (500 HP) against five waves of heroes.
public struct VoidMode: Equatable, Sendable {
    public static let maxHp = 500

    public static let waves: [[VoidHero]] = [
        [VoidHero("Wandering Warrior", "⚔️", 90, 12...18, "Overconfident. Undertrained. Still dangerous.")],
        [VoidHero("Holy Paladin", "🛡", 110, 12...20, "Carries a shield of faith. Heals every 3 turns.") { $0.healEvery = 3; $0.healAmt = 15 },
         VoidHero("Shadow Archer", "🏹", 75, 15...24, "Fires from a distance. Precise. Deadly.")],
        [VoidHero("Iron Warrior", "⚔️", 120, 14...20, "Veteran fighter. Has survived worse. Almost.") { $0.enrageBelow = 50 },
         VoidHero("Battle Mage", "🔮", 90, 18...28, "Channels ancient fire. Burns bright."),
         VoidHero("War Scout", "🗡️", 80, 12...20, "Fast. Strikes before you can react.") { $0.canCrit = true }],
        [VoidHero("Elite Crusader", "✨", 160, 16...26, "The chosen of a forgotten god.") { $0.isElite = true; $0.enrageBelow = 50 },
         VoidHero("War Cleric", "⛪", 110, 13...20, "Heals allies. Destroy it first.") { $0.healEvery = 3; $0.healAmt = 18 },
         VoidHero("Rogue Assassin", "🗡️", 95, 18...30, "Crits for massive damage.") { $0.canCrit = true }],
        [VoidHero("The Last Hero", "👑", 250, 18...28, "They said one would come who could end the Void. This is that one.") {
            $0.isLegendary = true; $0.enrageBelow = 33; $0.healEvery = 5; $0.healAmt = 25 },
         VoidHero("Ancient Paladin", "🌟", 160, 14...22, "Has fought darkness for forty years.") { $0.isElite = true; $0.healEvery = 4; $0.healAmt = 20 },
         VoidHero("Void Hunter", "🎯", 130, 16...26, "Trained specifically to kill entities like you.") { $0.isElite = true; $0.canCrit = true; $0.voidBane = true },
         VoidHero("Lorekeeper Mage", "📚", 120, 18...30, "Knows your weaknesses. Exploits them.") { $0.isElite = true }],
    ]

    public var hp = maxHp
    public var wave = 0
    public var heroes: [VoidHero] = waves[0]
    public var index = 0
    public var turn = 1
    public var shieldTurns = 0
    public var blastCooldown = 0
    public var shieldCooldown = 0
    public var drainCooldown = 0
    /// The wave is cleared and waits for Continue.
    public var waveCleared = false
    public var won = false
    public var lost = false

    public init() {}

    public var hero: VoidHero? { heroes.indices.contains(index) ? heroes[index] : nil }

    public enum Action: String, Sendable { case blast, shield, drain, strike }

    public struct Step: Equatable, Sendable {
        public var log: [String] = []
        public var acted = true
        public var heroFell: VoidHero? = nil
    }

    /// voidAction, then the hero's answer (voidEnemyTurn).
    public mutating func act(_ a: Action, dice: inout some Dice) -> Step {
        var s = Step()
        guard var e = hero, !won, !lost, !waveCleared else { s.acted = false; return s }
        var dmg = 0
        switch a {
        case .blast:
            guard blastCooldown == 0 else { s.acted = false; s.log = ["Void Blast on cooldown. \(blastCooldown) turns remaining."]; return s }
            dmg = dice.roll(40...70)
            blastCooldown = 2
            s.log.append("🌑 Void Blast tears through \(e.name) for \(dmg) damage!")
        case .shield:
            guard shieldCooldown == 0 else { s.acted = false; s.log = ["Shadow Shield on cooldown. \(shieldCooldown) turns remaining."]; return s }
            shieldTurns = 2
            shieldCooldown = 3
            s.log.append("🛡 Shadow Shield active. Damage reduced by 60% for 2 turns.")
        case .drain:
            guard drainCooldown == 0 else { s.acted = false; s.log = ["Soul Drain on cooldown. \(drainCooldown) turns remaining."]; return s }
            dmg = dice.roll(30...50)
            hp = min(Self.maxHp, hp + dmg)
            drainCooldown = 3
            s.log.append("💀 Soul Drain steals \(dmg) HP from \(e.name)!")
        case .strike:
            dmg = dice.roll(20...35)
            s.log.append("⚔ Dark Strike hits \(e.name) for \(dmg) damage.")
        }
        e.hp = max(0, e.hp - dmg)
        heroes[index] = e
        if e.hp <= 0 {
            s.log.append("\(e.name) has fallen.")
            s.heroFell = e
            heroDefeated(&s)
            return s
        }
        heroTurn(&s, dice: &dice)
        return s
    }

    mutating func heroTurn(_ s: inout Step, dice: inout some Dice) {
        guard var e = hero else { return }
        var dmg = dice.roll(e.atk)
        if e.canCrit && dice.chance(0.3) {
            dmg = jsRound(Double(dmg) * 2.2)
            s.log.append("CRITICAL HIT! \(e.name) lands a devastating blow for \(dmg)!")
        } else if e.voidBane && dice.chance(0.35) {
            dmg = jsRound(Double(dmg) * 1.7)
            s.log.append("\(e.name) exploits your void nature for \(dmg) damage!")
        } else if e.enrageBelow > 0 && e.hp * 100 <= e.maxHp * e.enrageBelow {
            dmg = jsRound(Double(dmg) * 1.5)
            s.log.append("\(e.name) is ENRAGED! Strikes for \(dmg)!")
        }
        if e.healEvery > 0 && turn % e.healEvery == 0 {
            e.hp = min(e.maxHp, e.hp + e.healAmt)
            heroes[index] = e
            s.log.append("\(e.name) heals for \(e.healAmt) HP! (\(e.hp)/\(e.maxHp))")
        }
        let shielded = shieldTurns > 0
        if shielded {
            dmg = jsRound(Double(dmg) * 0.4)
            shieldTurns -= 1
        }
        hp = max(0, hp - dmg)
        s.log.append("\(e.name) strikes for \(dmg) damage\(shielded ? " (shielded)" : ""). Your HP: \(hp).")
        if blastCooldown > 0 { blastCooldown -= 1 }
        if shieldCooldown > 0 { shieldCooldown -= 1 }
        if drainCooldown > 0 { drainCooldown -= 1 }
        turn += 1
        if hp <= 0 {
            lost = true
            s.log.append("\(e.name) ended your reign. The Void retreats — for now.")
        }
    }

    /// voidEnemyDefeated: the next hero steps up, or the wave ends (50 HP
    /// back), or after wave 5 the Void prevails.
    mutating func heroDefeated(_ s: inout Step) {
        index += 1
        if let next = hero {
            s.log.append("Next: \(next.name) steps forward. HP: \(next.hp).")
            return
        }
        if wave >= Self.waves.count - 1 {
            won = true
            s.log.append("THE VOID PREVAILS! All five waves defeated.")
            return
        }
        hp = min(Self.maxHp, hp + 50)
        waveCleared = true
        s.log.append("Wave \(wave + 1) cleared! The void restores 50 HP. The next wave approaches.")
    }

    /// voidNextWave
    public mutating func nextWave() -> String {
        guard waveCleared else { return "" }
        waveCleared = false
        wave += 1
        heroes = Self.waves[wave]
        index = 0
        return "Wave \(wave + 1) of 5. " + heroes.map(\.name).joined(separator: ", ") + "."
    }

    // MARK: The victory prize

    public enum Prize: String, CaseIterable, Sendable {
        case gold500, gold250, coins5, discount10, xpBoost, gold750, coins10

        public var label: String {
            switch self {
            case .gold500: return "500 gold"
            case .gold250: return "250 gold"
            case .coins5: return "5 Mystery Coins"
            case .discount10: return "10% Blacksmith discount for 1 hour"
            case .xpBoost: return "2x XP for your next run"
            case .gold750: return "750 gold"
            case .coins10: return "10 Mystery Coins"
            }
        }
    }

    /// The victory prize. The web version handed out a VOID code for it;
    /// the App Store doesn't allow codes that unlock things, so on Apple
    /// devices the prize is given straight away.
    public static func victoryPrize(dice: inout some Dice) -> Prize {
        Prize.allCases[dice.roll(0...(Prize.allCases.count - 1))]
    }
}

/// Rewards that the web version gave out as codes (Void Mode's VOID codes
/// and the yearly birthday codes). App Store guideline 3.1.1 doesn't allow
/// codes that unlock things, so the Swift version gives them directly.
public enum RewardCodes {
    public static let goldenSword: Item = {
        var it = Item(id: "golden-sword", name: "The Golden Sword", icon: "🗡️", type: "weapon",
                      desc: "Forged on the first birthday of Dungeon Descent. Exists in only one copy per player.",
                      atkBase: [15, 25], level: 5, weaponType: "sword", isEquippable: true)
        it.extra["birthdayExclusive"] = .bool(true)
        return it
    }()

    public struct Outcome: Equatable, Sendable {
        public var ok: Bool
        public var message: String
        /// Gold and Mystery Coins for the caller to add; the golden sword to keep.
        public var gold = 0
        public var coins = 0
        public var sword = false
    }

    /// The birthday package, once a year: 1,500 gold (the web version's 500
    /// plus its code's 1,000), The Golden Sword and 15% off at the Blacksmith.
    public static func birthday(year: Int, store: GameStore) -> Outcome {
        let key = "dd_birthday_claimed_\(year)", codeKey = "dd_redeemed_DDBD\(year % 100)"
        guard store.getItem(codeKey) == nil else {
            return Outcome(ok: false, message: "Already claimed this year. Come back next birthday.")
        }
        // Claimed the 500 gold before codes were taken out: the rest is still owed.
        let gold = store.getItem(key) == nil ? 1500 : 1000
        store.setItem(key, "true")
        store.setItem(codeKey, "true")
        store.setItem("dd_blacksmith_discount", #"{"pct":0.15,"source":"Birthday \#(year)"}"#)
        return Outcome(ok: true, message: "🎂 Birthday reward claimed! +\(gold) gold · The Golden Sword · 15% Blacksmith discount!",
                       gold: gold, sword: true)
    }

    /// Applies a prize to the store; returns gold and coins for the caller.
    public static func give(_ prize: VoidMode.Prize, store: GameStore, now: Date = Date()) -> Outcome {
        var out = Outcome(ok: true, message: "You received: \(prize.label).")
        switch prize {
        case .gold500: out.gold = 500
        case .gold250: out.gold = 250
        case .gold750: out.gold = 750
        case .coins5: out.coins = 5
        case .coins10: out.coins = 10
        case .discount10:
            let exp = ((now.timeIntervalSince1970 + 3600) * 1000).rounded()
            store.setItem("dd_blacksmith_discount", #"{"pct":0.1,"expires":\#(Int(exp)),"source":"Void Mode"}"#)
        case .xpBoost:
            // The web version saved a flag nothing ever read; Swift doubles XP
            // for the next run like the seasonal XP boosts.
            var n = Events.nextRun(store)
            n.xpMult = max(n.xpMult, 2)
            n.xpFloors = max(n.xpFloors, 10)
            Events.saveNextRun(n, store)
        }
        return out
    }
}
