import Foundation
import DungeonCore

/// BESTIARY_DATA, recordKill()'s name map and BESTIARY_MILESTONES, pulled
/// from index.html by swift/tools/extract-game-data.js into bestiary.json.
struct BestiaryData: Decodable {
    struct Entry: Decodable {
        let id: String
        let name: String
        let icon: String
        let tier: String
        let desc: String
        let dungeon: String?
        let enemyType: String?
        let isBoss: Bool?
        let isElite: Bool?
    }
    struct Milestone: Decodable {
        let kills: Int
        let reward: String
        let effect: String?
    }

    let entries: [Entry]
    let nameToId: [String: String]
    let milestones: [String: Milestone]

    static let shared: BestiaryData = {
        guard let url = Bundle.main.url(forResource: "bestiary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let b = try? JSONDecoder().decode(BestiaryData.self, from: data) else {
            return BestiaryData(entries: [], nameToId: [:], milestones: [:])
        }
        return b
    }()
}

extension GameModel {
    /// Kills per bestiary entry ("dd_bestiary"), shared with the web version.
    var bestiaryKills: [String: Int] {
        guard let s = store.getItem("dd_bestiary"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) else { return [:] }
        return v.compactMapValues { if case .number(let n) = $0 { return Int(n) }; return nil }
    }

    /// recordKill(): only enemies with a bestiary entry are counted. Returns
    /// the milestone reward when this kill earns one (checkBestiaryMilestone).
    @discardableResult
    func recordBestiaryKill(_ enemyName: String) -> String? {
        guard let id = BestiaryData.shared.nameToId[enemyName] else { return nil }
        var k = bestiaryKills
        k[id, default: 0] += 1
        if let d = try? JSONEncoder().encode(k), let s = String(data: d, encoding: .utf8) {
            store.setItem("dd_bestiary", s)
        }
        guard let m = BestiaryData.shared.milestones[id], k[id, default: 0] >= m.kills else { return nil }
        var earned = jsonObject("dd_milestones")
        if earned[id] != nil { return nil }
        earned[id] = .bool(true)
        setJSON("dd_milestones", earned)
        if let e = m.effect { addMilestoneEffect(e) }
        return "Bestiary Milestone! \(id.replacingOccurrences(of: "-", with: " ")) — \(m.reward)"
    }

    // MARK: Permanent rewards

    func jsonObject(_ key: String) -> [String: JSONValue] {
        guard let s = store.getItem(key), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d) else { return [:] }
        return v
    }

    func setJSON<T: Encodable>(_ key: String, _ value: T) {
        if let d = try? JSONEncoder().encode(value), let s = String(data: d, encoding: .utf8) { store.setItem(key, s) }
    }

    /// "dd_milestone_effects": how many times each permanent effect was earned.
    var milestoneEffects: [String: Int] {
        jsonObject("dd_milestone_effects").compactMapValues { if case .number(let n) = $0 { return Int(n) }; return nil }
    }

    func addMilestoneEffect(_ effect: String) {
        var e = jsonObject("dd_milestone_effects")
        if case .number(let n)? = e[effect] { e[effect] = .number(n + 1) } else { e[effect] = .number(1) }
        setJSON("dd_milestone_effects", e)
    }

    var mysteryCoins: Int { jsParseInt(store.getItem("dd_mystery_coins")) ?? 0 }

    func addMysteryCoins(_ n: Int) {
        store.setItem("dd_mystery_coins", String(mysteryCoins + n))
    }
}

// MARK: Hall of Legends ("dd_legends")

extension GameModel {
    /// checkLegends: the best run records, kept forever.
    func checkLegends(_ r: Run) {
        var l = jsonObject("dd_legends")
        func num(_ key: String, _ field: String) -> Double {
            if case .object(let o)? = l[key], case .number(let n)? = o[field] { return n }
            return -1
        }
        var changed = false
        let who: [String: JSONValue] = ["name": .string(r.name), "cls": .string(r.cls), "race": .string(r.race),
                                        "dungeon": .string(r.dungeon)]
        if Double(r.kills) > num("bestKills", "kills") {
            l["bestKills"] = .object(who.merging(["kills": .number(Double(r.kills)), "diff": .string(r.difficulty.rawValue)]) { $1 })
            changed = true
        }
        if Double(r.gold) > num("bestGold", "gold") {
            l["bestGold"] = .object(who.merging(["gold": .number(Double(r.gold))]) { $1 })
            changed = true
        }
        if Double(r.floor) > num("deepestFloor", "floor") {
            l["deepestFloor"] = .object(who.merging(["floor": .number(Double(r.floor))]) { $1 })
            changed = true
        }
        if r.bestHit > 0 && Double(r.bestHit) > num("bestDmg", "dmg") {
            l["bestDmg"] = .object(who.merging(["dmg": .number(Double(r.bestHit))]) { $1 })
            changed = true
        }
        if changed { setJSON("dd_legends", l) }
    }

    /// recordDungeonFirstClear: the first character to finish each dungeon.
    func recordFirstClear(_ r: Run) {
        var l = jsonObject("dd_legends")
        var fc: [String: JSONValue] = [:]
        if case .object(let o)? = l["firstClears"] { fc = o }
        guard fc[r.dungeon] == nil else { return }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        fc[r.dungeon] = .object(["name": .string(r.name), "cls": .string(r.cls), "race": .string(r.race),
                                 "date": .string("\(c.year ?? 2026)-\(c.month ?? 1)-\(c.day ?? 1)")])
        l["firstClears"] = .object(fc)
        setJSON("dd_legends", l)
    }
}
