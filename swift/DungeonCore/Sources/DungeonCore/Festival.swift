import Foundation

/// The v11.8 events (js/26-events-11-8.js): nine more days on the calendar.
///
///  🌼 Día de los Muertos (Nov 1–2) — a fallen hero fights beside you; Marigolds and the Ofrenda
///  🇲🇽 Independencia de México (Sep 15–16) — ¡El Grito!: +30% attack for 3 turns, once a fight
///  🎆 New Year (Dec 31–Jan 1) — double XP
///  🐉 Lunar New Year (three days, by the lunar calendar) — red envelopes
///  🃏 Chaos Day (Apr 1) — every fight rolls a random twist
///  🌑 The Longest Night (Dec 21) — night all day
///  🌘 The Eclipse (one evening a month, 18:00–22:00 UTC, the same for everyone)
///  🏮 Night Market (first weekend of the month) — the merchant comes often, 25% off
///  🐾 Monster Migration (two days a month) — enemies from the other dungeons
public enum Festival {
    public static let ids: Set<String> = ["muertos", "mexico", "newyear", "lunar", "chaos", "longestnight", "eclipse", "nightmarket", "migration"]

    /// The first day of the lunar new year, and its animal.
    static let lunarNewYear: [Int: (month: Int, day: Int, animal: String, icon: String)] = [
        2025: (1, 29, "Snake", "🐍"), 2026: (2, 17, "Horse", "🐴"), 2027: (2, 6, "Goat", "🐐"),
        2028: (1, 26, "Monkey", "🐒"), 2029: (2, 13, "Rooster", "🐓"), 2030: (2, 3, "Dog", "🐕"),
        2031: (1, 23, "Pig", "🐖"), 2032: (2, 11, "Rat", "🐀"), 2033: (1, 31, "Ox", "🐂"),
        2034: (2, 19, "Tiger", "🐅"), 2035: (2, 8, "Rabbit", "🐇"),
    ]

    public static func eclipseDay(year: Int, month: Int) -> Int { ((year * 12 + month) * 7) % 26 + 2 }

    public static func migrationDay(year: Int, month: Int) -> Int {
        let d = ((year * 31 + month * 11) % 24) + 3
        let e = eclipseDay(year: year, month: month)
        return abs(d - e) < 2 ? ((d + 5 - 1) % 26) + 2 : d
    }

    /// The dated events, which come before every other event.
    static func dated(_ date: Date) -> String? {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents(in: .current, from: date)
        guard let month = c.month, let day = c.day, let year = c.year else { return nil }
        if month == 11 && day <= 2 { return "muertos" }
        if month == 9 && (day == 15 || day == 16) { return "mexico" }
        if (month == 12 && day == 31) || (month == 1 && day == 1) { return "newyear" }
        if let l = lunarNewYear[year], let start = cal.date(from: DateComponents(year: year, month: l.month, day: l.day)),
           let end = cal.date(byAdding: .day, value: 3, to: start), date >= start && date < end { return "lunar" }
        if month == 4 && day == 1 { return "chaos" }
        if month == 12 && day == 21 { return "longestnight" }
        return nil
    }

    /// The monthly ones only take a day no other dated event wants.
    static func recurring(_ date: Date) -> String? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let u = utc.dateComponents([.year, .month, .day, .hour], from: date)
        if let y = u.year, let m = u.month, let d = u.day, let h = u.hour,
           d == eclipseDay(year: y, month: m) && h >= 18 && h < 22 { return "eclipse" }
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        guard let year = c.year, let month = c.month, let day = c.day, let weekday = c.weekday else { return nil }
        let md = migrationDay(year: year, month: month)
        if day == md || day == md + 1 { return "migration" }
        if day <= 7 && (weekday == 7 || weekday == 1) { return "nightmarket" }
        return nil
    }

    static let weekly: Set<String> = ["xpweekend", "voidweek", "bloodmoon", "architect"]

    static func bonuses(_ id: String) -> Events.Bonuses? {
        switch id {
        case "muertos": return Events.Bonuses(id: id, label: "🌼 Día de los Muertos", xpMult: 1.30, enemyMult: 1.10, goldMult: 1.20,
                                              currency: Events.Currency(key: "marigolds", icon: "🌼", name: "Marigolds", shop: "🌼 The Ofrenda"))
        case "mexico": return Events.Bonuses(id: id, label: "🇲🇽 Independencia de México", xpMult: 1.30, enemyMult: 1.10, goldMult: 1.16)
        case "newyear": return Events.Bonuses(id: id, label: "🎆 New Year", xpMult: 2.00, goldMult: 1.20)
        case "lunar":
            let year = Calendar(identifier: .gregorian).component(.year, from: Date())
            let animal = lunarNewYear[year].map { " — Year of the \($0.animal)" } ?? ""
            return Events.Bonuses(id: id, label: "🐉 Lunar New Year" + animal, xpMult: 1.40, enemyMult: 1.10, goldMult: 1.28)
        case "chaos": return Events.Bonuses(id: id, label: "🃏 Chaos Day", xpMult: 1.25, goldMult: 1.25)
        case "longestnight": return Events.Bonuses(id: id, label: "🌑 The Longest Night", xpMult: 1.30, enemyMult: 1.20, goldMult: 1.10)
        case "eclipse": return Events.Bonuses(id: id, label: "🌘 The Eclipse", xpMult: 1.50, enemyMult: 1.30, goldMult: 2.00)
        case "nightmarket": return Events.Bonuses(id: id, label: "🏮 Night Market", xpMult: 1.10, goldMult: 1.10)
        case "migration": return Events.Bonuses(id: id, label: "🐾 Monster Migration", xpMult: 1.25, enemyMult: 1.05)
        default: return nil
        }
    }

    // MARK: Hooks

    /// The Longest Night: night all day.
    public static func isNight(event: String? = Events.active()) -> Bool { event == "longestnight" }

    /// The shop's 25% off: night time, or the Night Market.
    public static func shopDiscount(event: String?) -> Bool { event == "nightmarket" || event == "longestnight" }

    /// The Night Market: the merchant comes 4 times as often.
    public static func merchantChance(_ run: Run, _ base: Double) -> Double { run.event == "nightmarket" ? 0.25 : base }

    /// Monster Migration: the other dungeons' enemies at this floor's tier.
    static func migrants(_ run: Run) -> [EnemyTemplate] {
        TrueEnding.dungeons.filter { $0 != run.dungeon }.flatMap { d -> [EnemyTemplate] in
            Bestiary.enemies(for: d).pool(forFloor: run.floor).map { t in
                var m = t
                m.desc = (t.desc ?? "") + " (Wandered in from \(d).)"
                m.mechanics["migrant"] = .bool(true)
                return m
            }
        }
    }

    /// Día de los Muertos: a hero from The Graveyard, picked at the start of a run.
    public static func ghost(store: GameStore, dice: inout some Dice) -> Enemy? {
        guard let raw = store.getItem("dd_graveyard"), let d = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([JSONValue].self, from: d), !list.isEmpty,
              case .object(let o) = list[dice.roll(0...(list.count - 1))] else { return nil }
        var name = "a fallen hero", cls = "", lvl = 1
        if case .string(let s)? = o["name"], !s.isEmpty { name = s }
        if case .string(let s)? = o["cls"] { cls = s }
        if case .number(let n)? = o["level"] { lvl = max(1, Int(n)) }
        var g = Enemy(name: "ghost of \(name)", icon: "🌼", hp: 1, maxHp: 1, atk: (3 + lvl)...(7 + lvl * 2), gold: 0...0)
        g.mechanics["ghost"] = .bool(true)
        g.mechanics["cls"] = .string(cls)
        return g
    }

    /// The start of every fight: the ghost ally, and Chaos Day's twist.
    static func combatStart(_ run: inout Run, log: inout [String]) {
        guard var e = run.enemy else { return }
        if run.event == "muertos", run.fight.ally == nil, let g = run.festivalGhost {
            run.fight.ally = g
            let cls: String = { if case .string(let c)? = g.mechanics["cls"], !c.isEmpty { return " the \(c)" }; return "" }()
            log.append("🌼 The \(g.name)\(cls) returns to fight beside you.")
        }
        if run.event == "chaos" {
            var dice = SystemDice()
            let msg: String
            switch dice.roll(0...4) {
            case 0:
                e.hp = max(1, jsRound(Double(e.hp) * 0.5)); e.maxHp = e.hp
                msg = "It forgot half its HP at home."
            case 1:
                let lo = max(1, jsRound(Double(e.atk.lowerBound) * 1.5)), hi = max(2, jsRound(Double(e.atk.upperBound) * 1.5))
                e.atk = lo...max(lo, hi)
                e.gold = (e.gold.lowerBound * 3)...(e.gold.upperBound * 3)
                msg = "It hits 50% harder — and carries triple gold."
            case 2:
                run.markedKill = true
                msg = "It trips. Your first strike is a critical."
            case 3:
                e.stunTurns = max(e.stunTurns, 1)
                msg = "It is laughing too hard to attack this turn."
            default:
                let names = ["Sir Wobbles", "The Unimpressed", "Gerald", "Definitely Not A Mimic", "Mr. Bones Jr."]
                e.name = names[dice.roll(0...(names.count - 1))] + " (\(e.name))"
                msg = "It insists on a new name."
            }
            run.enemy = e
            log.append("🃏 Chaos Day: " + msg)
        }
    }

    /// After a kill: red envelopes, and the migrants' bonus XP.
    public struct KillBonus: Equatable, Sendable {
        public var gold = 0
        public var xp = 0
        public var mysteryCoin = false
        public var note = ""
    }

    static func onKill(_ run: inout Run, _ e: Enemy, dice: inout some Dice) -> KillBonus {
        var b = KillBonus()
        if run.event == "lunar" && dice.chance(0.15) {
            if dice.chance(0.15) {
                b.mysteryCoin = true
                b.note = " 🧧 A red envelope! It holds a Mystery Coin."
            } else {
                b.gold = dice.roll(20...60)
                b.note = " 🧧 A red envelope! \(b.gold) gold inside."
            }
        }
        if run.event == "migration" && e.flag("migrant") {
            b.xp = 15
            b.note += " 🐾 A wanderer from another dungeon — +15 XP."
        }
        return b
    }

    /// ¡El Grito!: once a fight, +30% attack for 3 turns. It doesn't use your turn.
    public static func canGrito(_ run: Run) -> Bool { run.event == "mexico" && run.inCombat && run.enemy != nil }

    public static func grito(_ run: inout Run) -> String {
        guard canGrito(run) else { return "" }
        guard !run.fight.gritoUsed else { return "You already gave your grito this fight." }
        run.fight.gritoUsed = true
        let base = (run.atk.lowerBound + run.atk.upperBound) / 2 + run.atkBonus
        let add = max(2, jsRound(Double(base) * 0.3))
        run.fight.buffAtk = add
        run.fight.buffDef = 0
        run.fight.buffTurns = 3
        return "🇲🇽 ¡VIVA MÉXICO! Your grito echoes through the dungeon — +\(add) attack for 3 turns!"
    }
}

extension Events {
    /// getActiveEvent: the v11.8 dated events first, then the others; the
    /// monthly ones only on a day nothing else (but a weekly event) wants.
    public static func active(on date: Date = Date()) -> String? {
        if let n = Festival.dated(date) { return n }
        let base = baseActive(on: date)
        if let base, !Festival.weekly.contains(base) { return base }
        return Festival.recurring(date) ?? base
    }
}
