import Foundation

/// Endless Descent, the AFK mode (ENDLESS DESCENT — AFK MODE): one automatic
/// fight every 15 seconds (20 with Steady Rhythm) until the champion falls.
/// The run is Codable so it survives the app being closed, and `fight` is a
/// pure step so time spent away can be caught up fight by fight.
public struct AFKRun: Codable, Sendable {
    public struct Line: Codable, Sendable, Equatable {
        public var text: String
        public var color: UInt32
    }

    /// AFK_EXCLUSIVE_ENEMIES and the crypt tables share this shape.
    struct Foe {
        var name: String
        var icon: String
        var hp: Int
        var atk: ClosedRange<Int>
        var special: String?
    }

    public var charIndex: Int
    public var charName: String
    public var cls: String
    public var floor = 1
    public var hp: Int
    public var maxHp: Int
    public var atk: Int
    public var def: Int
    public var points = 0
    public var potions: Int
    public var fightSeconds: Double
    public var level: Int
    public var xp: Int
    public var levelsGainedThisRun = 0
    public var skills: [String]
    public var battleScrollActive = false
    public var xpBoostFights = 0
    public var xpBoostMult = 1.0
    public var bandages: Int
    public var luckyCharm: Bool
    public var deathWard: Bool
    public var deathWardUsed = false
    public var classPassive: String?
    public var totalDmgDealt = 0
    public var totalDmgTaken = 0
    public var enemiesDefeated = 0
    public var bossesDefeated = 0
    public var running = true
    /// When the run began and when the last fight happened (seconds since 1970).
    public var startedAt: Double
    public var lastFightAt: Double
    /// Newest first, at most 50 (afkLog).
    public var log: [Line] = []

    // MARK: Setup

    /// AFK_SHOP_ITEMS
    public struct ShopItem: Sendable, Identifiable {
        public let id, name, icon: String
        public let cost: Int
        public let desc: String
        public let max: Int
    }

    public static let shop: [ShopItem] = [
        ShopItem(id: "afk-extra-potion", name: "Extra Potion", icon: "🧪", cost: 50, desc: "Start each run with 1 extra Health Potion.", max: 3),
        ShopItem(id: "afk-hp-boost", name: "Resilience", icon: "❤️", cost: 80, desc: "+20 max HP in Endless Descent runs.", max: 5),
        ShopItem(id: "afk-atk-boost", name: "Sharpened Blade", icon: "⚔️", cost: 80, desc: "+5 attack in Endless Descent runs.", max: 5),
        ShopItem(id: "afk-slow-fight", name: "Steady Rhythm", icon: "⏱️", cost: 120, desc: "Auto-fight timer slows by 3 seconds.", max: 1),
        ShopItem(id: "afk-bandages", name: "Bandages", icon: "🩹", cost: 100, desc: "Passively regenerate 8 HP after every floor.", max: 3),
        ShopItem(id: "afk-lucky-charm", name: "Lucky Charm", icon: "🍀", cost: 150, desc: "15% chance to dodge any boss attack completely.", max: 1),
        ShopItem(id: "afk-iron-will", name: "Iron Will", icon: "🛡️", cost: 180, desc: "Start every AFK run with +80 max HP bonus.", max: 1),
        ShopItem(id: "afk-death-save", name: "Death Ward", icon: "✨", cost: 250, desc: "Once per run, survive a killing blow with 1 HP.", max: 1),
        ShopItem(id: "afk-mystery-coins", name: "Coin Cache", icon: "🪙", cost: 200, desc: "Convert 200 Descent Points to 2 Mystery Coins.", max: 99),
        ShopItem(id: "afk-title-void", name: "Title: TheEndless", icon: "⬇", cost: 300, desc: "Unlock the \"TheEndless\" leaderboard title.", max: 1),
        ShopItem(id: "afk-title-fallen", name: "Title: TheFallen", icon: "💀", cost: 300, desc: "Unlock the \"TheFallen\" leaderboard title.", max: 1),
    ]

    static let passives: [String: String] = [
        "Warrior": "warrior", "Assassin": "assassin", "Necromancer": "necromancer", "Paladin": "paladin",
        "Berserker": "berserker", "Monk": "monk", "Druid": "druid", "Sorcerer": "sorcerer", "Bard": "bard",
        "Alchemist": "alchemist", "BloodKnight": "bloodknight", "Naturalist": "naturalist", "Warlock": "warlock",
        "DeathKnight": "deathknight", "Dragonborn": "dragonborn", "Cleric": "cleric", "Wizard": "wizard",
    ]

    /// startAFKRun: 1000 HP plus shop boosts and the character's saved level,
    /// attack from the level, shop and equipped weapon, and the class passive.
    public init(character ch: PlayerCharacter, index: Int, save: AFKSave, weapon: Item?, armor: Item?,
                now: Double = Date().timeIntervalSince1970) {
        let up = save.upgrades
        let baseHp = 1000 + (up["afk-hp-boost"] ?? 0) * 50 + ((up["afk-iron-will"] ?? 0) > 0 ? 200 : 0)
        let lvl = ch.persistLevel ?? 1
        charIndex = index
        charName = ch.name
        cls = ch.cls
        maxHp = baseHp + (lvl - 1) * 10
        hp = maxHp
        var weaponBonus = 0
        if let w = weapon { weaponBonus = (w.weaponAttack.lowerBound + w.weaponAttack.upperBound) / 2 }
        let armorBonus = armor.map { $0.defBase ?? $0.defBonus ?? 0 } ?? 0
        func num(_ k: String) -> Int { if case .number(let n)? = ch.extra[k] { return Int(n) }; return 0 }
        let chLevel = num("level")
        atk = 28 + jsRound(Double(num("atkBonus")) * 0.7) + (chLevel > 0 ? (chLevel - 1) * 2 : 0)
            + (up["afk-atk-boost"] ?? 0) * 5 + (lvl - 1) + weaponBonus
        def = num("defBonus") + armorBonus
        potions = 5 + (up["afk-extra-potion"] ?? 0)
        fightSeconds = (up["afk-slow-fight"] ?? 0) > 0 ? 20 : 15
        level = lvl
        xp = num("persistXp")
        if case .array(let a)? = ch.extra["persistSkills"] {
            skills = a.compactMap { if case .string(let s) = $0 { return s }; return nil }
        } else {
            skills = []
        }
        bandages = up["afk-bandages"] ?? 0
        luckyCharm = (up["afk-lucky-charm"] ?? 0) > 0
        deathWard = (up["afk-death-save"] ?? 0) > 0
        classPassive = Self.passives[ch.cls]
        startedAt = now
        lastFightAt = now
        switch classPassive {
        case "berserker": atk = jsRound(Double(atk) * 1.20); def = max(0, def - 2)
        case "sorcerer": atk = jsRound(Double(atk) * 1.25); maxHp = jsRound(Double(maxHp) * 0.85); hp = maxHp
        case "wizard": atk = jsRound(Double(atk) * 1.30); maxHp = jsRound(Double(maxHp) * 0.80); hp = maxHp
        case "dragonborn": atk = jsRound(Double(atk) * 1.15)
        case "naturalist": def += 3
        default: break
        }
        add("The descent begins. \(ch.name) steps into the dark.", 0x8888ff)
    }

    // MARK: One fight

    /// What one step did, for the screen, VoiceOver and the Live Activity.
    public struct Step: Sendable {
        public var spoken: [String] = []
        public var ended = false
        /// Something worth waking the lock screen for: a boss, a level, the end.
        public var alert: String?
        public var leveledUp = false
    }

    mutating func add(_ text: String, _ color: UInt32 = 0x888888) {
        log.insert(Line(text: text, color: color), at: 0)
        if log.count > 50 { log.removeLast(log.count - 50) }
    }

    static let exclusive: [String: [Foe]] = [
        "t3": [
            Foe(name: "The Hydra", icon: "🐉", hp: 95, atk: 14...22, special: "hydra"),
            Foe(name: "The Minotaur", icon: "🐂", hp: 110, atk: 12...18, special: "minotaur"),
            Foe(name: "The Colossus Spider", icon: "🕷️", hp: 80, atk: 11...17, special: "spider"),
            Foe(name: "The Watcher", icon: "👁️", hp: 70, atk: 8...12, special: "watcher"),
            Foe(name: "The Accumulator", icon: "🔮", hp: 88, atk: 10...16, special: "accumulator"),
            Foe(name: "Void Leech", icon: "🌑", hp: 75, atk: 12...19, special: "void-leech"),
            Foe(name: "The Eternal", icon: "♾️", hp: 100, atk: 11...17, special: "eternal"),
            Foe(name: "Soul Collector", icon: "💜", hp: 85, atk: 13...20, special: "soul-collector"),
        ],
        "t4": [
            Foe(name: "The Endless Knight", icon: "💀", hp: 130, atk: 16...24, special: "endless-knight"),
            Foe(name: "The Void Titan", icon: "🌀", hp: 150, atk: 18...28, special: "void-titan"),
            Foe(name: "The Dread Hydra", icon: "🐲", hp: 140, atk: 15...22, special: "dread-hydra"),
            Foe(name: "The Labyrinth Guard", icon: "🗿", hp: 160, atk: 14...20, special: "labyrinth"),
        ],
    ]

    /// afkDoFight: a boss every 25 floors, otherwise a crypt enemy (or an
    /// Endless-only one from floor 20), fought to the end in up to 20 rounds.
    public mutating func fight(dice: inout some Dice, save: AFKSave, now: Double = Date().timeIntervalSince1970) -> Step {
        var s = Step()
        guard running else { return s }
        lastFightAt = now
        if floor > 0 && floor % 25 == 0 { return bossFight(dice: &dice, save: save) }

        let tier = floor <= 5 ? "t1" : floor <= 15 ? "t2" : floor <= 30 ? "t3" : "t4"
        let crypt = Bestiary.crypt
        // The crypt has no fourth tier; the web version fell back to tier 2.
        let table = tier == "t1" ? crypt.t1 : tier == "t3" ? crypt.t3 : crypt.t2
        var pool = table.map { Foe(name: $0.name, icon: $0.icon, hp: $0.hp, atk: $0.atk, special: nil) }
        if floor >= 20, let ex = Self.exclusive[tier], dice.chance(tier == "t4" ? 0.50 : 0.30) { pool = ex }
        var base = pool[dice.roll(0...(pool.count - 1))]
        if base.special == "void-titan" {
            base = Foe(name: "The Void Titan", icon: "🌀", hp: 80 + floor * 2,
                       atk: (10 + floor * 3 / 10)...(16 + floor * 4 / 10), special: "void-titan")
        }

        if classPassive == "assassin" && dice.chance(0.20) {
            let pts = 5 + floor / 2
            points += pts
            xp += 20 + floor * 3
            levelUp(&s)
            floor += 1
            add("🗡️ Assassin instinct — one-shot kill! +\(pts) pts. → Floor \(floor)", 0xff88ff)
            s.spoken.append("Assassin one-shot. Floor \(floor).")
            return s
        }

        let mult = 1 + Double(floor - 1) * 0.03
        var eHp = jsRound(Double(base.hp) * mult)
        var eAtk = jsRound(Double(base.atk.lowerBound) * mult)...max(jsRound(Double(base.atk.lowerBound) * mult), jsRound(Double(base.atk.upperBound) * mult))
        var dealt = 0, taken = 0, rounds = 0

        func exchange(maxRounds: Int) {
            while eHp > 0 && hp > 0 && rounds < maxRounds {
                rounds += 1
                var pDmg = max(1, dice.roll((atk - 2)...(atk + 6)))
                if base.special == "watcher" {
                    let f = 1 + Double(rounds) * 0.5
                    let lo = jsRound(Double(eAtk.lowerBound) * f), hi = jsRound(Double(eAtk.upperBound) * f)
                    eAtk = lo...max(lo, hi)
                }
                if battleScrollActive && rounds == 1 { pDmg *= 2; battleScrollActive = false }
                eHp -= pDmg
                dealt += pDmg
                totalDmgDealt += pDmg
                if eHp <= 0 { break }
                var eDmg = max(1, dice.roll(eAtk) - def)
                if classPassive == "paladin" { eDmg = jsRound(Double(eDmg) * 0.85) }
                if classPassive == "deathknight" { eDmg = jsRound(Double(eDmg) * 0.80) }
                if classPassive == "monk" && dice.chance(0.10) { eDmg = 0 }
                if classPassive == "bard" && dice.chance(0.15) {
                    eDmg = 0
                    add("🎵 Bard charm — enemy attack skipped!", 0x88ffaa)
                }
                // The web version doubled the hit after it had landed, so these
                // surges never did anything; here the extra hit lands.
                if classPassive == "warlock" && dice.chance(0.25) {
                    eHp -= pDmg; dealt += pDmg; totalDmgDealt += pDmg
                    add("🧿 Warlock surge — double damage!", 0xcc88ff)
                }
                if classPassive == "wizard" && dice.chance(0.20) {
                    eHp -= pDmg; dealt += pDmg; totalDmgDealt += pDmg
                    add("🧙 Arcane surge — spell doubles in power!", 0xaaaaff)
                }
                hp = max(0, hp - eDmg)
                totalDmgTaken += eDmg
                taken += eDmg
            }
        }

        exchange(maxRounds: 20)
        // The Endless Knight rises once with half its HP. The web version then
        // ended the run as if you had died; here the fight goes on.
        if eHp <= 0 && base.special == "endless-knight" {
            eHp = jsRound(Double(base.hp) * 0.50)
            add("💀 The Endless Knight falls... and rises again with \(eHp) HP!", 0xff8888)
            s.spoken.append("The Endless Knight respawns with \(eHp) HP!")
            exchange(maxRounds: rounds + 20)
        }

        if eHp <= 0 {
            let pts = 5 + floor / 2
            points += pts
            enemiesDefeated += 1
            rollLoot(&s, dice: &dice)
            var xpGain = 20 + floor * 3
            if xpBoostFights > 0 {
                xpGain = jsRound(Double(xpGain) * xpBoostMult)
                xpBoostFights -= 1
                if xpBoostFights == 0 { add("🔮 Void Shard expired.", 0x555555) }
            }
            xp += xpGain
            levelUp(&s)
            if classPassive == "druid" { hp = min(maxHp, hp + jsRound(Double(maxHp) * 0.03)) }
            if classPassive == "cleric" && floor % 5 == 0 {
                let h = jsRound(Double(maxHp) * 0.05)
                hp = min(maxHp, hp + h)
                add("✝️ Cleric blessing — +\(h) HP.", 0xffffaa)
            }
            floor += 1
            let color: UInt32 = Double(hp) > Double(maxHp) * 0.5 ? 0xa0e0ff : Double(hp) > Double(maxHp) * 0.25 ? 0xffaa44 : 0xff6666
            if classPassive == "necromancer" { hp = min(maxHp, hp + 5) }
            if bandages > 0 { hp = min(maxHp, hp + bandages * 8) }
            add("\(base.icon) \(base.name) defeated in \(rounds) rounds. Dealt \(dealt), took \(taken). +\(pts) pts +\(xpGain) xp. HP: \(hp)/\(maxHp)\(classPassive == "necromancer" ? " (+5 lifesteal)" : "")", color)
            s.spoken.append("\(base.name) defeated. Floor \(floor). Plus \(pts) descent points. HP: \(hp).")
            if hp <= jsRound(Double(maxHp) * 0.30) && potions > 0 {
                let heal = jsRound(Double(maxHp) * (classPassive == "alchemist" ? 0.60 : 0.45))
                hp = min(maxHp, hp + heal)
                potions -= 1
                add("🧪 Auto-potion used after combat. HP: \(hp)/\(maxHp). \(potions) left.\(classPassive == "alchemist" ? " (Alchemist boost)" : "")", 0x44ff88)
                s.spoken.append("Auto potion. HP: \(hp). Potions left: \(potions).")
            }
            if floor > 1 && floor % 10 == 0 {
                hp = maxHp
                potions = min(potions + 3, 10)
                add("✨ Floor \(floor) cleared. Full heal granted. Potions restocked. The descent deepens.", 0x44ff88)
                s.spoken.append("Floor \(floor) milestone. Full heal! HP restored. Potions refilled to \(potions).")
            } else if floor % 10 == 1 && floor > 1 {
                add("⬇ Floor \(floor) reached. The darkness deepens.", 0x8888ff)
                s.spoken.append("Milestone! Floor \(floor). Total points this run: \(points).")
            }
            return s
        }

        if hp <= 0 && deathWard && !deathWardUsed {
            deathWardUsed = true
            hp = 1
            add("✨ Death Ward activates — you survive with 1 HP!", 0xffdd44)
            s.spoken.append("Death Ward activated. You survive with 1 HP.")
            s.alert = "Death Ward — survived with 1 HP"
            return s
        }
        // Twenty rounds without a winner: the web version counted that as a death too.
        add("\(base.icon) \(base.name) — you fell after \(rounds) rounds. Dealt \(dealt), took \(taken).", 0xff4444)
        s.spoken.append("You fell to \(base.name) on floor \(floor).")
        s.alert = "Fell to \(base.name) on floor \(floor)"
        running = false
        s.ended = true
        return s
    }

    struct Boss { let name, icon: String; let hpMult, atkMult: Double; let pts: Int; let color: UInt32; let msg: String }

    static let bosses: [Boss] = [
        Boss(name: "The Hollow Warden", icon: "🕯️", hpMult: 1.8, atkMult: 1.2, pts: 50, color: 0xaaaaff, msg: "A guardian stirs in the dark."),
        Boss(name: "The Ashen Colossus", icon: "🔥", hpMult: 2.2, atkMult: 1.4, pts: 75, color: 0xff8844, msg: "The floor trembles. Something massive descends."),
        Boss(name: "The Void Sentinel", icon: "🌑", hpMult: 2.6, atkMult: 1.6, pts: 100, color: 0x8888ff, msg: "The void takes shape."),
        Boss(name: "The Eternal Revenant", icon: "💀", hpMult: 3.0, atkMult: 1.8, pts: 150, color: 0xff4444, msg: "It has been waiting."),
        Boss(name: "The Deep Architect", icon: "🏛️", hpMult: 3.5, atkMult: 2.0, pts: 250, color: 0xffdd44, msg: "Something ancient notices your descent."),
    ]

    /// afkDoBossFight
    mutating func bossFight(dice: inout some Dice, save: AFKSave) -> Step {
        var s = Step()
        let boss = Self.bosses[min(floor / 100, Self.bosses.count - 1)]
        var bHp = jsRound(Double(80 + floor / 25 * 8) * boss.hpMult)
        let atkBase = 12 + Int((Double(floor).squareRoot() * 1.8).rounded(.down))
        let lo = jsRound(Double(atkBase) * boss.atkMult * 0.85), hi = jsRound(Double(atkBase) * boss.atkMult)
        let bAtk = lo...max(lo, hi)
        add("⚡ BOSS FLOOR \(floor) — \(boss.icon) \(boss.name)", boss.color)
        add(boss.msg, 0x555555)
        s.spoken.append("Boss floor \(floor). \(boss.name). \(boss.msg)")
        var dealt = 0, taken = 0, rounds = 0
        while bHp > 0 && hp > 0 && rounds < 40 {
            rounds += 1
            var p = max(1, dice.roll((atk - 2)...(atk + 8)))
            if classPassive == "warrior" { p = jsRound(Double(p) * 1.10) }
            bHp -= p
            dealt += p
            if bHp <= 0 { break }
            var e = max(1, dice.roll(bAtk) - def)
            if luckyCharm && dice.chance(0.15) {
                e = 0
                add("🍀 Lucky Charm — boss attack dodged!", 0x44ff88)
            }
            hp = max(0, hp - e)
            taken += e
        }
        if bHp <= 0 {
            let bonus = boss.pts + floor / 5
            points += bonus
            let xpGain = 150 + floor * 5
            xp += xpGain
            levelUp(&s)
            floor += 1
            hp = maxHp
            if classPassive == "bloodknight" {
                let h = jsRound(Double(maxHp) * 0.08)
                hp = min(maxHp, hp + h)
                add("🩸 BloodKnight — +\(h) HP from boss kill.", 0xff6666)
            }
            bossesDefeated += 1
            add("⚡ \(boss.name) DEFEATED! +\(bonus) pts +\(xpGain) xp. Full heal!", boss.color)
            s.spoken.append("Boss defeated. \(boss.name) falls. Plus \(bonus) descent points. Full heal!")
            s.alert = "\(boss.name) defeated on floor \(floor - 1)"
        } else {
            add("💀 Fell to \(boss.name) on floor \(floor). Dealt \(dealt), took \(taken).", 0xff4444)
            s.spoken.append("You fell to \(boss.name) on floor \(floor).")
            s.alert = "Fell to \(boss.name) on floor \(floor)"
            hp = 0
            running = false
            s.ended = true
        }
        return s
    }

    static let xpTable = [0, 100, 220, 380, 580, 820, 1100, 1430, 1810, 2240, 9999]

    public var xpNeeded: Int? { level < Self.xpTable.count ? Self.xpTable[level] : nil }

    /// afkCheckLevelUp: up to level 10, +10 max HP and +1 attack each.
    mutating func levelUp(_ s: inout Step) {
        guard level < 10 else { return }
        while let need = xpNeeded, xp >= need, level < 10 {
            xp -= need
            level += 1
            levelsGainedThisRun += 1
            maxHp += 10
            hp = min(maxHp, hp + 10)
            atk += 1
            add("━━━━━━━━━━━━━━━━━━━━━━━━━━━━", 0x333333)
            add("⬆ LEVEL UP! Now Level \(level). +10 max HP. +1 attack. HP fully restored to \(maxHp).", 0xffdd44)
            s.spoken.append("Level up! You are now Level \(level). Max HP increased to \(maxHp). Attack increased. HP restored.")
            s.leveledUp = true
            if s.alert == nil { s.alert = "Level up! Now Level \(level)" }
        }
    }

    // MARK: Loot

    struct Loot { let id, name: String; let floor: Int; let weight: Int }

    /// AFK_LOOT_ITEMS, weighted common 4, uncommon 2, rare 1, legendary 0.3 (×10 here).
    static let loot: [Loot] = [
        Loot(id: "potion", name: "Health Potion", floor: 1, weight: 40),
        Loot(id: "big-potion", name: "Mega Potion", floor: 20, weight: 20),
        Loot(id: "rusty-blade", name: "Rusty Blade", floor: 1, weight: 40),
        Loot(id: "sharp-edge", name: "Sharp Edge", floor: 10, weight: 20),
        Loot(id: "void-blade", name: "Void Blade", floor: 30, weight: 10),
        Loot(id: "iron-fragment", name: "Iron Fragment", floor: 1, weight: 40),
        Loot(id: "heavy-stone", name: "Heavy Stone", floor: 5, weight: 20),
        Loot(id: "void-armor", name: "Void Plate", floor: 40, weight: 10),
        Loot(id: "blood-vial", name: "Blood Vial", floor: 5, weight: 20),
        Loot(id: "herb-bundle", name: "Herb Bundle", floor: 3, weight: 40),
        Loot(id: "descent-gem", name: "Descent Gem", floor: 10, weight: 20),
        Loot(id: "battle-scroll", name: "Battle Scroll", floor: 15, weight: 20),
        Loot(id: "void-shard", name: "Void Shard", floor: 25, weight: 10),
        Loot(id: "elixir", name: "Elixir of Power", floor: 50, weight: 3),
    ]

    /// afkRollLoot: 15% a kill, +5% every 25 floors.
    mutating func rollLoot(_ s: inout Step, dice: inout some Dice) {
        guard dice.chance(0.15 + Double(floor / 25) * 0.05) else { return }
        let available = Self.loot.filter { floor >= $0.floor }
        let total = available.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return }
        let roll = dice.roll(1...total)
        var cum = 0
        var picked = available[0]
        for item in available {
            cum += item.weight
            if roll <= cum { picked = item; break }
        }
        func say(_ log: String, _ color: UInt32, _ spoken: String) { add(log, color); s.spoken.append(spoken) }
        switch picked.id {
        case "potion":
            potions += 1
            say("🧪 Health Potion found. Potions: \(potions).", 0x44ff88, "Found a Health Potion. Potions now: \(potions).")
        case "big-potion":
            let h = jsRound(Double(maxHp) * 0.60)
            hp = min(maxHp, hp + h)
            say("🧪 Mega Potion! Healed \(h) HP. HP: \(hp)/\(maxHp).", 0x44ff88, "Found a Mega Potion. Healed \(h) HP.")
        case "rusty-blade":
            atk += 5
            say("🗡️ Rusty Blade found. Attack +5. Now \(atk).", 0xa0e0ff, "Found a Rusty Blade. Attack increased by 5. Now \(atk).")
        case "sharp-edge":
            atk += 8
            say("⚔️ Sharp Edge found. Attack +8. Now \(atk).", 0xa0e0ff, "Found a Sharp Edge. Attack increased by 8. Now \(atk).")
        case "void-blade":
            atk += 15
            say("🌑 Void Blade found! Attack +15. Now \(atk).", 0x8888ff, "Found a Void Blade. Attack increased by 15. Now \(atk).")
        case "iron-fragment":
            def += 3
            say("🛡️ Iron Fragment found. Defense +3. Now \(def).", 0xa0e0ff, "Found an Iron Fragment. Defense increased by 3.")
        case "heavy-stone":
            def += 5
            atk = max(1, atk - 2)
            say("🪨 Heavy Stone. Defense +5, Attack -2.", 0xa0e0ff, "Found a Heavy Stone. Defense plus 5, Attack minus 2.")
        case "void-armor":
            def += 10
            say("⚫ Void Plate found! Defense +10. Now \(def).", 0x8888ff, "Found Void Plate. Defense increased by 10.")
        case "blood-vial":
            hp = min(maxHp, hp + 30)
            say("🩸 Blood Vial. Healed 30 HP. HP: \(hp)/\(maxHp).", 0xff8888, "Found a Blood Vial. Healed 30 HP.")
        case "herb-bundle":
            hp = min(maxHp, hp + 20)
            def += 2
            say("🌿 Herb Bundle. +20 HP, +2 defense.", 0x44ff88, "Found an Herb Bundle. Healed 20 HP and defense plus 2.")
        case "descent-gem":
            points += 20
            say("💎 Descent Gem! +20 descent points.", 0xffdd44, "Found a Descent Gem. Plus 20 descent points.")
        case "battle-scroll":
            battleScrollActive = true
            say("📜 Battle Scroll! Next fight deals double damage.", 0xffaa44, "Found a Battle Scroll. Your next fight deals double damage.")
        case "void-shard":
            xpBoostFights = 5
            xpBoostMult = 1.5
            say("🔮 Void Shard! +50% XP for next 5 fights.", 0x8888ff, "Found a Void Shard. Plus 50 percent XP for your next 5 fights.")
        default:
            atk += 10
            def += 5
            say("✨ ELIXIR OF POWER! Attack +10, Defense +5.", 0xffdd44, "Found an Elixir of Power. Attack plus 10, Defense plus 5.")
        }
    }

    // MARK: Player actions

    /// afkUsePotion: 40% of max HP.
    public mutating func usePotion() -> String {
        guard running else { return "" }
        guard potions > 0 else { return "No potions remaining." }
        let heal = jsRound(Double(maxHp) * 0.40)
        hp = min(maxHp, hp + heal)
        potions -= 1
        add("🧪 Potion used. Restored \(heal) HP. \(potions) remaining.", 0x44ff88)
        return "Potion used. HP: \(hp). Potions remaining: \(potions)."
    }

    /// The fights owed after `seconds` without one (time away from the app).
    public func fightsDue(at now: Double) -> Int {
        guard running else { return 0 }
        return max(0, Int((now - lastFightAt) / fightSeconds))
    }
}

/// "dd_afk": total Descent Points, best floor, shop upgrades and the daily
/// challenge record.
public struct AFKSave: Sendable {
    public var raw: [String: JSONValue]

    public static func load(_ store: GameStore) -> AFKSave {
        guard let s = store.getItem("dd_afk"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) else { return AFKSave(raw: [:]) }
        return AFKSave(raw: v)
    }

    public func save(_ store: GameStore) {
        if let d = try? JSONEncoder().encode(raw), let s = String(data: d, encoding: .utf8) { store.setItem("dd_afk", s) }
    }

    private func int(_ k: String) -> Int { if case .number(let n)? = raw[k] { return Int(n) }; return 0 }

    public var totalPoints: Int {
        get { int("totalPoints") }
        set { raw["totalPoints"] = .number(Double(newValue)) }
    }

    public var bestFloor: Int {
        get { int("bestFloor") }
        set { raw["bestFloor"] = .number(Double(newValue)) }
    }

    public var upgrades: [String: Int] {
        get {
            guard case .object(let o)? = raw["upgrades"] else { return [:] }
            return o.compactMapValues { if case .number(let n) = $0 { return Int(n) }; return nil }
        }
        set { raw["upgrades"] = .object(newValue.mapValues { .number(Double($0)) }) }
    }

    // MARK: Daily challenge

    public struct Challenge: Sendable {
        public let id, desc, type: String
        public let target, bonus: Int
    }

    /// AFK_DAILY_CHALLENGES
    public static let challenges: [Challenge] = [
        Challenge(id: "reach-floor-20", desc: "Reach floor 20.", type: "floor", target: 20, bonus: 50),
        Challenge(id: "reach-floor-50", desc: "Reach floor 50.", type: "floor", target: 50, bonus: 100),
        Challenge(id: "reach-floor-100", desc: "Reach floor 100.", type: "floor", target: 100, bonus: 200),
        Challenge(id: "reach-level-3", desc: "Reach level 3 in one run.", type: "level", target: 3, bonus: 75),
        Challenge(id: "reach-level-5", desc: "Reach level 5 in one run.", type: "level", target: 5, bonus: 150),
        Challenge(id: "defeat-boss", desc: "Defeat a boss floor.", type: "boss", target: 1, bonus: 80),
        Challenge(id: "defeat-3-bosses", desc: "Defeat 3 boss floors.", type: "boss", target: 3, bonus: 200),
        Challenge(id: "earn-100-pts", desc: "Earn 100 descent points.", type: "points", target: 100, bonus: 60),
        Challenge(id: "earn-500-pts", desc: "Earn 500 descent points.", type: "points", target: 500, bonus: 150),
    ]

    /// getTodayAFKChallenge: date + month × 7 (months counted from 0).
    public static func todaysChallenge(_ date: Date = Date()) -> Challenge {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return challenges[((c.day ?? 1) + ((c.month ?? 1) - 1) * 7) % challenges.count]
    }

    private static func key(_ date: Date) -> String {
        "challenge_\(RaidSave.todayKey(date))_\(todaysChallenge(date).id)"
    }

    public func challengeDone(_ date: Date = Date()) -> Bool {
        raw[Self.key(date)] == .bool(true)
    }

    /// afkCheckDailyChallenge: returns the log line when it completes now.
    public mutating func checkChallenge(_ run: inout AFKRun, date: Date = Date()) -> String? {
        guard !challengeDone(date) else { return nil }
        let c = Self.todaysChallenge(date)
        let value = c.type == "floor" ? run.floor : c.type == "level" ? run.level
            : c.type == "points" ? run.points : run.bossesDefeated
        guard value >= c.target else { return nil }
        raw[Self.key(date)] = .bool(true)
        totalPoints += c.bonus
        run.add("🎯 DAILY CHALLENGE COMPLETE! \(c.desc) +\(c.bonus) bonus pts!", 0xffdd44)
        return "Daily challenge complete! \(c.desc) Plus \(c.bonus) bonus descent points!"
    }

    /// addDescentPoints at the end of a run.
    public mutating func finish(_ run: AFKRun) {
        totalPoints += run.points
        bestFloor = max(bestFloor, run.floor)
    }

    /// buyAFKUpgrade. Returns the spoken result and whether it went through.
    public mutating func buy(_ item: AFKRun.ShopItem, store: GameStore) -> (String, Bool) {
        guard totalPoints >= item.cost else { return ("Not enough descent points.", false) }
        let owned = upgrades[item.id] ?? 0
        guard owned < item.max else { return ("Already maxed.", false) }
        totalPoints -= item.cost
        if item.id == "afk-mystery-coins" {
            return ("Purchased. 2 Mystery Coins added. \(totalPoints) descent points remaining.", true)
        }
        var u = upgrades
        u[item.id] = owned + 1
        upgrades = u
        if item.id == "afk-title-void" || item.id == "afk-title-fallen" {
            let title = item.id == "afk-title-void" ? "TheEndless" : "TheFallen"
            var titles: [String] = []
            if let s = store.getItem("dd_unlocked_titles"), let d = s.data(using: .utf8),
               let v = try? JSONDecoder().decode([String].self, from: d) { titles = v }
            if !titles.contains(title) { titles.append(title) }
            if let d = try? JSONEncoder().encode(titles), let s = String(data: d, encoding: .utf8) {
                store.setItem("dd_unlocked_titles", s)
            }
            return ("Title unlocked: \(title). Set it in Account settings.", true)
        }
        return ("Purchased \(item.name). \(totalPoints) descent points remaining.", true)
    }
}
