import Foundation

/// 12.0 THE HUNTING GROUNDS, TRACKING: hunt one beast by sound. The forest is a
/// grid; the beast hides a few steps away and wanders. Listen (its call comes
/// from where it is, louder when it's close), read its tracks, and walk or
/// creep toward it: walking is quick but loud, and a beast that hears you
/// runs (or charges). Reach it unseen for an ambush, or set a trap, then
/// fight. Legendary beasts break away once, wounded, and must be tracked
/// again. Everything the narrator says is a line id in hunt-lines.json.
public enum Tracking {
    public enum Call: String, Codable, Sendable { case howl, snort, wings, hiss, growl }

    public struct Prey: Sendable, Equatable {
        public let id: String
        public let name: String
        public let icon: String
        public let call: Call
        public let hp: Int
        public let atk: ClosedRange<Int>
        public let gold: Int
        public let xp: Int
        public let trophy: String
        /// Chance it moves each turn.
        public let wander: Double
        /// Charges at you when it hears you (instead of running).
        public let aggressive: Bool
        public let legendary: Bool
        /// The Bounty Rank that lets you hunt it.
        public let rank: Int
    }

    public static let prey: [Prey] = [
        Prey(id: "wolf", name: "Grey Wolf", icon: "🐺", call: .howl, hp: 70, atk: 8...14, gold: 60, xp: 20, trophy: "Wolf Pelt", wander: 0.30, aggressive: false, legendary: false, rank: 1),
        Prey(id: "boar", name: "Wild Boar", icon: "🐗", call: .snort, hp: 90, atk: 7...13, gold: 55, xp: 18, trophy: "Boar Tusk", wander: 0.25, aggressive: true, legendary: false, rank: 1),
        Prey(id: "owl", name: "Shadow Owl", icon: "🦉", call: .wings, hp: 50, atk: 9...15, gold: 65, xp: 22, trophy: "Night Feather", wander: 0.40, aggressive: false, legendary: false, rank: 1),
        Prey(id: "serpent", name: "Vine Serpent", icon: "🐍", call: .hiss, hp: 60, atk: 10...16, gold: 70, xp: 24, trophy: "Serpent Scale", wander: 0.20, aggressive: false, legendary: false, rank: 2),
        Prey(id: "stalker", name: "Night Stalker", icon: "👁", call: .growl, hp: 100, atk: 13...19, gold: 100, xp: 32, trophy: "Stalker Fang", wander: 0.35, aggressive: true, legendary: false, rank: 3),
        Prey(id: "bear", name: "Cave Bear", icon: "🐻", call: .growl, hp: 130, atk: 12...20, gold: 110, xp: 35, trophy: "Bear Claw", wander: 0.20, aggressive: true, legendary: false, rank: 4),
        Prey(id: "greyfang", name: "The Grey Fang", icon: "🐺", call: .howl, hp: 220, atk: 14...22, gold: 500, xp: 120, trophy: "The Grey Fang's Crown", wander: 0.40, aggressive: false, legendary: true, rank: 2),
        Prey(id: "stag", name: "The White Stag", icon: "🦌", call: .snort, hp: 260, atk: 12...20, gold: 750, xp: 160, trophy: "White Antler", wander: 0.50, aggressive: false, legendary: true, rank: 4),
        Prey(id: "swampking", name: "The Swamp King", icon: "🐊", call: .hiss, hp: 320, atk: 16...26, gold: 1000, xp: 220, trophy: "The Swamp King's Eye", wander: 0.30, aggressive: true, legendary: true, rank: 6),
        Prey(id: "nightmother", name: "The Night Mother", icon: "🦇", call: .wings, hp: 380, atk: 18...28, gold: 1500, xp: 300, trophy: "Moonlit Wing", wander: 0.45, aggressive: false, legendary: true, rank: 8),
        Prey(id: "forest", name: "The Forest Itself", icon: "🌳", call: .growl, hp: 500, atk: 20...32, gold: 3000, xp: 500, trophy: "The Heartwood", wander: 0.35, aggressive: true, legendary: true, rank: 10),
    ]

    public static func prey(_ id: String) -> Prey? { prey.first { $0.id == id } }
    public static var common: [Prey] { prey.filter { !$0.legendary } }
    public static var legends: [Prey] { prey.filter(\.legendary) }

    /// The forest runs from -size to size each way.
    public static let size = 6
    /// Tracking turns before the trail goes cold.
    public static let maxTurns = 40
    public static let bandages = 3

    public enum Phase: String, Codable, Sendable { case tracking, found, fight, won, lost, cold }
    public enum Strike: String, Sendable { case attack, heavy, defend, bandage }

    public struct Hunt: Codable, Sendable, Equatable {
        public var preyId: String
        public var bounty: Bool
        public var phase: Phase = .tracking
        /// You and the beast on the grid (north is -y).
        public var x = 0, y = 0, px = 0, py = 0
        public var noise = 0
        public var turns = 0
        /// It noticed you before you reached it: no ambush.
        public var seen = false
        public var hp: Int
        public var maxHp: Int
        public var atkLo: Int
        public var atkHi: Int
        public var def: Int
        public var bandages = Tracking.bandages
        public var preyHp: Int
        public var preyMax: Int
        /// Turns it stays caught in your trap.
        public var stuck = 0
        /// A legend breaks away once.
        public var fledOnce = false

        public var prey: Prey { Tracking.prey(preyId) ?? Tracking.prey[0] }
        public var dx: Int { px - x }
        public var dy: Int { py - y }
        public var distance: Int { max(abs(dx), abs(dy)) }
    }

    /// The hunter: the character's class, stronger with level.
    public static func start(_ preyId: String, character ch: PlayerCharacter, bounty: Bool = false, dice: inout some Dice) -> Hunt {
        let info = GameData.classInfo(ch.cls)
        let lv = max(1, ch.persistLevel ?? 1)
        let p = prey(preyId) ?? prey[0]
        var h = Hunt(preyId: p.id, bounty: bounty, hp: info.maxHp + lv * 10, maxHp: info.maxHp + lv * 10,
                     atkLo: info.atk.lowerBound + lv, atkHi: info.atk.upperBound + lv, def: info.def,
                     preyHp: p.hp, preyMax: p.hp)
        place(&h, away: 5 + dice.roll(0...2), dice: &dice)
        return h
    }

    /// Puts the beast about `away` steps from you.
    static func place(_ h: inout Hunt, away: Int, dice: inout some Dice) {
        for _ in 0..<50 {
            let ang = Double(dice.roll(0...359)) * .pi / 180
            let nx = h.x + Int((cos(ang) * Double(away)).rounded()), ny = h.y + Int((sin(ang) * Double(away)).rounded())
            if abs(nx) <= size, abs(ny) <= size, max(abs(nx - h.x), abs(ny - h.y)) >= 2 {
                h.px = nx; h.py = ny; return
            }
        }
        h.px = h.x > 0 ? -size : size; h.py = h.y > 0 ? -size : size
    }

    /// One of the eight directions from you to (dx, dy): "north", "northeast" ….
    public static func direction(_ dx: Int, _ dy: Int) -> String {
        if dx == 0 && dy == 0 { return "north" }
        let deg = (atan2(Double(dx), Double(-dy)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let names = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        return names[Int((deg + 22.5) / 45) % 8]
    }

    public static func distanceWord(_ d: Int) -> String { d <= 1 ? "close" : d <= 3 ? "near" : "far" }

    /// The line for hearing it from where you are.
    public static func hearLine(_ h: Hunt) -> String {
        "hear_\(h.prey.call.rawValue)_\(direction(h.dx, h.dy))_\(distanceWord(h.distance))"
    }

    // MARK: Tracking

    /// Walk (loud) or creep (quiet, but the beast gets an extra move) one step.
    public static func move(_ h: inout Hunt, _ d: Compass, sneak: Bool, dice: inout some Dice) -> [String] {
        guard h.phase == .tracking else { return [] }
        let nx = h.x + d.dx, ny = h.y + d.dy
        guard abs(nx) <= size, abs(ny) <= size else { return ["tree"] }
        h.x = nx; h.y = ny
        h.noise += sneak ? 1 : 3
        var out = [(sneak ? "sneak_" : "walk_") + d.rawValue]
        if h.dx == 0 && h.dy == 0 { return out + reached(&h) }
        out += passTime(&h, extraMove: sneak, dice: &dice)
        return out
    }

    /// Stand still and listen: where the call comes from, and how far.
    public static func listen(_ h: inout Hunt, dice: inout some Dice) -> [String] {
        guard h.phase == .tracking else { return [] }
        let out = [hearLine(h)]
        return out + passTime(&h, extraMove: false, dice: &dice)
    }

    /// Search the ground: fresh tracks point the way when it's close.
    public static func search(_ h: inout Hunt, dice: inout some Dice) -> [String] {
        guard h.phase == .tracking else { return [] }
        let found = dice.chance(h.distance <= 3 ? 0.85 : 0.55)
        let out = found ? ["tracks_\(direction(h.dx, h.dy))_\(h.distance <= 3 ? "fresh" : "old")"] : ["tracks_none"]
        return out + passTime(&h, extraMove: false, dice: &dice)
    }

    /// A turn goes by: the noise fades, the beast may move or hear you.
    static func passTime(_ h: inout Hunt, extraMove: Bool, dice: inout some Dice) -> [String] {
        var out: [String] = []
        h.turns += 1
        let p = h.prey
        let threshold = p.legendary ? 3 : 4
        if h.noise >= threshold && h.distance <= 3 {
            h.seen = true
            if p.aggressive {
                h.phase = .fight
                h.px = h.x; h.py = h.y
                out.append("heard_charge")
                out += preyTurn(&h, defending: false, dice: &dice)
                return out
            }
            out.append("heard_flee")
            place(&h, away: 4, dice: &dice)
            h.noise = 0
        } else if h.noise >= threshold - 1 && h.distance <= 4 {
            out.append("noise_warn")
        }
        for _ in 0..<(extraMove ? 2 : 1) where dice.chance(p.wander) { wander(&h, dice: &dice) }
        h.noise = max(0, h.noise - 1)
        if h.turns >= maxTurns && h.phase == .tracking { h.phase = .cold; out.append("cold") }
        return out
    }

    static func wander(_ h: inout Hunt, dice: inout some Dice) {
        let d = Compass.allCases[dice.roll(0...3)]
        let nx = h.px + d.dx, ny = h.py + d.dy
        guard abs(nx) <= size, abs(ny) <= size, !(nx == h.x && ny == h.y) else { return }
        h.px = nx; h.py = ny
    }

    static func reached(_ h: inout Hunt) -> [String] {
        h.phase = .found
        // Walking right up to it gives you away.
        if h.noise >= 3 { h.seen = true }
        return ["found_\(h.preyId)"]
    }

    // MARK: Found it

    /// Strike from hiding: double and a half damage if it hasn't noticed you.
    public static func ambush(_ h: inout Hunt, dice: inout some Dice) -> [String] {
        guard h.phase == .found else { return [] }
        h.phase = .fight
        if h.seen { return ["ambush_seen"] + preyTurn(&h, defending: false, dice: &dice) }
        let dmg = Int(Double(dice.roll(h.atkLo...h.atkHi)) * 2.5)
        return ["ambush"] + hurtPrey(&h, dmg)
    }

    /// Set a trap: it's caught for two turns, or it slips away.
    public static func trap(_ h: inout Hunt, dice: inout some Dice) -> [String] {
        guard h.phase == .found else { return [] }
        if dice.chance(h.prey.legendary ? 0.5 : 0.7) {
            h.phase = .fight
            h.stuck = 2
            return ["trap_ok"]
        }
        h.phase = .tracking
        h.seen = false
        h.noise = 0
        place(&h, away: 2 + dice.roll(0...1), dice: &dice)
        return ["trap_fail"]
    }

    public static func face(_ h: inout Hunt) -> [String] {
        guard h.phase == .found else { return [] }
        h.phase = .fight
        return ["fight"]
    }

    // MARK: Fighting

    public static func strike(_ h: inout Hunt, _ s: Strike, dice: inout some Dice) -> [String] {
        guard h.phase == .fight else { return [] }
        var out: [String] = []
        switch s {
        case .attack:
            let dmg = dice.roll(h.atkLo...h.atkHi)
            out.append("hit"); out += hurtPrey(&h, dmg)
        case .heavy:
            if dice.chance(0.25) { out.append("miss") }
            else { out.append("hit_hard"); out += hurtPrey(&h, Int(Double(dice.roll(h.atkLo...h.atkHi)) * 1.6)) }
        case .defend:
            out.append("defend"); out += hurtPrey(&h, max(1, dice.roll(h.atkLo...h.atkHi) / 2))
        case .bandage:
            guard h.bandages > 0 else { return ["no_bandage"] }
            h.bandages -= 1
            h.hp = min(h.maxHp, h.hp + h.maxHp * 35 / 100)
            out.append("bandage")
        }
        if h.phase == .fight { out += preyTurn(&h, defending: s == .defend, dice: &dice) }
        return out
    }

    /// Your blow lands: it weakens, breaks away (a legend, once) or falls.
    static func hurtPrey(_ h: inout Hunt, _ dmg: Int) -> [String] {
        let before = h.preyHp
        h.preyHp = max(0, h.preyHp - dmg)
        if h.preyHp == 0 {
            h.phase = .won
            var out = ["win_\(h.preyId)"]
            if h.prey.legendary { out.append("legend_done") }
            if h.bounty { out.append("bounty_done") }
            return out
        }
        if h.prey.legendary && !h.fledOnce && h.preyHp * 2 <= h.preyMax {
            h.fledOnce = true
            h.phase = .tracking
            h.stuck = 0
            h.seen = false
            h.noise = 0
            h.turns = max(0, h.turns - 10)
            var d = SeededDice(seed: UInt64(h.preyHp * 31 + h.turns))
            place(&h, away: 4, dice: &d)
            return ["legend_flee"]
        }
        if h.preyHp * 4 <= h.preyMax && before * 4 > h.preyMax { return ["prey_dying"] }
        if h.preyHp * 2 <= h.preyMax && before * 2 > h.preyMax { return ["prey_weak"] }
        return []
    }

    /// The beast's turn: caught, or it strikes (a quarter as hard when you defend).
    static func preyTurn(_ h: inout Hunt, defending: Bool, dice: inout some Dice) -> [String] {
        if h.stuck > 0 { h.stuck -= 1; return ["its_stuck"] }
        let before = h.hp
        var dmg = max(1, dice.roll(h.prey.atk) - h.def)
        if defending { dmg = max(1, dmg / 4) }
        h.hp = max(0, h.hp - dmg)
        var out = [defending ? "blocked" : dmg * 100 >= h.maxHp * 15 ? "its_hit_hard" : "its_hit"]
        if h.hp == 0 { h.phase = .lost; out.append("lost"); return out }
        if h.hp * 4 <= h.maxHp && before * 4 > h.maxHp { out.append("badly_hurt") }
        else if h.hp * 2 <= h.maxHp && before * 2 > h.maxHp { out.append("hurt") }
        return out
    }

    // MARK: Rewards and records

    public struct Reward: Equatable, Sendable {
        public let gold: Int
        public let xp: Int
        public let trophy: String
    }

    /// What a won hunt pays: a bounty pays double gold and half again the XP.
    public static func reward(_ h: Hunt) -> Reward? {
        guard h.phase == .won else { return nil }
        let p = h.prey
        return Reward(gold: p.gold * (h.bounty ? 2 : 1), xp: h.bounty ? p.xp * 3 / 2 : p.xp, trophy: p.trophy)
    }

    /// Pays a won hunt into the save: gold, Bounty Rank XP, the trophy, the
    /// bounty and the legend. Returns the reward and a new rank, if any.
    @discardableResult
    public static func collect(_ h: Hunt, store: GameStore, wallet: Wallet, now: Date = Date()) -> (reward: Reward, rankUp: DungeonCore.Hunt.Rank?)? {
        guard let r = reward(h) else { return nil }
        wallet.addGold(r.gold)
        let up = DungeonCore.Hunt.addXP(r.xp, store: store)
        var t = trophies(store)
        t[h.preyId, default: 0] += 1
        save(t, "dd_hunt_trophies", store)
        if h.prey.legendary {
            var l = legendsSlain(store)
            if !l.contains(h.preyId) { l.append(h.preyId); save(l, "dd_hunt_legends", store) }
        }
        if h.bounty {
            var b = bountyState(store, now: now)
            if !b.done.contains(h.preyId) { b.done.append(h.preyId) }
            save(b, "dd_hunt_bounties", store)
        }
        return (r, up)
    }

    public static func trophies(_ store: GameStore) -> [String: Int] { load("dd_hunt_trophies", store) ?? [:] }
    public static func legendsSlain(_ store: GameStore) -> [String] { load("dd_hunt_legends", store) ?? [] }

    // MARK: Daily bounties

    public struct Bounties: Codable, Equatable, Sendable {
        public var day: String
        public var done: [String] = []
    }

    static func utcDay(_ now: Date) -> (String, Int) {
        let n = Int((now.timeIntervalSince1970 / 86400).rounded(.down))
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return (f.string(from: now), n)
    }

    /// Today's three bounties (UTC), the same for everyone: beasts your rank can hunt.
    public static func bounties(rank: Int, now: Date = Date()) -> [Prey] {
        let (_, n) = utcDay(now)
        var pool = common.filter { $0.rank <= max(1, rank) }
        var out: [Prey] = []
        var s = n * 7 + 31_000
        while out.count < 3 && !pool.isEmpty {
            let i = Int(Challenges.seeded(s) * Double(pool.count)) % pool.count
            out.append(pool.remove(at: i))
            s += 1
        }
        return out
    }

    public static func bountyState(_ store: GameStore, now: Date = Date()) -> Bounties {
        let day = utcDay(now).0
        if let b: Bounties = load("dd_hunt_bounties", store), b.day == day { return b }
        return Bounties(day: day)
    }

    // MARK: Saving

    static func load<T: Decodable>(_ key: String, _ store: GameStore) -> T? {
        guard let s = store.getItem(key), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    static func save<T: Encodable>(_ v: T, _ key: String, _ store: GameStore) {
        if let d = try? JSONEncoder().encode(v), let s = String(data: d, encoding: .utf8) { store.setItem(key, s) }
    }
}


/// The narrator's lines (hunt-lines.json, made by swift/tools/hunt-lines.py):
/// each id has English and Portuguese text, and a recording of each.
public enum HuntLines {
    public static let all: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "hunt-lines", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let v = try? JSONDecoder().decode([String: [String: String]].self, from: d) else { return [:] }
        return v
    }()

    /// The words of a line: Portuguese when `pt`, else English (the id when unknown).
    public static func text(_ id: String, pt: Bool = false) -> String {
        guard let l = all[id] else { return id }
        return (pt ? l["pt"] : nil) ?? l["en"] ?? id
    }
}
