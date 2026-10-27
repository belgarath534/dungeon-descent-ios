import Foundation

/// A gun (GUN_DEFS).
public struct Gun: Sendable, Equatable {
    public let id: String
    public let name: String
    public let icon: String
    public let tier: Int
    public let damage: ClosedRange<Int>
    /// Shots per charge before the reload.
    public let shots: Int
    /// Reload, in seconds.
    public let cooldown: Int
    public let desc: String
    public let diamondCost: Int
    public let parts: [String]

    /// The parts it takes, counted ("barrel": 2 …).
    public var partCounts: [String: Int] { parts.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
}

/// GUNS: crafted from parts at Home, bought with diamonds at the Blacksmith,
/// and fired in fights. Charging is free; each shot is your turn; after the
/// last shot the gun reloads for some seconds. Saved like the web version
/// (dd_gun_parts, dd_owned_guns, dd_equipped_gun).
public enum Guns {
    public struct Part: Sendable { public let id, name, icon, desc: String }

    public static let parts: [Part] = [
        Part(id: "barrel", name: "Gun Barrel", icon: "🔩", desc: "A steel barrel. Part of a gun."),
        Part(id: "mechanism", name: "Firing Mechanism", icon: "⚙️", desc: "The internal firing component."),
        Part(id: "stock", name: "Gun Stock", icon: "🪵", desc: "A wooden stock for grip and stability."),
        Part(id: "trigger", name: "Trigger Assembly", icon: "🔧", desc: "The trigger and firing pin assembly."),
    ]

    public static func part(_ id: String) -> Part? { parts.first { $0.id == id } }

    static func g(_ id: String, _ name: String, _ icon: String, _ tier: Int, _ dmg: ClosedRange<Int>, _ shots: Int, _ cd: Int,
                  _ cost: Int, _ parts: [String], _ desc: String) -> Gun {
        Gun(id: id, name: name, icon: icon, tier: tier, damage: dmg, shots: shots, cooldown: cd, desc: desc, diamondCost: cost, parts: parts)
    }

    public static let all: [Gun] = [
        g("flintlock", "Flintlock Pistol", "🔫", 1, 18...28, 1, 15, 5, ["barrel", "mechanism", "stock", "trigger"],
          "A classic single-shot flintlock. Reliable, slow. Must recharge after every shot."),
        g("revolver", "Revolver", "🔫", 2, 28...42, 1, 12, 10, ["barrel", "mechanism", "stock", "trigger"],
          "A six-chamber revolver. More power, slightly faster cooldown than the flintlock."),
        g("sawedoff", "Sawed-Off Shotgun", "💥", 3, 45...70, 1, 18, 18, ["barrel", "barrel", "mechanism", "trigger"],
          "Devastating at close range. Highest single-shot damage but longest cooldown."),
        g("repeater", "Repeater Rifle", "🔫", 4, 32...48, 3, 15, 28, ["barrel", "mechanism", "mechanism", "stock", "trigger"],
          "Fire 3 shots before reloading. Solid damage, good rhythm."),
        g("autorifle", "Automatic Rifle", "⚡", 5, 40...58, 5, 20, 45, ["barrel", "barrel", "mechanism", "mechanism", "stock", "trigger"],
          "Five shots before reload. High sustained damage output."),
        g("ak47", "AK-47", "☠️", 6, 65...95, 8, 25, 80, ["barrel", "barrel", "mechanism", "mechanism", "mechanism", "stock", "stock", "trigger"],
          "The god of guns. 8 shots before reload. Highest damage in the game. Extremely rare."),
        g("musket", "Musket", "🔫", 2, 55...80, 1, 22, 14, ["barrel", "stock", "trigger"],
          "Old school single shot. Massive damage but the longest cooldown of any single shot weapon. One shot, one kill."),
        g("doublebarrel", "Double Barrel Shotgun", "💥", 3, 38...55, 2, 16, 20, ["barrel", "barrel", "stock", "trigger"],
          "Two barrels, two shots, then reload. More controlled than the sawed-off. Two bangs before the silence."),
        g("sniper", "Sniper Rifle", "🎯", 5, 70...100, 1, 20, 50, ["barrel", "barrel", "mechanism", "stock", "trigger"],
          "Highest single shot damage in the game. One bullet. Make it count."),
        g("machinepistol", "Machine Pistol", "⚡", 4, 15...25, 10, 18, 35, ["barrel", "mechanism", "mechanism", "stock", "trigger"],
          "Weak per shot but 10 shots before reloading. Sustained pressure. Never lets the enemy breathe."),
        g("crossbow", "Crossbow", "🏹", 2, 25...40, 1, 10, 12, ["barrel", "stock", "trigger"],
          "Silent. Deadly. Fastest cooldown of any gun. A fantasy weapon in a dark dungeon — it fits perfectly."),
        g("magnum", "Magnum", "🔫", 3, 40...60, 1, 13, 22, ["barrel", "mechanism", "stock", "trigger"],
          "The revolver's bigger, angrier brother. More damage, slightly longer cooldown. A serious weapon."),
        g("glock", "Glock", "🔫", 3, 22...35, 3, 11, 18, ["barrel", "mechanism", "stock", "trigger"],
          "Reliable, fast, no nonsense. 3 shots before reload, short cooldown. The everyday carry of dungeon weapons."),
    ]

    public static func gun(_ id: String) -> Gun? { all.first { $0.id == id } }

    // MARK: Saves

    public static func partCounts(_ store: GameStore) -> [String: Int] {
        guard let s = store.getItem("dd_gun_parts"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) else { return [:] }
        return v.compactMapValues { if case .number(let n) = $0 { return Int(n) }; return nil }
    }

    static func savePartCounts(_ p: [String: Int], _ store: GameStore) {
        if let d = try? JSONEncoder().encode(p), let s = String(data: d, encoding: .utf8) { store.setItem("dd_gun_parts", s) }
    }

    public static func addPart(_ id: String, store: GameStore) {
        var p = partCounts(store)
        p[id, default: 0] += 1
        savePartCounts(p, store)
    }

    public static func owned(_ store: GameStore) -> [String] {
        guard let s = store.getItem("dd_owned_guns"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return v
    }

    static func addOwned(_ id: String, _ store: GameStore) {
        var o = owned(store)
        guard !o.contains(id) else { return }
        o.append(id)
        if let d = try? JSONEncoder().encode(o), let s = String(data: d, encoding: .utf8) { store.setItem("dd_owned_guns", s) }
    }

    public static func equipped(_ store: GameStore) -> Gun? { store.getItem("dd_equipped_gun").flatMap(gun) }

    public static func equip(_ id: String?, store: GameStore) {
        if let id, owned(store).contains(id) { store.setItem("dd_equipped_gun", id) } else { store.removeItem("dd_equipped_gun") }
    }

    public static func canCraft(_ g: Gun, store: GameStore) -> Bool {
        let have = partCounts(store)
        return g.partCounts.allSatisfy { have[$0.key, default: 0] >= $0.value }
    }

    /// craftGunFromParts
    public static func craft(_ id: String, store: GameStore) -> String {
        guard let g = gun(id) else { return "" }
        if owned(store).contains(id) { return "You already own the \(g.name)." }
        guard canCraft(g, store: store) else { return "Not enough parts to craft the \(g.name)." }
        var have = partCounts(store)
        for (p, n) in g.partCounts { have[p, default: 0] -= n }
        savePartCounts(have, store)
        addOwned(id, store)
        return "You crafted the \(g.name)! Equip it below."
    }

    /// buyGunWithDiamonds
    public static func buy(_ id: String, wallet: Wallet, store: GameStore) -> String {
        guard let g = gun(id) else { return "" }
        if owned(store).contains(id) { return "You already own the \(g.name)." }
        guard wallet.spendDiamonds(g.diamondCost) else {
            return "Not enough diamonds. You need \(g.diamondCost) diamonds to buy the \(g.name)."
        }
        addOwned(id, store)
        return "You bought the \(g.name)! Equip it below."
    }

    /// Gun part drop: 8% of dungeon kills.
    public static func drop(store: GameStore, dice: inout some Dice) -> Part? {
        guard dice.chance(0.08) else { return nil }
        let p = parts[dice.roll(0...(parts.count - 1))]
        addPart(p.id, store: store)
        return p
    }

    /// A shot's damage, with your attack bonus as a percentage like the web version.
    public static func damage(_ g: Gun, atkBonus: Int, dice: inout some Dice) -> Int {
        max(1, jsRound(Double(dice.roll(g.damage)) * (1 + Double(atkBonus) / 100)))
    }

    /// A shot in a dungeon fight: it lands on your target, then the fight
    /// goes on as after any attack (the enemy answers).
    public static func shoot(_ run: inout Run, _ g: Gun, dice: inout some Dice, options: Combat.Options = Combat.Options()) -> TurnResult {
        var r = TurnResult()
        guard run.inCombat, run.enemy != nil else { r.acted = false; return r }
        let dmg = damage(g, atkBonus: run.atkBonus, dice: &dice)
        r.playerDamage = dmg
        r.log.append("🔫 \(g.name) fires! \(dmg) damage!")
        Combat.dealDamage(&run, dmg, log: &r.log)
        return Combat.finishTurn(&run, r, skipEnemy: false, dice: &dice, options: options)
    }
}

/// The gun's charge and reload, shared by every mode like the web version's
/// _gunState: charge (free), shoot until empty, then reload for its seconds.
public struct GunState: Sendable, Equatable {
    public var charged = false
    public var shotsLeft = 0
    /// When the reload ends (seconds since 1970), 0 when not reloading.
    public var reloadUntil = 0.0

    public init() {}

    public func reloading(now: Date = Date()) -> Int {
        max(0, Int((reloadUntil - now.timeIntervalSince1970).rounded(.up)))
    }

    public enum Step: Equatable, Sendable { case charged, fire, reloading(Int) }

    /// What the gun button does now: charge it, fire it, or wait.
    public mutating func pull(_ g: Gun, now: Date = Date()) -> Step {
        let wait = reloading(now: now)
        if wait > 0 { return .reloading(wait) }
        reloadUntil = 0
        if !charged || shotsLeft <= 0 {
            charged = true
            shotsLeft = g.shots
            return .charged
        }
        shotsLeft -= 1
        if shotsLeft <= 0 {
            charged = false
            reloadUntil = now.timeIntervalSince1970 + Double(g.cooldown)
        }
        return .fire
    }

    /// A kill drops the charge with no reload (as in the web version).
    public mutating func reset() {
        charged = false
        shotsLeft = 0
        reloadUntil = 0
    }
}
