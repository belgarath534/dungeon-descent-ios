import Foundation

/// The Spirit Builder (SB_ICONS, SB_ABILITIES, openSpiritBuilder,
/// getCustomSpiritFunctions, confirmBuildSpirit): 40% of kills drop a Soul
/// Fragment, and 25 of them forge a spirit of your own — a name, an icon and
/// one of twenty abilities — that every character can pick (saved in
/// "dd_custom_spirits", like the web version). Web bugs fixed: Predator's Eye,
/// Wind Step and Lucky Charm added 15, 30 and 10 as whole numbers to chances
/// kept as fractions (always crit, always flee); bonuses were added again at
/// every fight; Purifying Song worked per kill instead of per floor.
public enum CustomSpirits {
    public struct Ability: Sendable, Identifiable {
        public let id, label, desc: String
    }

    public static let cost = 25
    public static let icons = ["🐺", "🦅", "🌑", "🔥", "💀", "⚡", "🌿", "👁️", "🌊", "🐉", "🦋", "❄️"]

    public static let abilities: [Ability] = [
        .init(id: "heal-kill", label: "Soul Mend", desc: "Restore 8 HP on every kill."),
        .init(id: "bonus-dmg", label: "Surge Strike", desc: "20% chance to deal bonus damage each attack."),
        .init(id: "sp-kill", label: "Essence Drain", desc: "Restore 3 SP on every kill."),
        .init(id: "block", label: "Spirit Ward", desc: "15% chance to block incoming damage completely."),
        .init(id: "gold-boost", label: "Fortune's Veil", desc: "Earn 25% more gold from all sources."),
        .init(id: "poison-start", label: "Venom Aura", desc: "Poison the enemy at the start of every combat."),
        .init(id: "instakill", label: "Final Judgment", desc: "10% chance to finish enemies below 20% HP."),
        .init(id: "corruption", label: "Purifying Song", desc: "Reduce corruption by 5% each floor."),
        .init(id: "xp-boost", label: "Scholar's Mark", desc: "Earn 20% more XP from all sources."),
        .init(id: "crit-boost", label: "Predator's Eye", desc: "Increase critical hit chance by 15%."),
        .init(id: "def-boost", label: "Iron Veil", desc: "Gain +4 DEF permanently while active."),
        .init(id: "atk-boost", label: "Wrath Brand", desc: "Gain +3 ATK permanently while active."),
        .init(id: "flee-boost", label: "Wind Step", desc: "Increase flee chance by 30%."),
        .init(id: "heal-floor", label: "Floor Blessing", desc: "Restore 10 HP at the start of each new floor."),
        .init(id: "sp-regen", label: "Mana Spring", desc: "Restore 2 SP at the start of each combat."),
        .init(id: "luck-boost", label: "Lucky Charm", desc: "Increase luck by 10, improving loot drops."),
        .init(id: "lifesteal", label: "Blood Pact", desc: "Steal 10% of damage dealt as HP."),
        .init(id: "tank", label: "Stone Skin", desc: "Reduce all incoming damage by 3."),
        .init(id: "double-gold", label: "Gilded Touch", desc: "10% chance to double gold from any source."),
        .init(id: "burn-start", label: "Ember Spirit", desc: "Burn the enemy for 2 turns at combat start."),
    ]

    // MARK: Soul Fragments

    public static func fragments(_ store: GameStore) -> Int { max(0, jsParseInt(store.getItem("dd_soul_fragments")) ?? 0) }

    /// 40% of kills. Returns what to say, if anything (the 1st, every 5th, the 25th).
    public static func killDrop(_ store: GameStore, dice: inout some Dice) -> String? {
        guard dice.chance(0.40) else { return nil }
        let n = fragments(store) + 1
        store.setItem("dd_soul_fragments", String(n))
        if n == 1 { return "🔮 Soul Fragment collected. You collected your first Soul Fragment. Collect 25 to build a custom spirit in the Bestiary." }
        if n == cost { return "🔮 Soul Fragment collected. You have 25 Soul Fragments! Go to the Bestiary Builder to create your own spirit companion." }
        return n % 5 == 0 ? "🔮 Soul Fragment collected. \(n) of 25." : nil
    }

    // MARK: The forged spirits

    struct Saved: Codable {
        var id, name, icon: String
        var rarity: String?
        var abilityId: String
        var desc, ability, passiveDesc: String?
    }

    /// Loaded by the app; the dungeon looks spirits up here as well.
    nonisolated(unsafe) public static var loaded: [Spirit] = []

    public static func reload(_ store: GameStore) {
        guard let s = store.getItem("dd_custom_spirits"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([Saved].self, from: d) else { loaded = []; return }
        loaded = v.compactMap { c in
            guard let ab = abilities.first(where: { $0.id == c.abilityId }) else { return nil }
            var sp = Spirit(id: c.id, name: c.name, icon: c.icon, rarity: "rare", desc: c.desc ?? "A spirit forged from 25 Soul Fragments. \(ab.desc)",
                            ability: ab.desc, passive: ab.label, minLevel: 5, strike: 0)
            sp.customAbility = ab.id
            return sp
        }
    }

    /// confirmBuildSpirit. Nil when it worked, or the problem.
    public static func build(name raw: String, icon: String, ability: String, store: GameStore, now: Date = Date()) -> String? {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !name.isEmpty else { return "Please enter a name." }
        guard let ab = abilities.first(where: { $0.id == ability }) else { return "Please choose an ability." }
        guard fragments(store) >= cost else { return "Not enough fragments." }
        if CommunityEnemies.hasBadWord(name) { return "That name is not allowed. Please choose another." }
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        var list: [[String: JSONValue]] = []
        if let s = store.getItem("dd_custom_spirits"), let d = s.data(using: .utf8),
           let v = try? JSONDecoder().decode([[String: JSONValue]].self, from: d) { list = v }
        list.append([
            "id": .string("custom-\(slug)-\(Int(now.timeIntervalSince1970 * 1000))"), "name": .string(name), "icon": .string(icon),
            "rarity": .string("rare"), "isCustomBuilt": .bool(true), "abilityId": .string(ab.id),
            "desc": .string("A spirit forged from 25 Soul Fragments. \(ab.desc)"), "ability": .string(ab.desc), "passiveDesc": .string(ab.label),
        ])
        if let d = try? JSONEncoder().encode(list), let s = String(data: d, encoding: .utf8) { store.setItem("dd_custom_spirits", s) }
        store.setItem("dd_soul_fragments", String(fragments(store) - cost))
        reload(store)
        return nil
    }

    // MARK: In the dungeon

    static func ability(_ run: Run) -> String? { Spirits.awake(run)?.customAbility }

    static func combatStart(_ run: inout Run, e: inout Enemy, log: inout [String]) {
        switch ability(run) {
        case "poison-start": e.dotDamage = max(e.dotDamage, 5); e.dotTurns = max(e.dotTurns, 4); log.append("✨ Venom Aura — enemy poisoned for 4 turns!")
        case "burn-start": e.dotDamage = max(e.dotDamage, 6); e.dotTurns = max(e.dotTurns, 2); log.append("✨ Ember Spirit — enemy burning for 2 turns!")
        case "def-boost": run.fight.def += 4; log.append("✨ Iron Veil — +4 DEF!")
        case "atk-boost": run.fight.atk += 3; log.append("✨ Wrath Brand — +3 ATK!")
        case "sp-regen": run.sp = min(run.maxSp, run.sp + 2); log.append("✨ Mana Spring — +2 SP!")
        case "heal-floor" where run.spiritHealFloor != run.floor:
            run.spiritHealFloor = run.floor
            run.hp = min(run.maxHp, run.hp + 10)
            log.append("✨ Floor Blessing — restored 10 HP!")
        case "block": log.append("✨ Spirit Ward active — 15% chance to block attacks.")
        case "tank": log.append("✨ Stone Skin — damage reduced by 3!")
        default: break
        }
    }

    /// After your attack.
    static func attack(_ run: inout Run, e: inout Enemy, base: Int, dice: inout some Dice, log: inout [String]) {
        switch ability(run) {
        case "bonus-dmg" where dice.chance(0.20):
            let d = Int(Double(base) * 0.4)
            e.hp = max(0, e.hp - d)
            log.append("✨ Surge Strike — \(d) bonus damage!")
        case "instakill" where !e.isBoss && Double(e.hp) <= Double(e.maxHp) * 0.20 && dice.chance(0.10):
            e.hp = 0
            log.append("✨ Final Judgment — instant kill!")
        case "lifesteal":
            let steal = base / 10
            if steal > 0 { run.hp = min(run.maxHp, run.hp + steal); log.append("✨ Blood Pact — stole \(steal) HP!") }
        default: break
        }
    }

    static func blocks(_ run: Run, dice: inout some Dice, log: inout [String]) -> Bool {
        guard ability(run) == "block", dice.chance(0.15) else { return false }
        log.append("✨ Spirit Ward blocks the attack!")
        return true
    }

    static func incoming(_ run: Run, _ taken: Int) -> Int { ability(run) == "tank" && taken > 0 ? max(1, taken - 3) : taken }

    static func crit(_ run: Run) -> Double { ability(run) == "crit-boost" ? 0.15 : 0 }
    static func flee(_ run: Run) -> Double { ability(run) == "flee-boost" ? 0.30 : 0 }

    static func gold(_ run: Run, _ g: Int, dice: inout some Dice, log: inout [String]) -> Int {
        switch ability(run) {
        case "gold-boost": return jsRound(Double(g) * 1.25)
        case "luck-boost": return jsRound(Double(g) * 1.10)
        case "double-gold" where dice.chance(0.10): log.append("✨ Gilded Touch — gold doubled!"); return g * 2
        default: return g
        }
    }

    static func xp(_ run: Run, _ xp: Int) -> Int { ability(run) == "xp-boost" ? jsRound(Double(xp) * 1.2) : xp }

    static func kill(_ run: inout Run, log: inout [String]) {
        switch ability(run) {
        case "heal-kill": run.hp = min(run.maxHp, run.hp + 8); log.append("✨ Spirit heals 8 HP on kill!")
        case "sp-kill": run.sp = min(run.maxSp, run.sp + 3); log.append("✨ Spirit restores 3 SP on kill!")
        default: break
        }
    }

    /// A new floor: Purifying Song.
    public static func newFloor(_ run: inout Run) -> String? {
        guard ability(run) == "corruption" else { return nil }
        var did = false
        if let c = run.corruption, c > 0 { run.corruption = max(0, c - 5); did = true }
        if run.forestCorruption > 0 { run.forestCorruption = max(0, run.forestCorruption - 5); did = true }
        return did ? "✨ Purifying Song reduces corruption by 5%." : nil
    }
}
