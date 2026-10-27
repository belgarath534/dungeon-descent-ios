import Foundation

/// Something dug up or dropped in the Mine (MINE_LOOT_TABLES).
public struct MineItem: Codable, Equatable, Sendable {
    public var name: String
    public var icon: String
    /// mine-gold, mine-coin, mine-diamond, mine-potion, mine-ingredient, gun-part
    public var type: String
    public var value = 0
    public var heal = 0
    public var partId: String? = nil
    var weight = 1

    init(_ name: String, _ icon: String, _ type: String, value: Int = 0, heal: Int = 0, part: String? = nil, weight: Int) {
        self.name = name; self.icon = icon; self.type = type
        self.value = value; self.heal = heal; partId = part; self.weight = weight
    }
}

/// A Mine enemy (MINE_ENEMIES) with its special move.
public struct MineFoe: Codable, Equatable, Sendable {
    public var name: String
    public var icon: String
    public var hp: Int
    public var maxHp: Int
    public var atk: ClosedRange<Int>
    public var gold: Int
    public var isBoss = false
    public var isElite = false
    public var milestone: Int? = nil
    public var lore: String? = nil
    // Special moves.
    var dodgeEvery = 0
    var poisonChance = 0.0
    var immuneFirstHit = false
    var drainsSkills = false
    var grows = false
    var lifesteal = false
    var burn = 0
    var burnTurns = 0
    var physResist = 0.0
    var depth: ClosedRange<Int> = 1...99
    // In the fight.
    public var turns = 0
    public var hitsTaken = 0
    public var weakened = false

    init(_ name: String, _ icon: String, hp: Int, atk: ClosedRange<Int>, gold: Int, depth: ClosedRange<Int>) {
        self.name = name; self.icon = icon; self.hp = hp; maxHp = hp; self.atk = atk; self.gold = gold; self.depth = depth
    }

    func with(_ f: (inout MineFoe) -> Void) -> MineFoe { var c = self; f(&c); return c }

    /// What its special move is, for the screen.
    public var special: String? {
        if dodgeEvery > 0 { return "Slips aside every \(dodgeEvery)rd strike." }
        if poisonChance > 0 { return "Its bite can poison." }
        if immuneFirstHit { return physResist > 0 ? "Shrugs off your first hit, and resists 20% of every blow." : "Shrugs off your first hit." }
        if drainsSkills { return "Drains your focus — no skills the turn after it hits." }
        if grows { return "Grows stronger every turn." }
        if lifesteal { return "Heals from the blood it draws." }
        if burn > 0 { return "Its strikes set you burning." }
        return nil
    }
}

/// One trip into the Mine (_mineState).
public struct MineRun: Codable, Equatable, Sendable {
    public var name: String
    public var cls: String
    public var level: Int
    public var skills: [String]
    public var depth = 1
    public var hand: [MineItem] = []
    public var chest: [MineItem] = []
    public var hasChest = false
    public var hp: Int
    public var maxHp: Int
    public var enemy: MineFoe? = nil
    public var digs = 0
    public var atmosphere = Mine.atmospheres[0]
    var defending = false
    var heavyPenalty = false
    var buffed = false
    var shielded = false
    var poisonTurns = 0
    var burn = 0
    var burnTurns = 0
    var skillsDrained = 0

    public var inCombat: Bool { enemy != nil }
    public var handsFull: Bool { hand.count >= Mine.maxCarry }
}

/// THE MINE: dig for gold, diamonds, Mystery Coins, potions and gun parts,
/// go deeper for better loot and harder enemies, and surface to keep it all.
/// Whatever is in your hands is lost if you fall; the chest (from depth 3)
/// keeps things safe.
public enum Mine {
    public static let maxCarry = 15

    static func i(_ n: String, _ icon: String, _ t: String, v: Int = 0, heal: Int = 0, part: String? = nil, w: Int) -> MineItem {
        MineItem(n, icon, t, value: v, heal: heal, part: part, weight: w)
    }

    static let tables: [(ClosedRange<Int>, [MineItem])] = [
        (1...2, [
            i("Gold Nugget", "🪨", "mine-gold", v: 15, w: 30), i("Gun Barrel", "🔩", "gun-part", part: "barrel", w: 20),
            i("Gun Stock", "🪵", "gun-part", part: "stock", w: 20), i("Mystery Coin", "🪙", "mine-coin", v: 1, w: 25),
            i("Iron Chunk", "🪨", "mine-gold", v: 8, w: 30), i("Trigger Assembly", "🔧", "gun-part", part: "trigger", w: 15),
            i("Health Potion", "🧪", "mine-potion", heal: 40, w: 15),
        ]),
        (3...4, [
            i("Gold Vein", "✨", "mine-gold", v: 35, w: 25), i("Firing Mechanism", "⚙️", "gun-part", part: "mechanism", w: 20),
            i("Mystery Coins ×2", "🪙", "mine-coin", v: 2, w: 20), i("Diamond Shard", "💎", "mine-diamond", v: 1, w: 15),
            i("Gun Barrel", "🔩", "gun-part", part: "barrel", w: 20), i("Potion Ingredient", "🌿", "mine-ingredient", w: 15),
            i("Health Potion", "🧪", "mine-potion", heal: 40, w: 18), i("Strong Potion", "🧪", "mine-potion", heal: 70, w: 8),
        ]),
        (5...99, [
            i("Diamond", "💎", "mine-diamond", v: 2, w: 20), i("Large Gold Vein", "🏆", "mine-gold", v: 80, w: 20),
            i("Diamonds ×3", "💎", "mine-diamond", v: 3, w: 10), i("Mystery Coins ×5", "🪙", "mine-coin", v: 5, w: 15),
            i("Rare Gun Part", "⚙️", "gun-part", part: "mechanism", w: 15), i("Firing Mechanism", "⚙️", "gun-part", part: "mechanism", w: 15),
            i("Alchemy Herb", "🌿", "mine-ingredient", w: 10), i("Treasure Cache", "📦", "mine-gold", v: 120, w: 5),
            i("Health Potion", "🧪", "mine-potion", heal: 40, w: 12), i("Strong Potion", "🧪", "mine-potion", heal: 70, w: 10),
            i("Mega Potion", "🧪", "mine-potion", heal: 120, w: 4),
        ]),
    ]

    static let healthPotion = i("Health Potion", "🧪", "mine-potion", heal: 40, w: 1)

    static func f(_ n: String, _ icon: String, _ hp: Int, _ atk: ClosedRange<Int>, _ gold: Int, _ d: ClosedRange<Int>) -> MineFoe {
        MineFoe(n, icon, hp: hp, atk: atk, gold: gold, depth: d)
    }

    public static let enemies: [MineFoe] = [
        f("Cave Rat", "🐀", 18, 2...5, 8, 1...2),
        f("Rock Beetle", "🪲", 22, 3...6, 10, 1...2),
        f("Mine Bat", "🦇", 15, 4...7, 7, 1...3),
        f("Dust Shade", "🌫️", 14, 3...6, 6, 1...3).with { $0.dodgeEvery = 3 },
        f("Tunnel Snake", "🐍", 20, 3...7, 9, 1...3).with { $0.poisonChance = 0.20 },
        f("Pickaxe Ghost", "⛏️", 16, 3...6, 7, 1...3),
        f("Cave Troll", "👹", 45, 6...12, 20, 2...4),
        f("Stone Golem", "🗿", 60, 8...14, 25, 3...5).with { $0.immuneFirstHit = true },
        f("Mine Wraith", "👻", 35, 10...16, 18, 3...5),
        f("Iron Sprite", "✨", 28, 5...10, 12, 2...4).with { $0.drainsSkills = true },
        f("The Collapsed", "🪨", 40, 7...12, 15, 2...4),
        f("Crystal Wolf", "🐺", 38, 8...13, 16, 3...5).with { $0.grows = true },
        f("Shaft Lurker", "🌑", 32, 7...13, 14, 3...5).with { $0.dodgeEvery = 3 },
        f("Vein Horror", "🩸", 42, 8...14, 18, 4...6).with { $0.lifesteal = true },
        f("Deep Crawler", "🕷️", 80, 12...20, 35, 5...99),
        f("Ore Demon", "😈", 100, 15...25, 50, 5...99).with { $0.burn = 3; $0.burnTurns = 2 },
        f("Diamond Golem", "💎", 90, 13...22, 45, 5...99).with { $0.immuneFirstHit = true; $0.physResist = 0.20 },
        f("Mine Boss", "💀", 150, 18...30, 100, 5...99).with { $0.isBoss = true },
        f("Forgotten Foreman", "👷", 120, 16...26, 80, 4...99).with { $0.isElite = true; $0.grows = true },
    ]

    public static let milestones: [MineFoe] = [
        f("The Foreman's Ghost", "👻", 180, 14...22, 150, 10...10).with { $0.isBoss = true; $0.milestone = 10; $0.lore = "He ran this mine for forty years. He never left." },
        f("The Cave King", "👑", 280, 20...32, 250, 20...20).with { $0.isBoss = true; $0.milestone = 20; $0.lore = "Something claimed the deepest tunnels as its kingdom long before you arrived." },
        f("The Deep Hunger", "🕳️", 420, 28...44, 400, 30...30).with { $0.isBoss = true; $0.milestone = 30; $0.lore = "It has been waiting in the dark since before the mine existed. It is very hungry." },
        f("The Vein Titan", "⛰️", 600, 36...55, 600, 50...50).with { $0.isBoss = true; $0.milestone = 50; $0.lore = "The mountain itself has decided you have gone far enough." },
        f("The Mine's Heart", "❤️", 900, 48...72, 1000, 100...100).with { $0.isBoss = true; $0.milestone = 100; $0.lore = "You found it. The thing at the center of everything. It does not want to be found." },
    ]

    public static let atmospheres = [
        "The tunnels stretch before you. Pickaxe rings echo off stone.",
        "A cold draft carries the smell of earth and iron.",
        "Faint glimmers in the rock face catch your eye.",
        "Water drips somewhere deep below.",
        "The walls narrow. Something skitters in the dark.",
        "Veins of ore shimmer faintly in your torchlight.",
        "The deeper tunnels breathe with an ancient stillness.",
        "Your boots crunch on broken stone. Wealth awaits the patient.",
    ]

    static let empties = ["Nothing but rock.", "Solid stone. Keep digging.", "Your pick sparks against hard ore.", "Empty. Try again."]

    // MARK: Starting

    /// mineStart: class HP, 4% more per level.
    public static func start(_ ch: PlayerCharacter) -> MineRun {
        let lvl = max(1, ch.persistLevel ?? 1)
        let hp = Int((Double(GameData.classInfo(ch.cls).maxHp) * (1 + Double(lvl - 1) * 0.04)).rounded(.down))
        var skills: [String] = []
        for key in ["persistSkills", "unlockedSkills"] where skills.isEmpty {
            if case .array(let a)? = ch.extra[key] { skills = a.compactMap { if case .string(let s) = $0 { return s }; return nil } }
        }
        return MineRun(name: ch.name, cls: ch.cls, level: lvl, skills: skills, hp: hp, maxHp: hp)
    }

    /// getMineSkills: up to six of the character's learned skills.
    public static func skills(_ m: MineRun) -> [Skill] {
        Skills.all(for: m.cls).filter { m.skills.contains($0.effect) }.prefix(6).map { $0 }
    }

    static func table(_ depth: Int) -> [MineItem] {
        (tables.last { $0.0.contains(depth) } ?? tables[tables.count - 1]).1
    }

    static func pick(_ items: [MineItem], dice: inout some Dice) -> MineItem {
        let total = items.reduce(0) { $0 + $1.weight }
        var r = dice.roll(1...max(1, total))
        for it in items {
            r -= it.weight
            if r <= 0 { return it }
        }
        return items[items.count - 1]
    }

    // MARK: Digging

    public enum Dig: Equatable, Sendable {
        case handsFull
        case enemy(MineFoe)
        case empty(String)
        case found([MineItem])
    }

    /// mineDig: an enemy (8% plus 3% a depth), an empty swing (15%), or one
    /// or two finds.
    public static func dig(_ m: inout MineRun, dice: inout some Dice) -> Dig {
        guard !m.inCombat else { return .empty("Finish the fight first!") }
        guard !m.handsFull else { return .handsFull }
        m.digs += 1
        if m.digs % 5 == 0 { m.atmosphere = atmospheres[dice.roll(0...(atmospheres.count - 1))] }
        if dice.chance(0.08 + Double(m.depth) * 0.03) {
            let pool = enemies.filter { $0.depth.contains(m.depth) }
            if !pool.isEmpty {
                let e = pool[dice.roll(0...(pool.count - 1))]
                m.enemy = e
                return .enemy(e)
            }
        }
        if dice.chance(0.15) { return .empty(empties[dice.roll(0...(empties.count - 1))]) }
        var found: [MineItem] = []
        for _ in 0..<(dice.chance(0.3) ? 2 : 1) where !m.handsFull {
            let it = pick(table(m.depth), dice: &dice)
            collect(&m, it)
            found.append(it)
        }
        return .found(found)
    }

    @discardableResult
    static func collect(_ m: inout MineRun, _ it: MineItem) -> Bool {
        guard !m.handsFull else { return false }
        m.hand.append(it)
        if m.depth >= 3 { m.hasChest = true }
        return true
    }

    /// mineDescend: 10 HP back, and a milestone boss at depths 10, 20, 30, 50 and 100.
    public static func descend(_ m: inout MineRun) -> MineFoe? {
        guard !m.inCombat else { return nil }
        m.depth += 1
        m.digs = 0
        m.hp = min(m.maxHp, m.hp + 10)
        m.atmosphere = "Depth \(m.depth). The air is colder. The darkness is thicker."
        if let boss = milestones.first(where: { $0.milestone == m.depth }) {
            m.enemy = boss
            return boss
        }
        return nil
    }

    /// mineOpenChest: everything in your hands goes into the chest.
    public static func stash(_ m: inout MineRun) -> Int {
        guard m.hasChest else { return 0 }
        let n = m.hand.count
        m.chest += m.hand
        m.hand = []
        return n
    }

    // MARK: Fighting

    public enum Action: String, Sendable { case attack, heavy, defend, potion, flee }

    public struct Turn: Equatable, Sendable {
        public var log: [String] = []
        public var enemyDied = false
        public var gold = 0
        public var loot: [MineItem] = []
        public var playerDied = false
        public var fled = false
        public var acted = true
        public var defeated: MineFoe? = nil
    }

    /// Your attack: the class's range, 5% more per level (mineCombatAction).
    static func roll(_ m: MineRun, dice: inout some Dice) -> Int {
        let a = GameData.classInfo(m.cls).atk
        return Int((Double(dice.roll(a)) * (1 + Double(m.level - 1) * 0.05)).rounded(.down))
    }

    /// Damage landing on the enemy, through its defenses.
    static func hit(_ m: inout MineRun, _ dmg: Int, log: inout [String]) -> Int {
        guard var e = m.enemy else { return 0 }
        e.hitsTaken += 1
        if e.immuneFirstHit && e.hitsTaken == 1 {
            m.enemy = e
            log.append("🗿 \(e.name) shrugs off your first blow!")
            return 0
        }
        if e.dodgeEvery > 0 && e.hitsTaken % e.dodgeEvery == 0 {
            m.enemy = e
            log.append("🌫️ \(e.name) slips aside — you hit nothing!")
            return 0
        }
        var d = dmg
        if e.physResist > 0 { d = Int((Double(d) * (1 - e.physResist)).rounded(.down)) }
        e.hp = max(0, e.hp - d)
        m.enemy = e
        return d
    }

    public static func act(_ m: inout MineRun, _ action: Action, dice: inout some Dice) -> Turn {
        var t = Turn()
        guard let e = m.enemy else { t.acted = false; return t }
        let base = roll(m, dice: &dice)
        switch action {
        case .attack:
            var dmg = base
            if m.buffed { dmg *= 2; m.buffed = false }
            let d = hit(&m, dmg, log: &t.log)
            if d > 0 { t.log.append("⚔ You hit \(e.name) for \(d) damage!") }
        case .heavy:
            let d = hit(&m, Int((Double(base) * 1.8).rounded(.down)), log: &t.log)
            if d > 0 { t.log.append("💥 HEAVY STRIKE! You slam \(e.name) for \(d) damage!") }
            m.heavyPenalty = true
        case .defend:
            m.defending = true
            t.log.append("🛡 You brace for impact! Defense up this turn.")
        case .potion:
            guard let i = m.hand.firstIndex(where: { $0.type == "mine-potion" }) else {
                t.acted = false
                t.log.append("🧪 No potions in hand!")
                return t
            }
            let pot = m.hand.remove(at: i)
            let heal = pot.heal > 0 ? pot.heal : 40
            m.hp = min(m.maxHp, m.hp + heal)
            t.log.append("🧪 You drink a potion and recover \(heal) HP! HP: \(m.hp) of \(m.maxHp).")
        case .flee:
            if dice.chance(0.6) {
                m.enemy = nil
                m.defending = false; m.heavyPenalty = false
                t.fled = true
                t.log.append("🏃 You fled from \(e.name)!")
                return t
            }
            t.log.append("❌ Flee failed! \(e.name) blocks you.")
        }
        return afterAction(&m, t, dice: &dice)
    }

    /// mineUseSkill: heals, shields, weakens, boosts or strikes by tier.
    public static func useSkill(_ m: inout MineRun, _ effect: String, dice: inout some Dice) -> Turn {
        var t = Turn()
        guard var e = m.enemy, let sk = skills(m).first(where: { $0.effect == effect }) else { t.acted = false; return t }
        if m.skillsDrained > 0 {
            t.acted = false
            t.log.append("✨ The Iron Sprite drained your focus. No skills this turn.")
            return t
        }
        switch effect {
        case "heal", "second-wind", "divine-shield", "iron-will", "fortify", "inner-focus":
            let h = Int((Double(m.maxHp) * 0.35).rounded(.down))
            m.hp = min(m.maxHp, m.hp + h)
            t.log.append("\(sk.icon) \(sk.name)! Restored \(h) HP.")
        case "shield", "bone-shield":
            m.shielded = true
            t.log.append("\(sk.icon) \(sk.name)! Next hit reduced by 80%.")
        case "smoke-bomb", "venom", "curse":
            e.weakened = true
            m.enemy = e
            t.log.append("\(sk.icon) \(sk.name)! \(e.name) is weakened — its attacks are reduced.")
        case "buff", "battlecry", "war-cry", "battle-hymn", "focus", "unlimited-power":
            m.buffed = true
            t.log.append("\(sk.icon) \(sk.name)! Your next attack hits twice as hard!")
            // A boost costs no turn.
            return t
        default:
            let a = GameData.classInfo(m.cls).atk
            let base = Double(a.lowerBound + a.upperBound) / 2 * (1 + Double(m.level - 1) * 0.05)
            let mult = sk.tier == "legendary" ? 3.0 : sk.tier == "rare" ? 2.2 : 1.6
            let d = hit(&m, Int((base * mult).rounded(.down)), log: &t.log)
            if d > 0 { t.log.append("\(sk.icon) \(sk.name)! \(d) damage!") }
        }
        return afterAction(&m, t, dice: &dice)
    }

    /// A kill pays its gold and maybe loot; otherwise the enemy strikes back.
    static func afterAction(_ m: inout MineRun, _ turn: Turn, dice: inout some Dice) -> Turn {
        var t = turn
        guard var e = m.enemy else { return t }
        if e.hp <= 0 {
            t.enemyDied = true
            t.defeated = e
            t.gold = e.gold
            t.log.append("💀 \(e.name) defeated! +\(e.gold) gold.")
            m.enemy = nil
            m.defending = false; m.heavyPenalty = false; m.buffed = false; m.shielded = false
            if e.milestone != nil {
                t.loot = [i("Mega Potion", "🧪", "mine-potion", heal: 120, w: 1), i("Diamonds ×3", "💎", "mine-diamond", v: 3, w: 1)]
                t.log.append("👑 Milestone boss defeated! Special loot dropped.")
            } else if dice.chance(0.5) {
                t.loot = [dice.chance(0.25) ? healthPotion : pick(table(m.depth), dice: &dice)]
            }
            for it in t.loot where collect(&m, it) { t.log.append("\(it.icon) Found: \(it.name)!") }
            return t
        }
        // The enemy's turn.
        e.turns += 1
        if m.skillsDrained > 0 { m.skillsDrained -= 1 }
        if m.poisonTurns > 0 {
            m.poisonTurns -= 1
            m.hp = max(0, m.hp - 3)
            t.log.append("🐍 Poison burns in your veins — 3 damage.")
        }
        if m.burnTurns > 0 {
            m.burnTurns -= 1
            m.hp = max(0, m.hp - m.burn)
            t.log.append("🔥 You burn for \(m.burn) damage.")
        }
        if e.grows && e.turns > 1 {
            e.atk = (e.atk.lowerBound + 1)...(e.atk.upperBound + 2)
            t.log.append("📈 \(e.name) grows stronger.")
        }
        var dmg = dice.roll(e.atk)
        if m.heavyPenalty { dmg = Int((Double(dmg) * 1.3).rounded(.down)); m.heavyPenalty = false }
        if m.defending { dmg = Int((Double(dmg) * 0.4).rounded(.down)); m.defending = false }
        if e.weakened { dmg = Int((Double(dmg) * 0.6).rounded(.down)); e.weakened = false }
        if m.shielded { dmg = Int((Double(dmg) * 0.2).rounded(.down)); m.shielded = false }
        if m.hp > 0 {
            m.hp = max(0, m.hp - dmg)
            t.log.append("💥 \(e.name) hits you for \(dmg)! HP: \(m.hp) of \(m.maxHp).")
            if dmg > 0 {
                if e.poisonChance > 0 && dice.chance(e.poisonChance) {
                    m.poisonTurns = 3
                    t.log.append("🐍 You've been poisoned! 3 damage a turn for 3 turns.")
                }
                if e.burn > 0 {
                    m.burn = e.burn
                    m.burnTurns = e.burnTurns
                    t.log.append("🔥 You catch fire!")
                }
                if e.lifesteal {
                    let h = dmg / 2
                    e.hp = min(e.maxHp, e.hp + h)
                    t.log.append("🩸 \(e.name) drinks \(h) HP from you.")
                }
                if e.drainsSkills {
                    m.skillsDrained = 1
                    t.log.append("✨ \(e.name) drains your focus — no skills next turn.")
                }
            }
        }
        m.enemy = e
        if m.hp <= 0 {
            t.playerDied = true
            m.hand = []
            m.enemy = nil
            t.log.append("💀 You were defeated. Surfacing... Everything in your hands is lost.")
        }
        return t
    }

    // MARK: Surfacing

    public struct Haul: Equatable, Sendable {
        public var gold = 0
        public var diamonds = 0
        public var coins = 0
        public var potions: [Item] = []
        public var parts: [String: Int] = [:]
        public var herbs = 0
        public var depth = 1
        public var defeated = false
        public var isEmpty: Bool { gold == 0 && diamonds == 0 && coins == 0 && potions.isEmpty && parts.isEmpty && herbs == 0 }
    }

    public static let partNames = ["barrel": "Gun Barrel", "mechanism": "Firing Mechanism", "stock": "Gun Stock", "trigger": "Trigger Assembly"]

    /// mineSurface: everything in hand and chest. (On a defeat the hand is
    /// already gone.)
    public static func surface(_ m: MineRun, defeated: Bool) -> Haul {
        var h = Haul(depth: m.depth, defeated: defeated)
        for it in m.hand + m.chest {
            switch it.type {
            case "mine-gold": h.gold += it.value
            case "mine-diamond": h.diamonds += it.value
            case "mine-coin": h.coins += it.value
            case "mine-potion":
                var p = Item(name: it.name, icon: it.icon, type: "potion", desc: "Restores \(it.heal) HP. Found in the Mine.", heal: it.heal)
                p.extra["fromMine"] = .bool(true)
                h.potions.append(p)
            case "gun-part": h.parts[it.partId ?? "barrel", default: 0] += 1
            case "mine-ingredient": h.herbs += 1
            default: break
            }
        }
        return h
    }

    /// The haul into your saves: gold, diamonds, coins through the callers;
    /// gun parts (dd_gun_parts) and herbs (dd_alchemy_ingredients) here, in
    /// the web version's keys, ready for the Gun Workshop and Alchemy.
    public static func storeParts(_ h: Haul, store: GameStore) {
        func object(_ key: String) -> [String: Int] {
            guard let s = store.getItem(key), let d = s.data(using: .utf8),
                  let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) else { return [:] }
            return v.compactMapValues { if case .number(let n) = $0 { return Int(n) }; return nil }
        }
        func save(_ key: String, _ v: [String: Int]) {
            if let d = try? JSONEncoder().encode(v), let s = String(data: d, encoding: .utf8) { store.setItem(key, s) }
        }
        if !h.parts.isEmpty {
            var parts = object("dd_gun_parts")
            for (k, n) in h.parts { parts[k, default: 0] += n }
            save("dd_gun_parts", parts)
        }
        if h.herbs > 0 {
            var ing = object("dd_alchemy_ingredients")
            ing["herb", default: 0] += h.herbs
            save("dd_alchemy_ingredients", ing)
        }
    }
}
