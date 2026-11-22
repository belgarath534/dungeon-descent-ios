import Foundation

/// THE SPIRE: 1800 floors with The Time Eater at the top. Your best floor is
/// saved ("dd_spire"), and every climb starts there.
public struct SpireRun: Codable, Sendable {
    public struct Foe: Codable, Sendable, Equatable {
        public var name: String
        public var icon: String
        public var hp: Int
        public var maxHp: Int
        public var atk: ClosedRange<Int>
        public var isBoss: Bool
    }

    public var floor: Int
    public var hp: Int
    public var maxHp: Int
    public var atk: Int
    public var def: Int
    public var potions: Int
    public var gold: Int
    public var charName: String
    public var cls: String
    public var enemy: Foe? = nil
    /// The floor's fight is over (or it's a rest floor): Next Floor is up.
    public var cleared = false
    public var won = false
    public var dead = false
}

public enum Spire {
    public static let top = 1800

    struct T { let name, icon: String; let hp: Int; let atk: ClosedRange<Int> }
    struct Boss { let name, icon: String; let hp: Int; let atk: ClosedRange<Int>; let floor: Int; let msg: String }

    /// SPIRE_ENEMIES (their special flags were never used by the web version's Spire fight).
    static let tiers: [[T]] = [
        [T(name: "Spire Rat", icon: "🐀", hp: 30, atk: 4...8), T(name: "Crumbling Golem", icon: "🪨", hp: 45, atk: 5...10),
         T(name: "Hollow Shade", icon: "👤", hp: 35, atk: 6...11), T(name: "Spire Bat", icon: "🦇", hp: 25, atk: 5...9),
         T(name: "Echo Crawler", icon: "🔊", hp: 28, atk: 5...9), T(name: "Spire Ember", icon: "🔥", hp: 30, atk: 5...9),
         T(name: "Cracked Husk", icon: "💀", hp: 40, atk: 3...6), T(name: "Spire Wisp", icon: "🔵", hp: 20, atk: 4...8)],
        [T(name: "Stone Sentinel", icon: "🗿", hp: 70, atk: 10...16), T(name: "Ash Wraith", icon: "💨", hp: 60, atk: 12...18),
         T(name: "Spire Knight", icon: "⚔️", hp: 80, atk: 11...17), T(name: "Void Tendril", icon: "🌑", hp: 65, atk: 13...19),
         T(name: "Mirror Stalker", icon: "🪞", hp: 55, atk: 11...17), T(name: "Spire Soul Eater", icon: "😈", hp: 58, atk: 10...16),
         T(name: "Spire Phantom", icon: "🌫️", hp: 50, atk: 11...18), T(name: "Tower Stalker", icon: "👁️", hp: 52, atk: 10...16),
         T(name: "Spire Drainer", icon: "⬛", hp: 55, atk: 9...14)],
        [T(name: "Crimson Warden", icon: "🔴", hp: 120, atk: 16...24), T(name: "Time Phantom", icon: "⏳", hp: 110, atk: 18...26),
         T(name: "Spire Colossus", icon: "🏛️", hp: 140, atk: 15...22), T(name: "Rift Stalker", icon: "🌀", hp: 100, atk: 20...28),
         T(name: "Spire Champion", icon: "⚔️", hp: 115, atk: 17...25), T(name: "The Ascending", icon: "🧗", hp: 105, atk: 16...24),
         T(name: "Spire Brute", icon: "👹", hp: 130, atk: 20...30), T(name: "Fracture Shade", icon: "🌑", hp: 108, atk: 16...23)],
        [T(name: "Eternal Husk", icon: "💀", hp: 200, atk: 22...32), T(name: "Voidborn", icon: "🌌", hp: 180, atk: 25...35),
         T(name: "Spire Titan", icon: "🗼", hp: 220, atk: 20...30), T(name: "Consumed Soul", icon: "😶", hp: 190, atk: 24...34)],
        [T(name: "Time Devourer", icon: "⌛", hp: 300, atk: 30...42), T(name: "The Forgotten", icon: "🫥", hp: 280, atk: 32...44),
         T(name: "Apex Construct", icon: "🤖", hp: 320, atk: 28...40), T(name: "Void Ancient", icon: "🔮", hp: 290, atk: 34...46)],
    ]

    /// SPIRE_BOSSES
    static let bosses: [Boss] = [
        Boss(name: "The Gate Warden", icon: "🚪", hp: 150, atk: 12...18, floor: 10, msg: "The first door will not open itself."),
        Boss(name: "The Ashen Judge", icon: "⚖️", hp: 280, atk: 18...26, floor: 50, msg: "It has judged every climber before you."),
        Boss(name: "The Iron Sovereign", icon: "👑", hp: 450, atk: 24...34, floor: 100, msg: "A king of stone and silence."),
        Boss(name: "The Rift Weaver", icon: "🌀", hp: 650, atk: 28...38, floor: 200, msg: "It unravels those who come too close."),
        Boss(name: "The Eternal Siege", icon: "⚔️", hp: 900, atk: 32...44, floor: 300, msg: "It has been fighting something for centuries."),
        Boss(name: "The Void Throne", icon: "🌑", hp: 1200, atk: 36...50, floor: 500, msg: "Something sits on it. You cannot quite see what."),
        Boss(name: "The Consumed", icon: "😶", hp: 1600, atk: 40...55, floor: 750, msg: "It used to be someone who climbed like you."),
        Boss(name: "The Last Barrier", icon: "🔒", hp: 2000, atk: 44...60, floor: 1000, msg: "Beyond this, only the top remains."),
        Boss(name: "The Time Eater", icon: "⏳", hp: 3000, atk: 50...70, floor: 1800, msg: "It has been waiting at the top since before the Spire existed."),
    ]

    /// SPIRE_MILESTONES
    static let milestones: [Int: (gold: Int, msg: String)] = [
        100: (50, "Floor 100 reached. The Spire acknowledges your persistence. +50 gold."),
        200: (80, "Floor 200. The air grows thinner. Something watches from above. +80 gold."),
        300: (100, "Floor 300. Halfway to the silence. +100 gold."),
        500: (150, "Floor 500. The Spire shudders. +150 gold."),
        750: (200, "Floor 750. You should not be here. +200 gold."),
        1000: (300, "Floor 1000. The summit is visible now. +300 gold."),
        1500: (400, "Floor 1500. The Time Eater stirs. +400 gold."),
    ]

    static let lore = [
        "The Time Eater has no name it gave itself. The name came from the first climber who reached floor 900 and came back down. No one knows what they saw.",
        "The Spire predates every map of this region. Cartographers draw around it. They do not draw it.",
        "Every 100 years, someone reaches the top. The records stop there. The person does not come back to continue them.",
        "The enemies in the upper floors are not native to the Spire. They wandered in from somewhere else and could not find the way out.",
        "The Time Eater does not sleep. It does not need to. It has been waiting so long that waiting has become the same as existing.",
    ]

    public static let deathLines = [
        "The Spire remembers everyone who fell. It does not mourn them.",
        "You will try again. The Spire has always known this.",
        "The floor you reached is saved. The Spire will be waiting.",
        "Something higher up noticed you before you stopped moving.",
    ]

    // MARK: Saved progress

    public static func bestFloor(_ store: GameStore) -> Int {
        guard let s = store.getItem("dd_spire"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d),
              case .number(let n)? = v["bestFloor"] else { return 1 }
        return max(1, Int(n))
    }

    public static func saveBest(_ floor: Int, store: GameStore) {
        var v: [String: JSONValue] = [:]
        if let s = store.getItem("dd_spire"), let d = s.data(using: .utf8),
           let old = try? JSONDecoder().decode([String: JSONValue].self, from: d) { v = old }
        v["bestFloor"] = .number(Double(max(bestFloor(store), floor)))
        if let d = try? JSONEncoder().encode(v), let s = String(data: d, encoding: .utf8) { store.setItem("dd_spire", s) }
    }

    /// The highest floor whose drops were paid, so leaving and climbing back
    /// onto a rest floor can't farm them.
    static func rewarded(_ store: GameStore) -> Int {
        guard let s = store.getItem("dd_spire"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d),
              case .number(let n)? = v["rewardedFloor"] else { return 0 }
        return Int(n)
    }

    static func setRewarded(_ floor: Int, _ store: GameStore) {
        var v: [String: JSONValue] = [:]
        if let s = store.getItem("dd_spire"), let d = s.data(using: .utf8),
           let old = try? JSONDecoder().decode([String: JSONValue].self, from: d) { v = old }
        v["rewardedFloor"] = .number(Double(floor))
        if let d = try? JSONEncoder().encode(v), let s = String(data: d, encoding: .utf8) { store.setItem("dd_spire", s) }
    }

    // MARK: Starting

    static func num(_ ch: PlayerCharacter, _ k: String) -> Int { if case .number(let n)? = ch.extra[k] { return Int(n) }; return 0 }

    /// startSpire: stats from the character's class and level and the saved gear.
    public static func start(_ ch: PlayerCharacter, store: GameStore, wallet: Wallet) -> SpireRun {
        let floor = bestFloor(store)
        let level = ch.persistLevel ?? 1
        let maxHp = GameData.classInfo(ch.cls).maxHp + (level - 1) * 25 + 150 + floor / 10 * 5
        let stash = GlobalInventory(store: store)
        let wpn = stash.equippedWeapon.map { ($0.weaponAttack.lowerBound + $0.weaponAttack.upperBound) / 2 } ?? 0
        let arm = stash.equippedArmor?.armorDefense ?? 0
        return SpireRun(floor: floor, hp: maxHp, maxHp: maxHp, atk: 20 + num(ch, "atkBonus") + (level - 1) * 2 + wpn,
                        def: num(ch, "defBonus") + arm, potions: 3 + floor / 100, gold: wallet.gold,
                        charName: ch.name, cls: ch.cls)
    }

    /// After the Blacksmith: gear bought or upgraded there counts right away
    /// (the web version only picked it up on the next climb).
    public static func refreshGear(_ run: inout SpireRun, _ ch: PlayerCharacter, store: GameStore, wallet: Wallet) {
        let fresh = start(ch, store: store, wallet: wallet)
        run.atk = fresh.atk
        run.def = fresh.def
        run.gold = wallet.gold
    }

    // MARK: Floors

    public static func boss(on floor: Int) -> Bool { bosses.contains { $0.floor == floor } }

    /// A rest floor: every 10th floor that isn't a boss floor. (In the web
    /// version rest floors came first, so no boss but The Time Eater ever
    /// appeared.)
    public static func isRest(_ floor: Int) -> Bool { floor % 10 == 0 && !boss(on: floor) }

    /// spireSpawnEnemy / spireRestFloor. Returns the lines to log and read.
    public static func enter(_ run: inout SpireRun, store: GameStore, wallet: Wallet, dice: inout some Dice) -> [String] {
        run.cleared = false
        if isRest(run.floor) { return rest(&run, store: store, wallet: wallet, dice: &dice) }
        let m = 1 + log(1 + Double(run.floor - 1) * 0.05)
        func scaled(_ r: ClosedRange<Int>) -> ClosedRange<Int> {
            let lo = jsRound(Double(r.lowerBound) * m), hi = jsRound(Double(r.upperBound) * m)
            return lo...max(lo, hi)
        }
        if let b = bosses.first(where: { $0.floor == run.floor }) {
            let hp = jsRound(Double(b.hp) * m)
            run.enemy = SpireRun.Foe(name: b.name, icon: b.icon, hp: hp, maxHp: hp, atk: scaled(b.atk), isBoss: true)
            return ["⚡ BOSS FLOOR — \(b.icon) \(b.name)", b.msg, "Boss HP: \(hp) | Your HP: \(run.hp)/\(run.maxHp)"]
        }
        let pool = run.floor <= 50 ? tiers[0] : run.floor <= 200 ? tiers[1] : run.floor <= 500 ? tiers[2] : run.floor <= 1000 ? tiers[3] : tiers[4]
        let t = pool[dice.roll(0...(pool.count - 1))]
        let hp = jsRound(Double(t.hp) * m)
        run.enemy = SpireRun.Foe(name: t.name, icon: t.icon, hp: hp, maxHp: hp, atk: scaled(t.atk), isBoss: false)
        return ["Floor \(run.floor) — \(t.icon) \(t.name) appears.", "Enemy HP: \(hp) | Your HP: \(run.hp)/\(run.maxHp)"]
    }

    static func rest(_ run: inout SpireRun, store: GameStore, wallet: Wallet, dice: inout some Dice) -> [String] {
        run.enemy = nil
        let pct = min(0.60, 0.40 + Double(run.floor) / Double(top) * 0.20)
        let heal = jsRound(Double(run.maxHp) * pct)
        run.hp = min(run.maxHp, run.hp + heal)
        run.potions = min(run.potions + 1, 10)
        let g = 20 + run.floor
        run.gold += g
        wallet.addGold(g)
        var lines = ["🕯 REST FLOOR \(run.floor)", "You find a moment of stillness in the Spire.",
                     "❤ Restored \(heal) HP. HP: \(run.hp)/\(run.maxHp).", "💰 +\(g) gold found.",
                     "📖 " + lore[(run.floor / 50) % lore.count]]
        lines += floorRewards(&run, store: store, wallet: wallet, dice: &dice)
        run.cleared = true
        saveBest(run.floor, store: store)
        return lines
    }

    /// Every 10th floor (boss or rest): its milestone gold, and a chance of
    /// diamonds and Mystery Coins. (Gun parts wait for the guns.)
    static func floorRewards(_ run: inout SpireRun, store: GameStore, wallet: Wallet, dice: inout some Dice) -> [String] {
        guard run.floor % 10 == 0, run.floor > rewarded(store) else { return [] }
        setRewarded(run.floor, store)
        var lines: [String] = []
        if let ms = milestones[run.floor] {
            run.gold += ms.gold
            wallet.addGold(ms.gold)
            lines.append("🏆 MILESTONE: " + ms.msg)
        }
        let depth = run.floor / 100
        if dice.chance(0.20 + Double(depth) * 0.03) {
            let n = max(1, depth / 2 + 1)
            wallet.addDiamonds(n)
            lines.append("💎 Floor \(run.floor) drop: \(n) diamond\(n > 1 ? "s" : "")!")
        }
        if dice.chance(0.25 + Double(depth) * 0.02) {
            let n = dice.chance(0.3) ? 2 : 1
            addCoins(n, store: store)
            lines.append("🪙 Floor \(run.floor) drop: \(n) mystery coin\(n > 1 ? "s" : "")!")
        }
        return lines
    }

    static func addCoins(_ n: Int, store: GameStore) {
        let total = CoinShop.coins(store) + n
        store.setItem("dd_mystery_coins", String(total))
        RaidSave(store: store).syncCoins(total)
    }

    public enum Action: Sendable { case attack, heavy, defend }

    /// spireDoPlayerTurn: your hit, the enemy's answer, and the auto-potion at 40% HP.
    public static func turn(_ run: inout SpireRun, _ action: Action, store: GameStore, wallet: Wallet,
                            dice: inout some Dice, gun: (name: String, damage: Int)? = nil) -> [String] {
        guard var e = run.enemy, !run.cleared, !run.dead else { return [] }
        var lines: [String] = []
        var dmg = max(1, dice.roll((run.atk - 2)...(run.atk + 8)))
        switch action {
        case .heavy:
            if dice.chance(0.30) { lines.append("Heavy strike misses!"); dmg = 0 } else { dmg = jsRound(Double(dmg) * 1.7) }
        case .defend: dmg = jsRound(Double(dmg) * 0.4)
        case .attack: break
        }
        // spireGunAction: a shot takes the turn's attack.
        if let gun { dmg = gun.damage }
        if dmg > 0 {
            e.hp = max(0, e.hp - dmg)
            lines.append(gun.map { "🔫 \($0.name) fires! \(dmg) damage!" }
                         ?? (action == .heavy ? "Heavy strike — \(dmg) damage!" : action == .defend ? "Defend and counter — \(dmg)." : "Attack — \(dmg) damage!"))
        }
        run.enemy = e
        if e.hp <= 0 { return lines + defeated(&run, store: store, wallet: wallet, dice: &dice) }
        var hit = max(1, dice.roll(e.atk) - run.def)
        if action == .defend { hit = max(1, jsRound(Double(hit) * 0.4)) }
        run.hp = max(0, run.hp - hit)
        lines.append("\(e.name) strikes for \(hit). HP: \(run.hp)/\(run.maxHp).")
        if run.hp > 0 && run.hp <= jsRound(Double(run.maxHp) * 0.40) && run.potions > 0 {
            run.hp = min(run.maxHp, run.hp + jsRound(Double(run.maxHp) * 0.50))
            run.potions -= 1
            lines.append("🧪 Auto-potion used. HP: \(run.hp)/\(run.maxHp). \(run.potions) left.")
        }
        if run.hp <= 0 {
            run.dead = true
            saveBest(run.floor, store: store)
        }
        return lines
    }

    /// spireUsePotion: 45% of max HP.
    public static func potion(_ run: inout SpireRun) -> String {
        guard run.potions > 0 else { return "No potions left." }
        let heal = jsRound(Double(run.maxHp) * 0.45)
        run.hp = min(run.maxHp, run.hp + heal)
        run.potions -= 1
        return "🧪 Potion used. Restored \(heal) HP. HP: \(run.hp)/\(run.maxHp). Potions left: \(run.potions)."
    }

    /// spireEnemyDefeated. (The web version added the kill's gold to your
    /// global gold twice.)
    static func defeated(_ run: inout SpireRun, store: GameStore, wallet: Wallet, dice: inout some Dice) -> [String] {
        guard let e = run.enemy else { return [] }
        let g = jsRound(3 + Double(run.floor) * 0.5)
        run.gold += g
        wallet.addGold(g)
        var lines = ["\(e.icon) \(e.name) defeated! +\(g)g. Your HP: \(run.hp)/\(run.maxHp)."]
        lines += floorRewards(&run, store: store, wallet: wallet, dice: &dice)
        saveBest(run.floor, store: store)
        run.cleared = true
        if run.floor >= top { lines += victory(&run, store: store, wallet: wallet) }
        return lines
    }

    /// spireVictory: 1000 gold, 25 Mystery Coins (the web version put them
    /// on the character, where the Coin Shop never looked) and 25% off at the
    /// Blacksmith for two hours.
    static func victory(_ run: inout SpireRun, store: GameStore, wallet: Wallet, now: Date = Date()) -> [String] {
        run.won = true
        saveBest(top, store: store)
        wallet.addGold(1000)
        run.gold += 1000
        addCoins(25, store: store)
        let exp = Int((now.timeIntervalSince1970 + 2 * 3600) * 1000)
        store.setItem("dd_blacksmith_discount", "{\"pct\":0.25,\"expires\":\(exp),\"source\":\"Time Eater\"}")
        return ["⏳ THE TIME EATER IS DEFEATED."]
    }

    /// spireNextFloor
    public static func next(_ run: inout SpireRun, store: GameStore, wallet: Wallet, dice: inout some Dice) -> [String] {
        guard run.cleared, !run.won else { return [] }
        run.floor += 1
        saveBest(run.floor, store: store)
        return enter(&run, store: store, wallet: wallet, dice: &dice)
    }
}
