import Foundation

/// CO-OP DUNGEON (12.0): 2–4 players, on the web and the apps together,
/// through 10 floors of a dungeon, one fight a floor and the boss on floor
/// 10. Every round each player picks Attack, Heavy, Defend or Potion; when
/// everyone has (or after 30 seconds) the round happens all at once, and the
/// enemy strikes one player back. A player at 0 HP is downed and comes back
/// on the next floor with 30% HP; if everyone is down, the run is lost.
///
/// The host's device runs these rules and writes the room; the others only
/// send their choices. The room lives in the Realtime Database at
/// "pvp_rooms/coop_CODE" (the one place open to every player, where PvP
/// never looks). The web version (js/31-coop.js) has the same rules.
public enum Coop {
    public static let maxPlayers = 4
    public static let floors = 10
    public static let roundSeconds = 30.0
    public static let potions = 3

    public enum Action: String, Sendable, CaseIterable {
        case attack, heavy, defend, potion
        public var label: String {
            switch self {
            case .attack: return "⚔ Attack"
            case .heavy: return "💥 Heavy"
            case .defend: return "🛡 Defend"
            case .potion: return "🧪 Potion"
            }
        }
    }

    // MARK: The party

    public struct Player: Equatable, Sendable {
        public var id: String
        public var name: String
        public var cls: String
        public var level: Int
        public var hp: Int
        public var maxHp: Int
        public var atkLo: Int
        public var atkHi: Int
        public var def: Int
        public var potions: Int
        public var platform: String
        public var ready = false
        public var alive: Bool { hp > 0 }

        public init(id: String, name: String, cls: String, level: Int, hp: Int, maxHp: Int,
                    atkLo: Int, atkHi: Int, def: Int, potions: Int, platform: String, ready: Bool = false) {
            self.id = id; self.name = name; self.cls = cls; self.level = level; self.hp = hp; self.maxHp = maxHp
            self.atkLo = atkLo; self.atkHi = atkHi; self.def = def; self.potions = potions; self.platform = platform
            self.ready = ready
        }

        public var dict: [String: Any] {
            ["id": id, "name": name, "cls": cls, "level": level, "hp": hp, "maxHp": maxHp,
             "atkLo": atkLo, "atkHi": atkHi, "def": def, "potions": potions, "platform": platform, "ready": ready]
        }

        public init?(_ d: [String: Any]) {
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            func n(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
            self.init(id: id, name: name, cls: d["cls"] as? String ?? "", level: max(1, n("level")),
                      hp: n("hp"), maxHp: max(1, n("maxHp")), atkLo: n("atkLo"), atkHi: max(n("atkLo"), n("atkHi")),
                      def: n("def"), potions: n("potions"), platform: d["platform"] as? String ?? "",
                      ready: d["ready"] as? Bool ?? false)
        }
    }

    /// A character's co-op stats: the class's HP, attack and defense, +12 HP
    /// and +1 attack a level, and the prestige stars on top.
    public static func player(_ ch: PlayerCharacter, id: String, platform: String) -> Player {
        let info = GameData.classInfo(ch.cls)
        let level = max(1, ch.persistLevel ?? 1)
        let stars = Double(Prestige.stars(ch))
        let hp = jsRound(Double(info.maxHp + 12 * (level - 1)) * (1 + Prestige.hpPerStar * stars))
        let atk = 1 + Prestige.atkPerStar * stars
        let lo = jsRound(Double(info.atk.lowerBound + level - 1) * atk)
        let hi = jsRound(Double(info.atk.upperBound + level - 1) * atk)
        return Player(id: id, name: Prestige.label(ch), cls: ch.cls, level: level, hp: hp, maxHp: hp,
                      atkLo: lo, atkHi: max(lo, hi), def: info.def, potions: potions, platform: platform)
    }

    // MARK: The enemy

    public struct Foe: Equatable, Sendable {
        public var name: String
        public var icon: String
        public var hp: Int
        public var maxHp: Int
        public var atkLo: Int
        public var atkHi: Int
        public var boss: Bool

        public var dict: [String: Any] {
            ["name": name, "icon": icon, "hp": hp, "maxHp": maxHp, "atkLo": atkLo, "atkHi": atkHi, "boss": boss]
        }

        public init(name: String, icon: String, hp: Int, maxHp: Int, atkLo: Int, atkHi: Int, boss: Bool) {
            self.name = name; self.icon = icon; self.hp = hp; self.maxHp = maxHp
            self.atkLo = atkLo; self.atkHi = atkHi; self.boss = boss
        }

        public init?(_ d: [String: Any]?) {
            guard let d, let name = d["name"] as? String else { return nil }
            func n(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
            self.init(name: name, icon: d["icon"] as? String ?? "💀", hp: n("hp"), maxHp: max(1, n("maxHp")),
                      atkLo: n("atkLo"), atkHi: max(n("atkLo"), n("atkHi")), boss: d["boss"] as? Bool ?? false)
        }
    }

    /// The floor's enemy: the dungeon's own (its boss on floor 10), scaled by
    /// floor and the party's average level, with 70% more HP for each extra
    /// player.
    public static func foe<D: Dice>(dungeon: String, floor: Int, party: [Player], dice: inout D) -> Foe {
        let table = Bestiary.enemies(for: dungeon)
        let boss = floor >= floors
        let pool = boss ? table.bosses : table.pool(forFloor: floor)
        let t = pool.isEmpty ? Bestiary.crypt.t1[0] : pool[dice.roll(0...(pool.count - 1))]
        let alive = max(1, party.count)
        let level = max(1, party.map(\.level).reduce(0, +) / alive)
        let e = Enemy.spawn(t, floor: floor, playerLevel: level)
        let hp = jsRound(Double(e.hp) * (1 + 0.7 * Double(alive - 1)) * (boss ? 1.5 : 1))
        return Foe(name: e.name, icon: e.icon, hp: hp, maxHp: hp, atkLo: e.atk.lowerBound, atkHi: e.atk.upperBound, boss: boss)
    }

    // MARK: A round

    public struct Round: Equatable, Sendable {
        public var party: [Player]
        public var foe: Foe
        public var lines: [String] = []
        public var foeDown = false
        public var partyDown = false
    }

    /// Everyone's actions at once, then the enemy's answer. Players without a
    /// choice (time ran out) attack.
    public static func resolve<D: Dice>(party: [Player], foe: Foe, actions: [String: Action], dice: inout D) -> Round {
        var r = Round(party: party, foe: foe)
        var defending = Set<String>()
        for i in r.party.indices where r.party[i].alive {
            let p = r.party[i]
            var a = actions[p.id] ?? .attack
            if a == .potion && p.potions <= 0 { a = .attack }
            switch a {
            case .potion:
                let heal = jsRound(Double(p.maxHp) * 0.4)
                r.party[i].hp = min(p.maxHp, p.hp + heal)
                r.party[i].potions -= 1
                r.lines.append("🧪 \(p.name) drinks a potion: +\(heal) HP (\(r.party[i].hp) of \(p.maxHp)).")
                continue
            case .defend:
                defending.insert(p.id)
            default: break
            }
            guard r.foe.hp > 0 else { continue }
            var dmg = dice.roll(p.atkLo...p.atkHi)
            var line: String
            switch a {
            case .heavy:
                if dice.chance(0.3) {
                    r.lines.append("💥 \(p.name)'s heavy strike misses!")
                    continue
                }
                dmg = jsRound(Double(dmg) * 1.8)
                line = "💥 \(p.name) heavy strikes for \(dmg)"
            case .defend:
                dmg = max(1, dmg / 2)
                line = "🛡 \(p.name) defends and strikes for \(dmg)"
            default:
                if dice.chance(0.1) {
                    dmg *= 2
                    line = "⚔ \(p.name) lands a CRITICAL hit for \(dmg)"
                } else {
                    line = "⚔ \(p.name) hits for \(dmg)"
                }
            }
            r.foe.hp = max(0, r.foe.hp - dmg)
            r.lines.append(line + (r.foe.hp > 0 ? "." : " — \(r.foe.name) falls!"))
        }
        if r.foe.hp <= 0 {
            r.foeDown = true
            return r
        }
        // The enemy strikes one standing player.
        let standing = r.party.indices.filter { r.party[$0].alive }
        if let t = standing.isEmpty ? nil : standing[dice.roll(0...(standing.count - 1))] {
            let p = r.party[t]
            var dmg = max(1, dice.roll(r.foe.atkLo...r.foe.atkHi) - p.def / 2)
            if defending.contains(p.id) { dmg = max(1, dmg / 2) }
            r.party[t].hp = max(0, p.hp - dmg)
            r.lines.append("\(r.foe.icon) \(r.foe.name) strikes \(p.name) for \(dmg)" + (r.party[t].hp > 0
                ? " (\(r.party[t].hp) of \(p.maxHp) HP)." : " — \(p.name) is down!"))
        }
        r.partyDown = !r.party.contains { $0.alive }
        r.lines.append("\(r.foe.name): \(r.foe.hp) of \(r.foe.maxHp) HP.")
        return r
    }

    /// Between floors: the downed come back with 30% HP, everyone heals 20%.
    public static func rest(_ party: [Player]) -> [Player] {
        party.map { p in
            var q = p
            q.hp = p.alive ? min(p.maxHp, p.hp + jsRound(Double(p.maxHp) * 0.2)) : jsRound(Double(p.maxHp) * 0.3)
            return q
        }
    }

    // MARK: Rewards (each player, on their own device)

    /// 100 gold a floor cleared, and 1,000 more for beating the boss.
    public static func gold(floorsCleared: Int, won: Bool) -> Int { 100 * max(0, floorsCleared) + (won ? 1000 : 0) }

    /// A room code: four letters and digits people can say out loud.
    public static func code<D: Dice>(dice: inout D) -> String {
        let chars = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<4).map { _ in chars[dice.roll(0...(chars.count - 1))] })
    }
}
