import Foundation

/// A captured enemy that fights beside you (MINION SYSTEM, "dd_minions").
public struct Minion: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var icon: String
    public var atk: Int
    public var tier: String
    public var capturedOn: Double
}

/// Your Home on the edge of the dungeon ("dd_home"): bought once for 500
/// gold, with a bed, a gold safe and skill upgrades, plus the minions and
/// the dreams you have when you sleep.
public enum Home {
    public static let cost = 500
    public static let bedCost = 75
    public static let sleepRooms = 5
    public static let maxSkillLevel = 5
    public static let skillCooldown: Double = 3 * 60
    public static let maxMinions = 8

    // MARK: The save

    public static func save(_ store: GameStore) -> [String: JSONValue] {
        guard let s = store.getItem("dd_home"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) else { return [:] }
        return v
    }

    static func write(_ v: [String: JSONValue], _ store: GameStore) {
        if let d = try? JSONEncoder().encode(v), let s = String(data: d, encoding: .utf8) { store.setItem("dd_home", s) }
    }

    static func num(_ v: [String: JSONValue], _ k: String) -> Int { if case .number(let n)? = v[k] { return Int(n) }; return 0 }

    public static func owned(_ store: GameStore) -> Bool { save(store)["owned"] == .bool(true) }
    public static func hasBed(_ store: GameStore) -> Bool { save(store)["bed"] == .bool(true) }
    public static func safe(_ store: GameStore) -> Int { num(save(store), "safe") }

    /// buyHome / buyBed: paid from your global gold.
    public static func buyHome(store: GameStore, wallet: Wallet) -> Bool {
        guard wallet.spendGold(cost) else { return false }
        var h = save(store)
        h["owned"] = .bool(true)
        h["safe"] = .number(0)
        write(h, store)
        return true
    }

    public static func buyBed(store: GameStore, wallet: Wallet) -> Bool {
        guard wallet.spendGold(bedCost) else { return false }
        var h = save(store)
        h["bed"] = .bool(true)
        write(h, store)
        return true
    }

    /// homeDeposit / homeWithdraw
    public static func deposit(_ amount: Int, store: GameStore, wallet: Wallet) -> Bool {
        guard amount > 0, wallet.spendGold(amount) else { return false }
        var h = save(store)
        h["safe"] = .number(Double(num(h, "safe") + amount))
        write(h, store)
        return true
    }

    public static func withdraw(_ amount: Int, store: GameStore, wallet: Wallet) -> Bool {
        var h = save(store)
        guard amount > 0, amount <= num(h, "safe") else { return false }
        h["safe"] = .number(Double(num(h, "safe") - amount))
        write(h, store)
        wallet.addGold(amount)
        return true
    }

    // MARK: Sleeping and dreams

    /// Rooms still to explore before the bed can be used again (0 = ready).
    public static func roomsBeforeSleep(_ run: Run, store: GameStore) -> Int {
        max(0, sleepRooms - (run.totalRooms - num(save(store), "lastSleepRoom")))
    }

    /// Each run starts with the bed ready (initDungeon resets lastSleepRoom).
    public static func resetSleep(store: GameStore) {
        var h = save(store)
        h["lastSleepRoom"] = .number(0)
        write(h, store)
    }

    public struct Dream: Sendable {
        public let id, type, icon, title, story, buff: String
    }

    /// HOME_DREAMS
    public static let dreams: [Dream] = [
        Dream(id: "warriors-dream", type: "buff", icon: "⚔️", title: "A Warrior's Dream", story: "You stand on a battlefield that stretches to every horizon. You have already won.", buff: "ATK +3 for your next run."),
        Dream(id: "golden-dream", type: "buff", icon: "💰", title: "The Golden Dream", story: "Coins fall like rain. You catch them all. Your hands never fill.", buff: "Gold drops +30% for your next run."),
        Dream(id: "iron-dream", type: "buff", icon: "🛡️", title: "Iron Sleep", story: "Your armor fuses to your skin in the dream. It does not hurt. It feels right.", buff: "DEF +3 for your next run."),
        Dream(id: "healers-dream", type: "buff", icon: "❤️", title: "The Healer's Grace", story: "A figure you cannot name presses their hand to your chest. The wound closes.", buff: "Potions heal 25% more next run."),
        Dream(id: "spirit-dream", type: "buff", icon: "✨", title: "The Spirit Dream", story: "Your spirit companion speaks to you in words you almost understand.", buff: "+15 max SP for your next run."),
        Dream(id: "fleet-dream", type: "buff", icon: "🏃", title: "Swift as Shadow", story: "You run through the dark and nothing catches you. Not tonight.", buff: "+10% flee chance next run."),
        Dream(id: "void-lore", type: "lore", icon: "🌑", title: "The Void Speaks", story: "A voice from the dark: The dungeons are not places. They are tests. You were chosen.", buff: "No buff. The dungeon remembers."),
        Dream(id: "leviathan-lore", type: "lore", icon: "🌊", title: "The Deep Memory", story: "You see the Leviathan before it was a monster. It was something else entirely once.", buff: "No buff. Knowledge has a cost."),
        Dream(id: "malachar-lore", type: "lore", icon: "💀", title: "Malachar's Confession", story: "The dead king speaks: I built the crypt to hide something. I am what I was hiding.", buff: "No buff. The truth is its own reward."),
        Dream(id: "crypt-lore", type: "lore", icon: "🕯️", title: "Candlelight and Nothing", story: "You see every adventurer who died in the dungeon before you. They are waiting.", buff: "No buff. You are not alone."),
        Dream(id: "nightmare-dream", type: "dark", icon: "👁️", title: "The Watching Dream", story: "Something watched you sleep. It did not move. It was still watching when you woke.", buff: "No buff. It knows your name now."),
        Dream(id: "falling-dream", type: "dark", icon: "🕳️", title: "The Fall", story: "You fell for a long time. You never landed. You woke up on the floor.", buff: "No buff. You feel rested somehow."),
    ]

    /// homeSleep: full HP and SP and a dream. The dream's id is saved on the
    /// character; its buff applies when the next run starts.
    public static func sleep(_ run: inout Run, store: GameStore, dice: inout some Dice) -> Dream? {
        guard roomsBeforeSleep(run, store: store) == 0 else { return nil }
        run.hp = run.maxHp
        run.sp = run.maxSp
        var h = save(store)
        h["lastSleepRoom"] = .number(Double(run.totalRooms))
        write(h, store)
        return dreams[dice.roll(0...(dreams.count - 1))]
    }

    /// The dream buffs at run start. The web version stored them on the run
    /// it was about to throw away, so they never reached the next one.
    public static func applyDream(_ id: String?, to run: inout Run) -> String? {
        switch id {
        case "warriors-dream": run.atkBonus += 3; return "Dream buff: +3 ATK"
        case "iron-dream": run.defBonus += 3; return "Dream buff: +3 DEF"
        case "spirit-dream": run.maxSp += 15; run.sp = run.maxSp; return "Dream buff: +15 max SP"
        case "healers-dream": run.potionMult *= 1.25; return "Dream buff: potions heal more"
        case "fleet-dream": run.fleeBonus += 0.10; return "Dream buff: +flee chance"
        case "golden-dream": run.dreamGoldMult = 1.30; return "Dream buff: +30% gold"
        default: return nil
        }
    }

    // MARK: Skill upgrades

    /// The upgrade's key, like "Warrior_Shield_Bash".
    public static func skillKey(cls: String, name: String) -> String { "\(cls)_\(name)".replacingOccurrences(of: " ", with: "_") }

    public static func skillLevels(_ store: GameStore) -> [String: Int] {
        guard case .object(let o)? = save(store)["skillLevels"] else { return [:] }
        return o.compactMapValues { if case .number(let n) = $0 { return Int(n) }; return nil }
    }

    /// Seconds until upgrades are allowed again (0 = now).
    public static func skillCooldownLeft(_ store: GameStore, now: Double = Date().timeIntervalSince1970) -> Int {
        max(0, Int((Double(num(save(store), "skillCooldownUntil")) / 1000 - now).rounded(.up)))
    }

    /// homeUpgradeSkill: level × 80 gold, up to level 5; five upgrades in a
    /// row start a 3-minute cooldown.
    public static func upgradeSkill(cls: String, name: String, store: GameStore, wallet: Wallet,
                                    now: Double = Date().timeIntervalSince1970) -> String {
        var h = save(store)
        if skillCooldownLeft(store, now: now) > 0 { return "On cooldown." }
        let key = skillKey(cls: cls, name: name)
        var levels = skillLevels(store)
        let level = levels[key] ?? 1
        if level >= maxSkillLevel { return "\(name) is maxed." }
        guard wallet.spendGold(level * 80) else { return "Not enough gold." }
        levels[key] = level + 1
        h["skillLevels"] = .object(levels.mapValues { .number(Double($0)) })
        var count = num(h, "upgradeCount") + 1
        if count >= maxSkillLevel {
            h["skillCooldownUntil"] = .number((now + skillCooldown) * 1000)
            count = 0
        }
        h["upgradeCount"] = .number(Double(count))
        write(h, store)
        return "\(name) upgraded to level \(level + 1)."
    }

    // MARK: Skill Orbs

    /// One upgraded skill kept from a fallen character (dd_skill_orbs).
    public struct SkillOrb: Codable, Equatable, Sendable {
        public var id: String
        public var skillName: String
        public var className: String
        public var level: Int
        public var fromChar: String
        public var created: Double
    }

    public static func skillOrbs(_ store: GameStore) -> [SkillOrb] {
        guard let s = store.getItem("dd_skill_orbs"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([SkillOrb].self, from: d) else { return [] }
        return v
    }

    static func saveOrbs(_ o: [SkillOrb], _ store: GameStore) {
        if let d = try? JSONEncoder().encode(o), let s = String(data: d, encoding: .utf8) { store.setItem("dd_skill_orbs", s) }
    }

    /// homeCreateSkillOrbs: when a character falls, every skill above level 1
    /// becomes an orb and the Home's upgrades start again. Returns how many.
    @discardableResult
    public static func makeSkillOrbs(fromChar: String, store: GameStore, now: Double = Date().timeIntervalSince1970) -> Int {
        let levels = skillLevels(store).filter { $0.value > 1 }
        guard !levels.isEmpty else { return 0 }
        var orbs = skillOrbs(store)
        for (id, level) in levels.sorted(by: { $0.key < $1.key }) {
            let parts = id.split(separator: "_").map(String.init)
            orbs.append(SkillOrb(id: id, skillName: parts.dropFirst().joined(separator: " "), className: parts.first ?? "",
                                 level: level, fromChar: fromChar, created: now * 1000))
        }
        saveOrbs(orbs, store)
        var h = save(store)
        h["skillLevels"] = .object([:])
        h["upgradeCount"] = .number(0)
        write(h, store)
        return levels.count
    }

    /// useSkillOrb: only a character of the orb's class can take it. The skill
    /// goes to the orb's level (never down).
    public static func useSkillOrb(at index: Int, cls: String, store: GameStore) -> (used: Bool, message: String) {
        var orbs = skillOrbs(store)
        guard orbs.indices.contains(index) else { return (false, "That orb is gone.") }
        let o = orbs[index]
        guard o.className == cls else {
            return (false, "This orb is for a \(o.className). Your character is a \(cls.isEmpty ? "nobody yet" : cls). You need to play the same class to use this orb.")
        }
        var h = save(store)
        var levels = skillLevels(store)
        levels[o.id] = max(levels[o.id] ?? 1, o.level)
        h["skillLevels"] = .object(levels.mapValues { .number(Double($0)) })
        write(h, store)
        orbs.remove(at: index)
        saveOrbs(orbs, store)
        return (true, "Skill Orb used. \(o.skillName) upgraded to level \(o.level) from \(o.fromChar).")
    }

    // MARK: Minions

    public static func minions(_ store: GameStore) -> [Minion] {
        guard let s = store.getItem("dd_minions"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([Minion].self, from: d) else { return [] }
        return v
    }

    static func saveMinions(_ m: [Minion], _ store: GameStore) {
        if let d = try? JSONEncoder().encode(m), let s = String(data: d, encoding: .utf8) { store.setItem("dd_minions", s) }
    }

    public static func activeMinion(_ store: GameStore) -> Minion? {
        guard let id = store.getItem("dd_active_minion") else { return nil }
        return minions(store).first { $0.id == id }
    }

    public static func setActive(_ id: String?, store: GameStore) {
        if let id { store.setItem("dd_active_minion", id) } else { store.removeItem("dd_active_minion") }
    }

    public static func release(_ id: String, store: GameStore) {
        saveMinions(minions(store).filter { $0.id != id }, store)
        if store.getItem("dd_active_minion") == id { setActive(nil, store: store) }
    }

    public enum CaptureResult: Equatable, Sendable { case captured(Minion), duplicate, full, boss, noTrap }

    /// doFight('soul-trap') + captureMinion: 60% of the enemy's top attack,
    /// 85% for an elite (the web version never passed the elite flag, so
    /// elite minions never happened). Up to 8, as the Help screen says.
    public static func capture(_ run: inout Run, store: GameStore) -> CaptureResult {
        guard let e = run.enemy else { return .noTrap }
        if e.isBoss { return .boss }
        guard let trap = run.inventory.firstIndex(where: { $0.type == "soul-trap" }) else { return .noTrap }
        var list = minions(store)
        let id = e.name.lowercased().replacingOccurrences(of: " ", with: "_")
        if list.contains(where: { $0.id == id }) { return .duplicate }
        if list.count >= maxMinions { return .full }
        let m = Minion(id: id, name: e.name, icon: e.icon, atk: max(1, Int(Double(e.atk.upperBound) * (e.isElite ? 0.85 : 0.60))),
                       tier: e.isElite ? "elite" : "common", capturedOn: (Date().timeIntervalSince1970 * 1000).rounded())
        list.append(m)
        saveMinions(list, store)
        run.inventory.remove(at: trap)
        run.inCombat = false
        run.enemy = nil
        run.kills += 1
        return .captured(m)
    }
}
