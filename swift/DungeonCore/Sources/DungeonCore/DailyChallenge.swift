import Foundation

/// The Daily Challenge (DAILY_CHALLENGES, getDailyChallenge, registerForDC,
/// applyDailyChallenge, checkDailyChallengeCompletion): one of seven
/// modifiers a day, opted into from the Quests screen's Challenge tab. Clear a
/// dungeon while registered for 1 Mystery Coin. Saved in "dd_dc_reg", "dd_dc"
/// and "dd_dc_history" in the web version's shapes.
public enum DailyChallenge {
    public struct Day: Equatable, Sendable {
        public let id: String
        public let name: String
        public let desc: String
        public let effect: String
        /// The red line under the description (effectWarnings).
        public let warning: String
    }

    public static let all: [Day] = [
        Day(id: "dc-iron", name: "Iron Day", desc: "All enemies have 50% more HP.", effect: "ironDay",
            warning: "WARNING: All enemies have 50% more HP."),
        Day(id: "dc-glass", name: "Glass Cannon", desc: "Deal double damage but start with half HP.", effect: "glassCannon",
            warning: "WARNING: You start with half your maximum HP."),
        Day(id: "dc-cursed", name: "Cursed Day", desc: "Potions cannot be used in combat.", effect: "cursedDay",
            warning: "WARNING: Potions cannot be used during combat."),
        Day(id: "dc-blessed", name: "Blessed Day", desc: "Start with 3 potions and 30 extra gold.", effect: "blessedDay",
            warning: "BONUS: Start with 3 potions and 30 extra gold."),
        Day(id: "dc-nightmare", name: "Nightmare Day", desc: "Nightmare enemies invade all floors.", effect: "nightmareDay",
            warning: "WARNING: Nightmare enemies invade all dungeon floors."),
        Day(id: "dc-speed", name: "Speed Run", desc: "Enemies give double XP but hit 25% harder.", effect: "speedRun",
            warning: "MIXED: Double XP gain but enemies hit 25% harder."),
        Day(id: "dc-horde", name: "Horde Day", desc: "Combat chance increased to 70% on all floors.", effect: "hordeDay",
            warning: "WARNING: Combat encounter chance increased to 70%."),
    ]

    /// Today's challenge, by the web version's formula.
    public static func today(_ now: Date = Date(), calendar: Calendar = .current) -> Day {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let i = ((c.year ?? 0) * 365 + ((c.month ?? 1) - 1) * 31 + (c.day ?? 1)) % all.count
        return all[i]
    }

    static func object(_ key: String, _ store: GameStore) -> [String: JSONValue] {
        guard let s = store.getItem(key), let d = s.data(using: .utf8),
              case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: d) else { return [:] }
        return o
    }

    static func put(_ key: String, _ v: JSONValue, _ store: GameStore) {
        if let d = try? JSONEncoder().encode(v), let s = String(data: d, encoding: .utf8) { store.setItem(key, s) }
    }

    public static func isRegistered(_ store: GameStore, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let o = object("dd_dc_reg", store)
        return o["date"] == .string(DailyDescent.key(now, calendar: calendar)) && o["registered"] == .bool(true)
    }

    public static func isCompleted(_ store: GameStore, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        object("dd_dc", store)["completedDate"] == .string(DailyDescent.key(now, calendar: calendar))
    }

    public static func register(_ store: GameStore, now: Date = Date(), calendar: Calendar = .current) {
        put("dd_dc_reg", .object(["date": .string(DailyDescent.key(now, calendar: calendar)), "registered": .bool(true),
                                  "challengeId": .string(today(now, calendar: calendar).id)]), store)
    }

    public static func decline(_ store: GameStore, now: Date = Date(), calendar: Calendar = .current) {
        put("dd_dc_reg", .object(["date": .string(DailyDescent.key(now, calendar: calendar)), "registered": .bool(false),
                                  "challengeId": .string("")]), store)
    }

    public struct Past: Equatable, Sendable {
        public var date: String
        public var name: String
        public var completed: Bool
    }

    /// The last 30 challenges, oldest first.
    public static func history(_ store: GameStore) -> [Past] {
        guard let s = store.getItem("dd_dc_history"), let d = s.data(using: .utf8),
              case .array(let a)? = try? JSONDecoder().decode(JSONValue.self, from: d) else { return [] }
        return a.compactMap {
            guard case .object(let o) = $0, case .string(let name)? = o["name"] else { return nil }
            var date = ""
            if case .string(let s)? = o["date"] { date = s }
            return Past(date: date, name: name, completed: o["completed"] == .bool(true))
        }
    }

    /// Turns today's challenge on for a new run, if you registered for it.
    /// Returns a line for the run log.
    public static func start(_ run: inout Run, store: GameStore, wallet: Wallet,
                             now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard isRegistered(store, now: now, calendar: calendar) else { run.dailyChallenge = nil; return nil }
        let dc = today(now, calendar: calendar)
        run.dailyChallenge = dc.effect
        switch dc.effect {
        case "glassCannon":
            run.hp = max(1, run.maxHp / 2)
            run.maxHp = run.hp
        case "blessedDay":
            run.gold += 30
            wallet.addGold(30)
            for _ in 0..<3 {
                run.inventory.append(Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "Restores 40 HP.", heal: 40))
            }
        default: break
        }
        return "⚡ Daily Challenge: \(dc.name). \(dc.desc) Clear the dungeon for 1 Mystery Coin."
    }

    /// A dungeon cleared while registered: 1 Mystery Coin, once a day.
    /// Returns the challenge it completed.
    @discardableResult
    public static func complete(_ run: Run, store: GameStore, now: Date = Date(), calendar: Calendar = .current) -> Day? {
        guard run.dailyChallenge != nil, isRegistered(store, now: now, calendar: calendar),
              !isCompleted(store, now: now, calendar: calendar) else { return nil }
        let key = DailyDescent.key(now, calendar: calendar)
        let dc = today(now, calendar: calendar)
        put("dd_dc", .object(["completedDate": .string(key)]), store)
        Spire.addCoins(1, store: store)
        var list: [JSONValue] = history(store).map {
            .object(["date": .string($0.date), "name": .string($0.name), "completed": .bool($0.completed)])
        }
        list.append(.object(["date": .string(key), "name": .string(dc.name), "completed": .bool(true)]))
        put("dd_dc_history", .array(Array(list.suffix(30))), store)
        return dc
    }

    static func on(_ run: Run, _ effect: String) -> Bool { run.dailyChallenge == effect }

    /// Iron Day: enemies have 50% more HP.
    static func shape(_ e: inout Enemy, _ run: Run) {
        guard on(run, "ironDay") else { return }
        e.hp = jsRound(Double(e.hp) * 1.5)
        e.maxHp = e.hp
    }

    /// Glass Cannon: double damage.
    static func attackMult(_ run: Run) -> Double { on(run, "glassCannon") ? 2 : 1 }
    /// Speed Run: double XP.
    static func xpMult(_ run: Run) -> Double { on(run, "speedRun") ? 2 : 1 }
    /// Speed Run: enemies hit 25% harder (the web version said so and never did it).
    static func enemyMult(_ run: Run) -> Double { on(run, "speedRun") ? 1.25 : 1 }
    /// Cursed Day: no potions in a fight (the web version said so and never did it).
    static func blocksPotions(_ run: Run) -> Bool { on(run, "cursedDay") && run.inCombat }
    /// Horde Day: fights in 70% of rooms instead of the difficulty's odds.
    static func combatBonus(_ run: Run) -> Double { on(run, "hordeDay") ? 0.70 - Rooms.combatChance(run.difficulty) : 0 }

    /// Nightmare Day: 30% of fights are a Nightmare enemy (tier 1 or 2), its HP
    /// grown by floor like the web version's.
    static func nightmareEnemy(for run: Run, dice: inout some Dice) -> Enemy? {
        guard on(run, "nightmareDay"), let n = GameContent.shared.nightmareEnemies, dice.chance(0.30) else { return nil }
        let pool = n.t1 + n.t2
        guard !pool.isEmpty else { return nil }
        let t = pool[dice.roll(0...(pool.count - 1))]
        let hp = jsRound(Double(t.hp) * (1 + Double(run.floor - 1) * 0.09))
        var e = Enemy(name: t.name, icon: t.icon, hp: hp, maxHp: hp, atk: t.atk, gold: t.gold)
        e.mechanics = t.mechanics
        if case .string(let a)? = t.mechanics["ability"] { e.desc = a } else { e.desc = t.desc }
        return e
    }
}
