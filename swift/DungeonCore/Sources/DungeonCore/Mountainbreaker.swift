import Foundation

/// 12.2: The Mountainbreaker, the Mine's legendary warhammer. Forged at the
/// Blacksmith from 5 Heartstone Shards: every Mine boss from depth 100 down
/// drops one, and below depth 50 you sometimes dig one up.
///
/// - Quake: every 3rd hit in a fight shakes the ground for double damage,
///   and the enemy (and the rest of an ambush) loses its next turn.
/// - Stone Memory: +1 damage for every 25 kills with it, up to +10.
public enum Mountainbreaker {
    public static let id = "mountainbreaker"
    public static let shardsNeeded = 5
    public static let storeKey = "swift_heartstones"
    static let forgedKey = "swift_mountainbreaker_forged"
    public static let maxMemory = 10
    public static let killsPerPoint = 25

    public static let shard = MineItem("Heartstone Shard", "🔶", "mine-heartstone", weight: 1)

    public static var weapon: Item {
        var w = Item(id: id, name: "Mountainbreaker", icon: "🔨", type: "weapon",
                     desc: "A warhammer forged from the heart of the mountain. Every third hit is a Quake: double damage, and the enemy loses its next turn. It remembers every kill: +1 damage for every 25, up to +10.",
                     atkBase: [17, 25], weaponType: "hammer")
        w.extra["legendary"] = .bool(true)
        return w
    }

    public static func isIt(_ i: Item?) -> Bool { i?.id == id }

    // MARK: Shards and forging

    public static func shards(_ store: GameStore) -> Int { Int(store.getItem(storeKey) ?? "") ?? 0 }

    public static func addShards(_ n: Int, store: GameStore) {
        guard n > 0 else { return }
        store.setItem(storeKey, String(shards(store) + n))
    }

    public static func forged(_ store: GameStore) -> Bool { store.getItem(forgedKey) == "1" }

    /// Forges it, once: into your saved items from the menu, or into the
    /// bag you're carrying in a run (`bag`), which the run saves.
    public static func forge(store: GameStore, bag: inout [Item]?) -> (ok: Bool, message: String) {
        guard !forged(store) else { return (false, "You already forged the Mountainbreaker. There is only one.") }
        let have = shards(store)
        guard have >= shardsNeeded else {
            return (false, "The Blacksmith needs \(shardsNeeded) Heartstone Shards. You have \(have). Mine bosses from depth 100 drop them, and below depth 50 you can dig them up.")
        }
        store.setItem(storeKey, String(have - shardsNeeded))
        store.setItem(forgedKey, "1")
        if bag != nil { bag?.append(weapon) } else { GlobalInventory(store: store).add(weapon) }
        return (true, "🔨 The Blacksmith works through the night. The shards glow, melt and ring like a bell. The Mountainbreaker is yours. Equip it from your items.")
    }

    public static func forge(store: GameStore) -> String {
        var none: [Item]? = nil
        return forge(store: store, bag: &none).message
    }

    // MARK: In a fight

    public static func memory(_ w: Item?) -> Int {
        guard let w, isIt(w), case .number(let k)? = w.extra["stoneKills"] else { return 0 }
        return min(maxMemory, Int(k) / killsPerPoint)
    }

    /// Every hit: Stone Memory, and the Quake on every 3rd.
    static func onHit(_ run: inout Run, _ dmg: Int, log: inout [String]) -> Int {
        guard isIt(run.equippedWeapon), dmg > 0 else { return dmg }
        var d = dmg + memory(run.equippedWeapon)
        let n = (run.fight.quakeHits ?? 0) + 1
        run.fight.quakeHits = n
        if n % 3 == 0 {
            d *= 2
            if var e = run.enemy { e.stunTurns = max(e.stunTurns, 1); run.enemy = e }
            for i in run.foes.indices { run.foes[i].stunTurns = max(run.foes[i].stunTurns, 1) }
            log.append("🔨 QUAKE! The ground splits. Double damage, and " + (run.foes.isEmpty ? "the enemy loses its next turn." : "every enemy loses its next turn."))
        }
        return d
    }

    /// A kill with it: Stone Memory grows.
    static func onKill(_ run: inout Run, log: inout [String]) {
        guard var w = run.equippedWeapon, isIt(w) else { return }
        let before = memory(w)
        var k = 0.0
        if case .number(let n)? = w.extra["stoneKills"] { k = n }
        w.extra["stoneKills"] = .number(k + 1)
        run.equippedWeapon = w
        let after = memory(w)
        if after > before { log.append("🔨 The Mountainbreaker remembers. Stone Memory +\(after) damage.") }
    }
}
