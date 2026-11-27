import Foundation

/// 12.3: the Advent Calendar. December 1 to 25, one door a day; missed doors
/// can be opened until December 31. Saved per year in "dd_advent_<year>" (a
/// list of opened days, cloud-synced). The web version is js/37-advent.js
/// with the same table.
public enum Advent {
    public struct Prize: Sendable {
        public let day: Int
        public let icon: String
        public var gold = 0, coins = 0, fragments = 0, trophies = 0
        public var item: String? = nil
        public var count = 1
    }

    public static let days: [Prize] = [
        Prize(day: 1, icon: "🎁", gold: 500),
        Prize(day: 2, icon: "🧪", item: "greater", count: 3),
        Prize(day: 3, icon: "🪙", coins: 5),
        Prize(day: 4, icon: "💠", fragments: 2),
        Prize(day: 5, icon: "🍪", gold: 1000),
        Prize(day: 6, icon: "🧴", item: "antidote", count: 3),
        Prize(day: 7, icon: "🪙", coins: 10),
        Prize(day: 8, icon: "🏆", trophies: 3),
        Prize(day: 9, icon: "💠", fragments: 3),
        Prize(day: 10, icon: "🎁", gold: 1500),
        Prize(day: 11, icon: "🧪", item: "greater", count: 5),
        Prize(day: 12, icon: "🪙", coins: 10),
        Prize(day: 13, icon: "🔥", item: "torch", count: 2),
        Prize(day: 14, icon: "💠", fragments: 5),
        Prize(day: 15, icon: "🎁", gold: 2500),
        Prize(day: 16, icon: "🏆", trophies: 5),
        Prize(day: 17, icon: "🪙", coins: 15),
        Prize(day: 18, icon: "💠", fragments: 5),
        Prize(day: 19, icon: "🧪", item: "greater", count: 5),
        Prize(day: 20, icon: "🎁", gold: 4000),
        Prize(day: 21, icon: "🪙", coins: 20),
        Prize(day: 22, icon: "💠", fragments: 8),
        Prize(day: 23, icon: "🏆", trophies: 10),
        Prize(day: 24, icon: "🌟", gold: 7500, coins: 25),
        Prize(day: 25, icon: "🎄", coins: 50, trophies: 10, item: "starfall"),
    ]

    public static func item(_ id: String) -> Item {
        switch id {
        case "greater": return Item(name: "Greater Potion", icon: "💊", type: "potion", desc: "Restores 80 HP. Stronger brew.", heal: 80)
        case "antidote": return SkyRuins.antidote
        case "torch": return SkyRuins.rootTorch
        default: return Item(name: "Starfall Blade", icon: "🌟", type: "weapon",
                             desc: "A blade forged from a star that fell on Christmas night. A gift from the Advent Calendar.", atk: 24)
        }
    }

    static func parts(_ date: Date) -> (year: Int, month: Int, day: Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    /// The calendar shows in December (or always in dev mode).
    public static func isOn(_ store: GameStore, now: Date = Date()) -> Bool {
        parts(now).month == 12 || store.getItem("dd_dev_mode") == "1"
    }

    /// A door opens on its day and stays open until December 31.
    public static func canOpen(_ day: Int, store: GameStore, now: Date = Date()) -> Bool {
        if store.getItem("dd_dev_mode") == "1" { return true }
        let p = parts(now)
        return p.month == 12 && p.day >= day
    }

    static func key(_ now: Date) -> String { "dd_advent_\(parts(now).year)" }

    public static func opened(_ store: GameStore, now: Date = Date()) -> [Int] {
        guard let s = store.getItem(key(now)), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([Int].self, from: d) else { return [] }
        return v
    }

    public static func ready(_ store: GameStore, now: Date = Date()) -> Int {
        let o = opened(store, now: now)
        return days.filter { canOpen($0.day, store: store, now: now) && !o.contains($0.day) }.count
    }

    public static func text(_ p: Prize) -> String {
        var parts: [String] = []
        if p.gold > 0 { parts.append("\(p.gold.formatted()) gold") }
        if let i = p.item {
            let name = item(i).name
            parts.append(p.count > 1 ? "\(p.count) " + (i == "torch" ? "Root Torches" : name + "s") : "the " + name)
        }
        if p.coins > 0 { parts.append("\(p.coins) Mystery Coins") }
        if p.fragments > 0 { parts.append("\(p.fragments) Soul Fragments") }
        if p.trophies > 0 { parts.append("\(p.trophies) trophies") }
        return parts.joined(separator: ", ")
    }

    public enum Result: Equatable { case opened(String), already(String), locked(String) }

    /// Opens a door and pays its prize: gold to the wallet, the rest to the save.
    public static func open(_ day: Int, store: GameStore, wallet: Wallet, now: Date = Date()) -> Result {
        guard let p = days.first(where: { $0.day == day }) else { return .locked("There is no door \(day).") }
        var o = opened(store, now: now)
        if o.contains(day) { return .already("Door \(day) is already open. You got \(text(p)).") }
        guard canOpen(day, store: store, now: now) else { return .locked("Door \(day) opens on December \(day).") }
        if p.gold > 0 { wallet.addGold(p.gold) }
        func add(_ key: String, _ n: Int) {
            guard n > 0 else { return }
            store.setItem(key, String((jsParseInt(store.getItem(key)) ?? 0) + n))
        }
        if p.coins > 0 {
            add("dd_mystery_coins", p.coins)
            RaidSave(store: store).syncCoins(jsParseInt(store.getItem("dd_mystery_coins")) ?? 0)
        }
        add("dd_soul_fragments", p.fragments)
        add("dd_trophies", p.trophies)
        if let i = p.item { for _ in 0..<p.count { GlobalInventory(store: store).add(item(i)) } }
        o.append(day)
        if let d = try? JSONEncoder().encode(o), let s = String(data: d, encoding: .utf8) { store.setItem(key(now), s) }
        return .opened((day == 25 ? "🎄 Merry Christmas! " : p.icon + " ") + "Door \(day): \(text(p))!"
                       + (day == 25 ? " The Starfall Blade is in your items." : ""))
    }
}
