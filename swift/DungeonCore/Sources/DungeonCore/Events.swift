import Foundation

/// Seasonal and weekly events (getActiveEvent / getEventBonuses): bonuses,
/// exclusive enemies, seasonal currency and the seasonal shops.
public enum Events {
    public struct Bonuses: Sendable, Equatable {
        public let id: String
        public let label: String
        public var xpMult = 1.0
        public var enemyMult = 1.0
        public var goldMult = 1.0
        /// Blood Moon: you hit 25% harder and take 25% more.
        public var atkBoost = 0.0
        public var takesMore = 0.0
        public var currency: Currency? = nil
    }

    public struct Currency: Sendable, Equatable {
        public let key, icon, name, shop: String
    }

    public struct ListEntry: Decodable, Sendable { public let id, title, desc, bonuses, dates: String }
    public struct ShopItem: Decodable, Sendable { public let id, name, icon, desc: String; public let cost: Int }

    struct Data: Decodable {
        let enemies: [String: [JSONValue]]
        let shops: [String: [ShopItem]]
        let list: [ListEntry]
    }

    static let data: Data? = {
        guard let url = Bundle.module.url(forResource: "events", withExtension: "json"),
              let d = try? Foundation.Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Data.self, from: d)
    }()

    /// The Events screen's list, in the web version's order.
    public static var list: [ListEntry] { data?.list ?? [] }

    // MARK: Which event

    static var calendar: Calendar { Calendar(identifier: .gregorian) }

    /// Easter Sunday (anonymous Gregorian algorithm).
    public static func easter(_ year: Int) -> DateComponents {
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = (h + l - 7 * m + 114) % 31 + 1
        return DateComponents(year: year, month: month, day: day)
    }

    /// getActiveEvent: the event running on this day, if any.
    public static func active(on date: Date = Date()) -> String? {
        let cal = calendar
        let c = cal.dateComponents(in: .current, from: date)
        guard let month = c.month, let day = c.day, let year = c.year, let weekday = c.weekday else { return nil }
        let dow = weekday - 1 // 0 = Sunday, like getDay()
        if month == 10 { return "halloween" }
        if month == 11 && day <= 2 { return "halloween" }
        if month == 12 { return "christmas" }
        if let e = cal.date(from: easter(year)), let end = cal.date(byAdding: .day, value: 3, to: e),
           date >= e && date < end { return "easter" }
        if month == 11 && (22...28).contains(day) { return "thanksgiving" }
        if month == 3 && (14...18).contains(day) { return "stpatricks" }
        if month == 3 && day == 23 { return "birthday" }
        if month == 5 && day == 5 { return "cincodemayo" }
        if month == 9 && day == 7 { return "brazil" }
        if month == 2 && (13...15).contains(day) { return "valentines" }
        if day == 13 && dow == 5 { return "friday13" }
        if month == 7 && (1...7).contains(day) { return "july4" }
        if day == 15 && [1, 4, 7, 10].contains(month) { return "ambushday" }
        if dow == 6 || dow == 0 { return "xpweekend" }
        if dow == 1 { return "voidweek" }
        if day <= 7 && month != 10 && month != 12 { return "bloodmoon" }
        if (8...14).contains(day) && month != 10 && month != 12 { return "architect" }
        return nil
    }

    /// getEventBonuses
    public static func bonuses(_ id: String?) -> Bonuses? {
        func c(_ key: String, _ icon: String, _ name: String, _ shop: String) -> Currency { Currency(key: key, icon: icon, name: name, shop: shop) }
        switch id {
        case "halloween": return Bonuses(id: "halloween", label: "🎃 Halloween", xpMult: 1.25, enemyMult: 1.30, currency: c("demonCoins", "🪙", "Demon Coins", "💀 Curse Shop"))
        case "christmas": return Bonuses(id: "christmas", label: "🎄 Christmas", xpMult: 1.15, enemyMult: 1.20, currency: c("christmasCookies", "🍪", "Christmas Cookies", "🎅 Santa Shop"))
        case "thanksgiving": return Bonuses(id: "thanksgiving", label: "🦃 Thanksgiving", xpMult: 1.20, enemyMult: 1.15, currency: c("harvestTokens", "🌽", "Harvest Tokens", "🌽 Harvest Market"))
        case "cincodemayo": return Bonuses(id: "cincodemayo", label: "🌮 Cinco de Mayo", xpMult: 1.50, goldMult: 1.25)
        case "july4": return Bonuses(id: "july4", label: "🎆 Fourth of July", xpMult: 1.76, enemyMult: 1.10, goldMult: 1.76, currency: c("libertyCoins", "🗽", "Liberty Coins", "🗽 Liberty Shop"))
        case "ambushday": return Bonuses(id: "ambushday", label: "⚔️ Ambush Day", xpMult: 1.50, enemyMult: 1.25, goldMult: 1.5)
        case "xpweekend": return Bonuses(id: "xpweekend", label: "⚡ XP Weekend", xpMult: 2.00)
        case "voidweek": return Bonuses(id: "voidweek", label: "🌑 Void Week", xpMult: 1.10, enemyMult: 1.20, goldMult: 2.0)
        case "bloodmoon": return Bonuses(id: "bloodmoon", label: "🔴 Blood Moon", enemyMult: 1.25, atkBoost: 0.25, takesMore: 0.25)
        case "architect": return Bonuses(id: "architect", label: "🏛️ Architect Week", xpMult: 1.20, enemyMult: 1.10)
        case "brazil": return Bonuses(id: "brazil", label: "🟢 Independencia do Brasil", xpMult: 1.50, enemyMult: 1.10, goldMult: 1.822)
        case "valentines": return Bonuses(id: "valentines", label: "💘 Valentine's Day", xpMult: 1.25, enemyMult: 1.05, goldMult: 1.14, currency: c("chocolate", "🍫", "Chocolate", "🍫 Chocolate Shop"))
        case "friday13": return Bonuses(id: "friday13", label: "🔪 Friday the 13th", enemyMult: 1.30, goldMult: 0.75)
        case "stpatricks": return Bonuses(id: "stpatricks", label: "☘️ St. Patrick's Day", xpMult: 1.30, enemyMult: 1.15, goldMult: 1.50, currency: c("shamrocks", "☘️", "Shamrocks", "☘️ Shamrock Shop"))
        case "easter": return Bonuses(id: "easter", label: "🐰 Easter", xpMult: 1.50, enemyMult: 0.80)
        default: return nil
        }
    }

    public static func current(on date: Date = Date()) -> Bonuses? { bonuses(active(on: date)) }

    /// getEventHoursRemaining
    public static func hoursRemaining(on now: Date = Date()) -> Int {
        let cal = calendar
        guard let ev = active(on: now) else { return 0 }
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: now)
        guard let year = c.year, let month = c.month, let weekday = c.weekday else { return 0 }
        func at(_ m: Int, _ d: Int) -> Date? { cal.date(from: DateComponents(year: year, month: m, day: d, hour: 23, minute: 59, second: 59)) }
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now)
        var end: Date?
        switch ev {
        case "halloween": end = cal.date(from: DateComponents(year: year, month: 11, day: 3))
        case "christmas": end = at(12, 31)
        case "easter":
            end = cal.date(from: easter(year)).flatMap { cal.date(byAdding: .day, value: 2, to: $0) }
                .flatMap { cal.date(bySettingHour: 23, minute: 59, second: 59, of: $0) }
        case "july4": end = at(7, 7)
        case "stpatricks": end = at(3, 18)
        case "birthday": end = at(3, 23)
        case "cincodemayo": end = at(5, 5)
        case "thanksgiving": end = at(11, 28)
        case "xpweekend": end = endOfToday.flatMap { cal.date(byAdding: .day, value: weekday == 1 ? 0 : 1, to: $0) }
        case "bloodmoon": end = at(month, 7)
        case "architect": end = at(month, 14)
        default: end = endOfToday // Void Week, Ambush Day and the one-day events
        }
        guard let end else { return 0 }
        return max(0, Int((end.timeIntervalSince(now) / 3600).rounded(.up)))
    }

    /// updateMenuEventBanner: the running event with its time left, plus any
    /// weekly event that also falls on this day.
    public static func bannerLines(on now: Date = Date()) -> [String] {
        var lines: [String] = []
        let ev = active(on: now)
        func left(_ hrs: Int, days: Bool) -> String { days && hrs >= 24 ? "\(hrs / 24)d \(hrs % 24)h remaining" : "\(hrs)h remaining" }
        if let b = bonuses(ev) {
            let hrs = hoursRemaining(on: now)
            if hrs > 0 { lines.append("\(b.label) · ACTIVE · \(left(hrs, days: true))") }
        }
        let cal = calendar
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: now)
        guard let year = c.year, let month = c.month, let day = c.day, let weekday = c.weekday else { return lines }
        let dow = weekday - 1
        func hours(to end: Date?) -> Int { end.map { max(0, Int(($0.timeIntervalSince(now) / 3600).rounded(.up))) } ?? 0 }
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now)
        if ev != "xpweekend" && (dow == 6 || dow == 0) {
            let h = hours(to: endOfToday.flatMap { cal.date(byAdding: .day, value: dow == 0 ? 0 : 1, to: $0) })
            if h > 0 { lines.append("⚡ XP Weekend · ACTIVE · \(h)h remaining") }
        }
        if ev != "voidweek" && dow == 1 {
            let h = hours(to: endOfToday)
            if h > 0 { lines.append("🌑 Void Week · ACTIVE · \(h)h remaining") }
        }
        if ev != "bloodmoon" && day <= 7 && month != 10 && month != 12 {
            let h = hours(to: cal.date(from: DateComponents(year: year, month: month, day: 7, hour: 23, minute: 59, second: 59)))
            if h > 0 { lines.append("🔴 Blood Moon · ACTIVE · \(left(h, days: true))") }
        }
        if ev != "architect" && (8...14).contains(day) && month != 10 && month != 12 {
            let h = hours(to: cal.date(from: DateComponents(year: year, month: month, day: 14, hour: 23, minute: 59, second: 59)))
            if h > 0 { lines.append("🏛️ Architect Week · ACTIVE · \(left(h, days: true))") }
        }
        return lines
    }

    /// Days until the event next starts (0 when it's running).
    public static func daysUntil(_ id: String, from now: Date = Date()) -> Int {
        for d in 0...800 {
            if let day = calendar.date(byAdding: .day, value: d, to: now), active(on: day) == id { return d }
        }
        return 0
    }

    /// Days left after today while the event runs.
    public static func daysLeft(_ id: String, from now: Date = Date()) -> Int {
        var n = 0
        while n < 60, let day = calendar.date(byAdding: .day, value: n + 1, to: now), active(on: day) == id { n += 1 }
        return n
    }

    // MARK: Enemies

    /// The event's exclusive enemies (bosses are left out, as in the web version).
    public static func enemies(_ id: String?) -> [EnemyTemplate] {
        guard let id, let raw = data?.enemies[id] else { return [] }
        return raw.compactMap { v -> EnemyTemplate? in
            guard case .object(let o) = v, o["isBoss"] != .bool(true),
                  let d = try? JSONEncoder().encode(v) else { return nil }
            return try? JSONDecoder().decode(EnemyTemplate.self, from: d)
        }
    }

    /// 20% of normal enemies are replaced by one of the event's own, scaled by
    /// the event's enemy strength (and New Game+), not by floor.
    static func seasonalEnemy(_ run: Run, dice: inout some Dice) -> Enemy? {
        guard let b = bonuses(run.event) else { return nil }
        let pool = enemies(b.id)
        guard !pool.isEmpty, dice.chance(0.20) else { return nil }
        let t = pool[dice.roll(0...(pool.count - 1))]
        let m = b.enemyMult * (run.ngPlus ? 1.20 : 1.0)
        let hp = jsRound(Double(t.hp) * m)
        let lo = jsRound(Double(t.atk.lowerBound) * m), hi = jsRound(Double(t.atk.upperBound) * m)
        var e = Enemy(name: t.name, icon: t.icon, hp: hp, maxHp: hp, atk: lo...max(lo, hi), gold: t.gold)
        e.desc = t.desc
        e.mechanics["seasonal"] = .string(b.label)
        return e
    }

    // MARK: Seasonal currency

    public static func currency(_ key: String, store: GameStore) -> Int {
        Int(store.getItem("dd_sc_" + key) ?? "0") ?? 0
    }

    public static func addCurrency(_ key: String, _ n: Int, store: GameStore) {
        store.setItem("dd_sc_" + key, String(currency(key, store: store) + n))
    }

    /// awardSeasonalCurrencyOnKill: 30% of kills give one coin.
    public static func awardOnKill(_ run: Run, store: GameStore, dice: inout some Dice) -> Currency? {
        guard let cur = bonuses(run.event)?.currency, dice.chance(0.30) else { return nil }
        addCurrency(cur.key, 1, store: store)
        return cur
    }

    // MARK: Seasonal shop

    public static func shop(_ key: String) -> [ShopItem] { data?.shops[key] ?? [] }

    /// Items whose effect the Swift version doesn't have yet.
    public static func comingSoon(_ id: String) -> Bool {
        ["liberty-title", "stpat-title", "val-title"].contains(id)
    }

    /// Pending boosts for the next run, saved by the seasonal shops.
    public struct NextRun: Codable, Sendable, Equatable {
        public var bonusLives = 0
        public var xpMult = 1.0
        public var xpFloors = 0
        public var spiritBoost = false
        public var sparkler = false
        public var luckKills = 0
        /// Potions bought from a seasonal shop, put in the bag when the run starts.
        public var items: [Item] = []
        /// The Curse Shop's Cursed Modifier: a run modifier on the next run.
        public var cursedModifier = false
        public init() {}

        // Saves from before a field existed still load.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            bonusLives = try c.decodeIfPresent(Int.self, forKey: .bonusLives) ?? 0
            xpMult = try c.decodeIfPresent(Double.self, forKey: .xpMult) ?? 1
            xpFloors = try c.decodeIfPresent(Int.self, forKey: .xpFloors) ?? 0
            spiritBoost = try c.decodeIfPresent(Bool.self, forKey: .spiritBoost) ?? false
            sparkler = try c.decodeIfPresent(Bool.self, forKey: .sparkler) ?? false
            luckKills = try c.decodeIfPresent(Int.self, forKey: .luckKills) ?? 0
            items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
            cursedModifier = try c.decodeIfPresent(Bool.self, forKey: .cursedModifier) ?? false
        }
    }

    public static func nextRun(_ store: GameStore) -> NextRun {
        guard let s = store.getItem("dd_event_next_run"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode(NextRun.self, from: d) else { return NextRun() }
        return v
    }

    public static func saveNextRun(_ v: NextRun, _ store: GameStore) {
        if let d = try? JSONEncoder().encode(v), let s = String(data: d, encoding: .utf8) { store.setItem("dd_event_next_run", s) }
    }

    /// buySeasonalItem: spends the currency and applies the item. Returns
    /// the line to show and read, or nil when it couldn't be bought.
    public static func buy(_ item: ShopItem, currency key: String, store: GameStore, wallet: Wallet,
                           now: Date = Date()) -> String? {
        guard !comingSoon(item.id), currency(key, store: store) >= item.cost else { return nil }
        store.setItem("dd_sc_" + key, String(currency(key, store: store) - item.cost))
        var next = nextRun(store)
        func potion(_ name: String, _ icon: String, _ heal: Int, _ desc: String) -> String {
            next.items.append(Item(name: name, icon: icon, type: "potion", desc: desc, heal: heal))
            return "\(name) will be in your bag when your next run starts."
        }
        func xp(_ mult: Double, _ floors: Int) -> String {
            next.xpMult = max(next.xpMult, mult)
            next.xpFloors += floors
            return "\(mult == 3 ? "Triple" : "Double") XP for your next \(floors) floors activated."
        }
        let msg: String
        switch item.id {
        case "bs-discount-code", "santa-bs-discount":
            let pct = item.id == "bs-discount-code" ? 0.10 : 0.15
            let exp = (now.timeIntervalSince1970 + 86400) * 1000
            store.setItem("dd_blacksmith_discount", "{\"pct\":\(pct),\"expires\":\(Int(exp)),\"source\":\"\(item.id == "bs-discount-code" ? "Curse Shop" : "Santa Shop")\"}")
            msg = "Blacksmith discount applied. \(Int(pct * 100))% off for 24 hours."
        case "double-xp-potion": msg = xp(2, 3)
        case "santa-xp-boost": msg = xp(3, 2)
        case "liberty-xp": msg = xp(2, 7)
        case "harvest-xp": msg = xp(2, 5)
        case "demon-revival": next.bonusLives += 1; msg = "One bonus life granted for your next run."
        case "halloween-potion": msg = potion("Pumpkin Brew", "🎃", 80, "Halloween brew. Heals 80 HP.")
        case "santa-potion": msg = potion("Eggnog Flask", "🥛", 60, "Heals 60 HP and 10 SP.")
        case "harvest-potion": msg = potion("Harvest Brew", "🍂", 70, "Heals 70 HP.")
        case "val-chocolate-box": msg = potion("Box of Chocolates", "🍫", 55, "Heals 55 HP.")
        case "santa-bonus-gold": wallet.addGold(150); msg = "150 gold received from Santa."
        case "liberty-gold": wallet.addGold(300); msg = "300 gold received from the Liberty Treasury."
        case "harvest-gold": wallet.addGold(200); msg = "200 gold received from the harvest."
        case "stpat-pot": wallet.addGold(300); msg = "Pot of Gold! 300 gold gained."
        case "santa-spirit-boost": next.spiritBoost = true; msg = "Elf blessing applied. Spirit deals double damage next run."
        case "liberty-sparkler": next.sparkler = true; msg = "Sparkler buff activated. Plus 30 percent attack for your next run."
        case "stpat-clover": next.luckKills += 30; msg = "Lucky Clover active. Double gold drops for your next 30 kills."
        case "liberty-eagle":
            var list = Home.minions(store)
            if !list.contains(where: { $0.id == "liberty_eagle" }) {
                list.append(Minion(id: "liberty_eagle", name: "Liberty Eagle", icon: "🦅", atk: 8, tier: "common",
                                   capturedOn: (now.timeIntervalSince1970 * 1000).rounded()))
                Home.saveMinions(list, store)
            }
            msg = "Liberty Eagle joins your cause. Find it in your Home under Minions."
        // The web version sold it and never applied it.
        case let id where SeasonalItems.all[id] != nil:
            next.items.append(SeasonalItems.all[id]!)
            msg = "\(item.name) will be in your bag when your next run starts."
        case "cursed-run-mod":
            next.cursedModifier = true
            msg = "💀 A curse settles on your next run. A random run modifier will take hold."
        default: msg = "\(item.name) bought."
        }
        saveNextRun(next, store)
        return msg
    }

    /// At run start: the shop boosts bought for this run. Returns log lines.
    public static func applyNextRun(_ run: inout Run, store: GameStore) -> [String] {
        let n = nextRun(store)
        guard n != NextRun() else { return [] }
        var log: [String] = []
        if n.bonusLives > 0 { run.lives += n.bonusLives; run.maxLives += n.bonusLives; log.append("😈 Demon Revival: +\(n.bonusLives) life this run.") }
        if n.xpFloors > 0 { run.xpBoostMult = n.xpMult; run.xpBoostFloors = n.xpFloors; log.append("🧪 \(n.xpMult == 3 ? "Triple" : "Double") XP for \(n.xpFloors) floors.") }
        if n.spiritBoost { run.spiritBoost = true; log.append("🌟 Elf Blessing: your spirit deals double damage this run.") }
        if n.sparkler { run.sparkler = true; log.append("✨ Sparkler: +30% attack this run.") }
        if n.cursedModifier { run.cursedModifier = true; log.append("💀 Cursed Modifier: a run modifier takes hold of this run.") }
        if n.luckKills > 0 { run.luckKills += n.luckKills; log.append("🍀 Lucky Clover: double gold for \(n.luckKills) kills.") }
        if !n.items.isEmpty { run.inventory += n.items; log.append("🎁 From the seasonal shop: " + n.items.map(\.name).joined(separator: ", ") + ".") }
        store.removeItem("dd_event_next_run")
        return log
    }
}
