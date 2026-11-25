import Foundation

/// CO-OP 2.0 (12.1): 2–4 players (5 from 12.2), on the web and the apps together, through
/// 10 floors of a dungeon: two fights a floor (now and then an elite) and the
/// boss on floor 10, who changes phase at two thirds and a third of its HP.
///
/// Everyone brings their real character: gear, spent level points, prestige
/// stars, up to three class skills (SP) and their gun. Every round each player
/// picks an action; when everyone has (or after 30 seconds) the round happens
/// all at once, then the enemy strikes: the weakest player, or whoever hit it
/// hardest. A downed player can be revived with a potion, and comes back on
/// the next floor anyway. Potions are bought with your own gold between floors.
///
/// Each player's device works out their own stats and skills and writes them
/// into the room as plain numbers, so the host (web or app) runs every fight
/// with the same rules and no skill tables. The room lives in the Realtime
/// Database at "pvp_rooms/coop_CODE" with kind "coop2"; a 12.0 device sees
/// no room there (it looks for "coop"). The web version (js/31-coop.js) has
/// the same rules.
public enum Coop {
    public static let kind = "coop2"
    /// 12.2: rooms hold 5. A room says how many it holds ("max"); one
    /// without it (made by 12.1 or the web) holds 4, and 12.1 apps never join
    /// as a fifth, so every version can still play together.
    public static let maxPlayers = 5
    public static let legacyMax = 4

    public static func roomMax(_ room: [String: Any]) -> Int {
        guard let n = (room["max"] as? NSNumber)?.intValue else { return legacyMax }
        return max(2, min(n, maxPlayers))
    }
    public static let floors = 10
    public static let fightsPerFloor = 2
    public static let roundSeconds = 30.0
    public static let startPotions = 2
    public static let maxPotions = 6
    public static let potionPrice = 40
    public static let spPerRound = 3

    // MARK: Actions

    public enum Action: Equatable, Sendable {
        case attack, heavy, defend, potion, gun
        case skill(String)
        case revive(String)
        case protect(String)

        public var raw: String {
            switch self {
            case .attack: return "attack"
            case .heavy: return "heavy"
            case .defend: return "defend"
            case .potion: return "potion"
            case .gun: return "gun"
            case .skill(let id): return "skill:" + id
            case .revive(let id): return "revive:" + id
            case .protect(let id): return "protect:" + id
            }
        }

        public init?(_ raw: String) {
            let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
            switch parts.first ?? "" {
            case "attack": self = .attack
            case "heavy": self = .heavy
            case "defend": self = .defend
            case "potion": self = .potion
            case "gun": self = .gun
            case "skill" where parts.count == 2: self = .skill(parts[1])
            case "revive" where parts.count == 2: self = .revive(parts[1])
            case "protect" where parts.count == 2: self = .protect(parts[1])
            default: return nil
            }
        }
    }

    // MARK: Skills, as plain numbers

    /// A class skill in co-op: what it does, as numbers any device can use.
    public struct Skill: Equatable, Sendable {
        public var id: String
        public var name: String
        public var icon: String
        public var sp: Int
        /// × the attack roll (0: no hit).
        public var dmg: Double = 0
        /// Share of the enemy's max HP, and flat damage, on top.
        public var pct: Double = 0
        public var flat = 0
        /// Healing: flat, and a share of max HP. Team skills heal everyone standing.
        public var heal = 0
        public var healPct: Double = 0
        public var team = false
        /// A shield that soaks the next hits.
        public var shield = 0
        /// The enemy skips this many turns.
        public var stun = 0
        /// Damage each round, for some rounds.
        public var dot = 0
        public var dotTurns = 0
        /// The enemy's attack × this for the rest of the fight (1: none).
        public var weaken: Double = 1

        public init(id: String, name: String, icon: String, sp: Int) {
            self.id = id; self.name = name; self.icon = icon; self.sp = sp
        }

        public var dict: [String: Any] {
            ["id": id, "name": name, "icon": icon, "sp": sp, "dmg": dmg, "pct": pct, "flat": flat,
             "heal": heal, "healPct": healPct, "team": team, "shield": shield, "stun": stun,
             "dot": dot, "dotTurns": dotTurns, "weaken": weaken]
        }

        public init?(_ d: [String: Any]) {
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            func n(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
            func x(_ k: String, _ def: Double = 0) -> Double { (d[k] as? NSNumber)?.doubleValue ?? def }
            self.init(id: id, name: name, icon: d["icon"] as? String ?? "✨", sp: max(0, n("sp")))
            dmg = x("dmg"); pct = x("pct"); flat = n("flat"); heal = n("heal"); healPct = x("healPct")
            team = d["team"] as? Bool ?? false; shield = n("shield"); stun = n("stun")
            dot = n("dot"); dotTurns = n("dotTurns"); weaken = x("weaken", 1)
        }

        /// What it does, for the button's description.
        public var summary: String {
            var parts: [String] = []
            if dmg > 0 { parts.append(dmg == 1 ? "a hit" : "×\(Self.trim(dmg)) damage") }
            if pct > 0 { parts.append("\(Int((pct * 100).rounded()))% of its max HP") }
            if flat > 0 { parts.append("+\(flat) damage") }
            if heal > 0 || healPct > 0 {
                let amt = healPct > 0 ? "\(Int((healPct * 100).rounded()))% HP" : "\(heal) HP"
                parts.append(team ? "heals the party \(amt)" : "heals you \(amt)")
            }
            if shield > 0 { parts.append("\(shield) shield") }
            if stun > 0 { parts.append("stuns \(stun) turn\(stun == 1 ? "" : "s")") }
            if dot > 0 { parts.append("\(dot) a round for \(dotTurns) rounds") }
            if weaken < 1 { parts.append("enemy hits \(Int(((1 - weaken) * 100).rounded()))% softer") }
            return parts.isEmpty ? "a hit" : parts.joined(separator: ", ")
        }

        static func trim(_ x: Double) -> String {
            x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x)
        }
    }

    /// A class skill's co-op version, from its solo numbers. Effects co-op
    /// doesn't have (and skills with none of these) become a 1.5× strike.
    public static func skill(_ s: DungeonCore.Skill, cls: String) -> Skill {
        let spec = SkillTable.spec(cls: cls, effect: s.effect)
        var c = Skill(id: s.effect, name: s.name, icon: s.icon, sp: s.spCost)
        c.dmg = spec.dmg * Double(max(1, spec.hits))
        c.pct = spec.pctEnemyMax + spec.pctEnemyHp * 0.5
        c.flat = spec.flat
        c.heal = spec.heal
        c.healPct = spec.healMaxShare
        c.shield = spec.shield
        c.stun = spec.stun
        if spec.dot > 0 { c.dot = spec.dot; c.dotTurns = max(1, spec.dotTurns) }
        c.weaken = spec.weaken < 1 ? spec.weaken : spec.reduce > 0 ? max(0.5, 1 - spec.reduce) : 1
        let does = c.dmg > 0 || c.pct > 0 || c.flat > 0 || c.heal > 0 || c.healPct > 0
            || c.shield > 0 || c.stun > 0 || c.dot > 0 || c.weaken < 1
        if !does { c.dmg = 1.5 }
        // Healing words in the description make it a party heal.
        let d = s.desc.lowercased()
        if (c.heal > 0 || c.healPct > 0) && (d.contains("party") || d.contains("allies") || d.contains("everyone")) { c.team = true }
        return c
    }

    /// Up to three skills for co-op: the ones this character knows (a
    /// Legacy character's saved skills), then the class's by tier as the
    /// level allows: common from 1, rare from 5, legendary from 10.
    public static func loadout(cls: String, level: Int, known: [String]) -> [Skill] {
        let all = Skills.all(for: cls)
        var picks: [DungeonCore.Skill] = known.compactMap { k in all.first { $0.effect == k } }
        let tiers = ["common"] + (level >= 5 ? ["rare"] : []) + (level >= 10 ? ["legendary"] : [])
        if let first = GameContent.shared.startingSkills[cls], let s = all.first(where: { $0.effect == first }),
           !picks.contains(s) { picks.insert(s, at: 0) }
        for tier in tiers.reversed() where picks.count < 3 {
            if let s = all.first(where: { $0.tier == tier && !picks.contains($0) }) { picks.append(s) }
        }
        return picks.prefix(3).map { skill($0, cls: cls) }
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
        public var sp: Int
        public var maxSp: Int
        public var crit: Double
        public var potions: Int
        public var platform: String
        public var ready = false
        public var skills: [Skill] = []
        /// The equipped gun: name, damage and shots a fight.
        public var gunName = ""
        public var gunLo = 0
        public var gunHi = 0
        public var gunShots = 0
        public var shots = 0
        /// Soaks damage before HP; from skills.
        public var shield = 0
        /// Damage dealt last round (the enemy goes after big hitters).
        public var dealt = 0
        public var alive: Bool { hp > 0 }
        public var hasGun: Bool { gunShots > 0 && gunHi > 0 }

        public init(id: String, name: String, cls: String, level: Int, hp: Int, maxHp: Int,
                    atkLo: Int, atkHi: Int, def: Int, sp: Int = 20, maxSp: Int = 20, crit: Double = 0.1,
                    potions: Int, platform: String, ready: Bool = false) {
            self.id = id; self.name = name; self.cls = cls; self.level = level; self.hp = hp; self.maxHp = maxHp
            self.atkLo = atkLo; self.atkHi = atkHi; self.def = def; self.sp = sp; self.maxSp = maxSp
            self.crit = crit; self.potions = potions; self.platform = platform; self.ready = ready
        }

        public var dict: [String: Any] {
            ["id": id, "name": name, "cls": cls, "level": level, "hp": hp, "maxHp": maxHp,
             "atkLo": atkLo, "atkHi": atkHi, "def": def, "sp": sp, "maxSp": maxSp, "crit": crit,
             "potions": potions, "platform": platform, "ready": ready, "skills": skills.map(\.dict),
             "gunName": gunName, "gunLo": gunLo, "gunHi": gunHi, "gunShots": gunShots, "shots": shots,
             "shield": shield, "dealt": dealt]
        }

        public init?(_ d: [String: Any]) {
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            func n(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
            self.init(id: id, name: name, cls: d["cls"] as? String ?? "", level: max(1, n("level")),
                      hp: n("hp"), maxHp: max(1, n("maxHp")), atkLo: n("atkLo"), atkHi: max(n("atkLo"), n("atkHi")),
                      def: n("def"), sp: n("sp"), maxSp: max(1, n("maxSp")),
                      crit: (d["crit"] as? NSNumber)?.doubleValue ?? 0.1, potions: n("potions"),
                      platform: d["platform"] as? String ?? "", ready: d["ready"] as? Bool ?? false)
            // Firebase hands back a list as an array, or as a keyed object
            // when it has gaps.
            let raw: [Any] = (d["skills"] as? [Any]) ?? ((d["skills"] as? [String: Any]).map { o in
                o.sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }.map(\.value) } ?? [])
            skills = raw.compactMap { ($0 as? [String: Any]).flatMap(Skill.init) }
            gunName = d["gunName"] as? String ?? ""
            gunLo = n("gunLo"); gunHi = max(n("gunLo"), n("gunHi")); gunShots = n("gunShots"); shots = n("shots")
            shield = n("shield"); dealt = n("dealt")
        }
    }

    /// A character's co-op player, from a run set up the way a dungeon run
    /// starts (gear, spent level points, prestige stars and Legacy's level
    /// already on it): +12 HP and +1 attack a level, the gear's attack and
    /// defense, up to three skills and the equipped gun.
    public static func player(_ run: Run, character ch: PlayerCharacter, id: String, platform: String, gun: Gun? = nil,
                              potions: Int = startPotions) -> Player {
        let level = max(1, max(run.level, ch.persistLevel ?? 1))
        let hp = run.maxHp + 12 * (level - 1)
        let bonus = run.totalAtkBonus + level - 1
        let lo = max(1, run.atk.lowerBound + bonus), hi = max(lo, run.atk.upperBound + bonus)
        var p = Player(id: id, name: Prestige.label(ch), cls: ch.cls, level: level, hp: hp, maxHp: hp,
                       atkLo: lo, atkHi: hi, def: max(0, run.totalDef), sp: run.maxSp, maxSp: run.maxSp,
                       crit: min(0.5, 0.1 + run.critBonus), potions: max(0, min(maxPotions, potions)), platform: platform)
        p.skills = loadout(cls: ch.cls, level: level, known: run.unlockedSkills)
        if let g = gun {
            p.gunName = g.icon + " " + g.name
            p.gunLo = g.damage.lowerBound
            p.gunHi = g.damage.upperBound
            p.gunShots = max(1, min(3, g.shots))
            p.shots = p.gunShots
        }
        return p
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
        public var elite = false
        /// The boss's phase: 1, then 2 under two thirds, 3 under a third.
        public var phase = 1
        public var stun = 0
        public var dot = 0
        public var dotTurns = 0
        public var weaken: Double = 1

        public init(name: String, icon: String, hp: Int, maxHp: Int, atkLo: Int, atkHi: Int, boss: Bool, elite: Bool = false) {
            self.name = name; self.icon = icon; self.hp = hp; self.maxHp = maxHp
            self.atkLo = atkLo; self.atkHi = atkHi; self.boss = boss; self.elite = elite
        }

        public var dict: [String: Any] {
            ["name": name, "icon": icon, "hp": hp, "maxHp": maxHp, "atkLo": atkLo, "atkHi": atkHi, "boss": boss,
             "elite": elite, "phase": phase, "stun": stun, "dot": dot, "dotTurns": dotTurns, "weaken": weaken]
        }

        public init?(_ d: [String: Any]?) {
            guard let d, let name = d["name"] as? String else { return nil }
            func n(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
            self.init(name: name, icon: d["icon"] as? String ?? "💀", hp: n("hp"), maxHp: max(1, n("maxHp")),
                      atkLo: n("atkLo"), atkHi: max(n("atkLo"), n("atkHi")), boss: d["boss"] as? Bool ?? false,
                      elite: d["elite"] as? Bool ?? false)
            phase = max(1, n("phase")); stun = n("stun"); dot = n("dot"); dotTurns = n("dotTurns")
            weaken = (d["weaken"] as? NSNumber)?.doubleValue ?? 1
        }

        /// Its attack range now: weakened, and 20% stronger each boss phase.
        public var attack: ClosedRange<Int> {
            let m = weaken * (1 + 0.2 * Double(phase - 1))
            let lo = max(1, jsRound(Double(atkLo) * m)), hi = max(lo, jsRound(Double(atkHi) * m))
            return lo...hi
        }
    }

    /// The fight's enemy: the dungeon's own (its boss on floor 10), scaled by
    /// floor, the party's average level and the dungeon's depth, with 70% more
    /// HP for each extra player. One fight in seven is an elite (+50%).
    public static func foe<D: Dice>(dungeon: String, floor: Int, party: [Player], dice: inout D) -> Foe {
        let table = Bestiary.enemies(for: dungeon)
        let boss = floor >= floors
        let pool = boss ? table.bosses : table.pool(forFloor: floor)
        let t = pool.isEmpty ? Bestiary.crypt.t1[0] : pool[dice.roll(0...(pool.count - 1))]
        let n = max(1, party.count)
        let level = max(1, party.map(\.level).reduce(0, +) / n)
        let e = Enemy.spawn(t, floor: floor, playerLevel: level)
        let elite = !boss && floor >= 3 && dice.chance(1.0 / 7)
        let depth = Legacy.depthMult(dungeon)
        let mult = depth * (elite ? 1.5 : 1)
        let hp = jsRound(Double(e.hp) * (1 + 0.7 * Double(n - 1)) * (boss ? 1.6 : 1) * mult)
        let lo = jsRound(Double(e.atk.lowerBound) * mult), hi = jsRound(Double(e.atk.upperBound) * mult)
        return Foe(name: (elite ? "Elite " : "") + e.name, icon: e.icon, hp: hp, maxHp: hp,
                   atkLo: lo, atkHi: max(lo, hi), boss: boss, elite: elite)
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
    /// choice (time ran out) attack. An action that can't happen (no SP, no
    /// potion, no shots) is an attack instead.
    public static func resolve<D: Dice>(party: [Player], foe: Foe, actions: [String: String], dice: inout D) -> Round {
        var r = Round(party: party, foe: foe)
        var defending = Set<String>()
        var guardOf: [String: String] = [:]          // protected id → protector id
        for i in r.party.indices { r.party[i].dealt = 0 }

        // Only those standing when the round starts act (a friend revived
        // this round gets up, but doesn't swing until the next one).
        let acting = r.party.indices.filter { r.party[$0].alive }
        for i in acting {
            let p = r.party[i]
            var a = actions[p.id].flatMap(Action.init) ?? .attack
            switch a {
            case .potion where p.potions <= 0, .gun where p.shots <= 0 || !p.hasGun: a = .attack
            case .skill(let id):
                if let s = p.skills.first(where: { $0.id == id }), p.sp >= s.sp {} else { a = .attack }
            case .revive(let id):
                if p.potions <= 0 || !(r.party.contains { $0.id == id && !$0.alive }) { a = .attack }
            case .protect(let id):
                if id == p.id || !(r.party.contains { $0.id == id && $0.alive }) { a = .defend }
            default: break
            }

            switch a {
            case .potion:
                let heal = jsRound(Double(p.maxHp) * 0.4)
                r.party[i].hp = min(p.maxHp, p.hp + heal)
                r.party[i].potions -= 1
                r.lines.append("🧪 \(p.name) drinks a potion: +\(heal) HP (\(r.party[i].hp) of \(p.maxHp)).")
                continue
            case .revive(let id):
                guard let t = r.party.firstIndex(where: { $0.id == id }) else { continue }
                r.party[i].potions -= 1
                r.party[t].hp = max(1, jsRound(Double(r.party[t].maxHp) * 0.35))
                r.lines.append("💫 \(p.name) pours a potion on \(r.party[t].name), who gets back up with \(r.party[t].hp) HP!")
                continue
            case .protect(let id):
                guardOf[id] = p.id
                defending.insert(p.id)
                let name = r.party.first { $0.id == id }?.name ?? "an ally"
                r.lines.append("🛡 \(p.name) stands in front of \(name).")
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
            case .gun:
                dmg = dice.roll(p.gunLo...p.gunHi) + p.atkLo / 2
                r.party[i].shots -= 1
                line = "🔫 \(p.name) fires \(p.gunName) for \(dmg)"
            case .skill(let id):
                let s = p.skills.first { $0.id == id }!
                r.party[i].sp -= s.sp
                dmg = jsRound(Double(dmg) * s.dmg) + jsRound(Double(r.foe.maxHp) * s.pct) + s.flat
                var extra: [String] = []
                if s.heal > 0 || s.healPct > 0 {
                    let targets = s.team ? r.party.indices.filter { r.party[$0].alive } : [i]
                    for t in targets {
                        let amt = s.heal + jsRound(Double(r.party[t].maxHp) * s.healPct)
                        r.party[t].hp = min(r.party[t].maxHp, r.party[t].hp + amt)
                    }
                    let amt = s.heal + jsRound(Double(p.maxHp) * s.healPct)
                    extra.append(s.team ? "the party heals \(amt)" : "heals \(amt)")
                }
                if s.shield > 0 { r.party[i].shield += s.shield; extra.append("a \(s.shield) shield") }
                if s.stun > 0 { r.foe.stun = max(r.foe.stun, s.stun); extra.append("\(r.foe.name) is stunned") }
                if s.dot > 0 { r.foe.dot = max(r.foe.dot, s.dot); r.foe.dotTurns = max(r.foe.dotTurns, s.dotTurns); extra.append("\(s.dot) a round for \(s.dotTurns) rounds") }
                if s.weaken < 1 { r.foe.weaken = max(0.4, r.foe.weaken * s.weaken); extra.append("\(r.foe.name) hits softer") }
                line = "\(s.icon) \(p.name) uses \(s.name)" + (dmg > 0 ? " for \(dmg)" : "")
                    + (extra.isEmpty ? "" : ": " + extra.joined(separator: ", "))
                if dmg <= 0 {
                    r.lines.append(line + ".")
                    continue
                }
            default:
                if dice.chance(p.crit) {
                    dmg *= 2
                    line = "⚔ \(p.name) lands a CRITICAL hit for \(dmg)"
                } else {
                    line = "⚔ \(p.name) hits for \(dmg)"
                }
            }
            r.foe.hp = max(0, r.foe.hp - dmg)
            r.party[i].dealt = dmg
            r.lines.append(line + (r.foe.hp > 0 ? "." : " — \(r.foe.name) falls!"))
        }

        // Burning, bleeding, poison: the enemy's damage over time.
        if r.foe.hp > 0 && r.foe.dotTurns > 0 && r.foe.dot > 0 {
            r.foe.hp = max(0, r.foe.hp - r.foe.dot)
            r.foe.dotTurns -= 1
            r.lines.append("🩸 \(r.foe.name) takes \(r.foe.dot) more damage" + (r.foe.hp > 0 ? "." : " and falls!"))
        }
        if r.foe.hp <= 0 {
            r.foeDown = true
            return r
        }

        // The boss changes phase: stronger, and it strikes everyone once.
        var sweep = false
        if r.foe.boss {
            let phase = r.foe.hp * 3 <= r.foe.maxHp ? 3 : r.foe.hp * 3 <= r.foe.maxHp * 2 ? 2 : 1
            if phase > r.foe.phase {
                r.foe.phase = phase
                sweep = true
                r.lines.append(phase == 2 ? "⚡ \(r.foe.name) roars and changes! It hits harder now."
                                          : "🔥 \(r.foe.name) is desperate. Its final phase begins!")
            }
        }

        if r.foe.stun > 0 {
            r.foe.stun -= 1
            r.lines.append("💫 \(r.foe.name) is stunned and can't attack.")
        } else if sweep {
            for t in r.party.indices where r.party[t].alive {
                hurt(&r, t, max(1, dice.roll(r.foe.attack) * 2 / 3), defending: defending, prefix: "\(r.foe.icon) The blast hits")
            }
        } else {
            // The weakest player (by share of HP), or whoever hit it hardest.
            let standing = r.party.indices.filter { r.party[$0].alive }
            if !standing.isEmpty {
                var t: Int
                if dice.chance(0.5) {
                    t = standing.min { Double(r.party[$0].hp) / Double(r.party[$0].maxHp) < Double(r.party[$1].hp) / Double(r.party[$1].maxHp) }!
                } else if let top = standing.max(by: { r.party[$0].dealt < r.party[$1].dealt }), r.party[top].dealt > 0 {
                    t = top
                } else {
                    t = standing[dice.roll(0...(standing.count - 1))]
                }
                // A protector takes the hit instead.
                if let pid = guardOf[r.party[t].id], let g = r.party.firstIndex(where: { $0.id == pid }), r.party[g].alive {
                    r.lines.append("🛡 \(r.party[g].name) takes the hit for \(r.party[t].name)!")
                    t = g
                }
                hurt(&r, t, dice.roll(r.foe.attack), defending: defending, prefix: "\(r.foe.icon) \(r.foe.name) strikes")
            }
        }
        r.partyDown = !r.party.contains { $0.alive }
        r.lines.append("\(r.foe.name): \(r.foe.hp) of \(r.foe.maxHp) HP.")
        for i in r.party.indices where r.party[i].alive { r.party[i].sp = min(r.party[i].maxSp, r.party[i].sp + spPerRound) }
        return r
    }

    private static func hurt(_ r: inout Round, _ t: Int, _ raw: Int, defending: Set<String>, prefix: String) {
        let p = r.party[t]
        var dmg = max(1, raw - p.def / 2)
        if defending.contains(p.id) { dmg = max(1, dmg / 2) }
        if p.shield > 0 {
            let soak = min(p.shield, dmg)
            r.party[t].shield -= soak
            dmg -= soak
        }
        r.party[t].hp = max(0, p.hp - dmg)
        r.lines.append("\(prefix) \(p.name) for \(dmg)" + (r.party[t].hp > 0
            ? " (\(r.party[t].hp) of \(p.maxHp) HP)." : " — \(p.name) is down!"))
    }

    /// Between fights: everyone heals 15% and the gun is reloaded. Between
    /// floors (floor: true) the downed get back up with 30% HP and SP fills.
    public static func rest(_ party: [Player], floor: Bool) -> [Player] {
        party.map { p in
            var q = p
            q.shots = p.gunShots
            q.shield = 0
            q.dealt = 0
            if p.alive {
                q.hp = min(p.maxHp, p.hp + jsRound(Double(p.maxHp) * (floor ? 0.25 : 0.15)))
            } else if floor {
                q.hp = jsRound(Double(p.maxHp) * 0.3)
            }
            if floor { q.sp = p.maxSp }
            return q
        }
    }

    // MARK: Rewards (each player, on their own device)

    /// 100 gold a floor cleared, and 1,000 more for beating the boss.
    public static func gold(floorsCleared: Int, won: Bool) -> Int { 100 * max(0, floorsCleared) + (won ? 1000 : 0) }

    /// XP for the character's real level (the Endless Descent curve): 60 a
    /// floor cleared, more deeper down, and 500 for the boss.
    public static func xp(floorsCleared: Int, won: Bool) -> Int {
        (0..<max(0, floorsCleared)).reduce(0) { $0 + 60 + $1 * 15 } + (won ? 500 : 0)
    }

    /// A room code: four letters and digits people can say out loud.
    public static func code<D: Dice>(dice: inout D) -> String {
        let chars = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<4).map { _ in chars[dice.roll(0...(chars.count - 1))] })
    }
}

// MARK: - Raid Boss (12.1)

/// A giant boss for the whole party in one long fight: much more HP than a
/// dungeon boss, it hits harder, changes phase twice (striking everyone),
/// and enrages after 20 rounds. Beating it pays gold, XP, diamonds and a
/// piece of gear; the diamonds and gear once a day for each character.
extension Coop {
    public struct RaidBoss: Sendable, Equatable {
        public let id: String
        public let name: String
        public let icon: String
        /// The dungeon its strength and its gear come from.
        public let home: String
        public let lore: String
    }

    public static let raidBosses: [RaidBoss] = [
        RaidBoss(id: "colossus", name: "The Hollow Colossus", icon: "🗿", home: "Crypt of Malachar",
                 lore: "A giant of fused bone that walks the crypt's lowest halls. Every warrior it has crushed is part of it now."),
        RaidBoss(id: "tyrant", name: "Vyrmathra, the Ember Tyrant", icon: "🐉", home: "The Ashbound Wastes",
                 lore: "The dragon whose breath made the Wastes. It wakes when enough heroes gather to make waking worth it."),
        RaidBoss(id: "drowned", name: "The Drowned King", icon: "🌊", home: "The Sunken Archives",
                 lore: "He ruled the Archives before the water came, and he still holds court beneath it."),
        RaidBoss(id: "frostmother", name: "The Frost Mother", icon: "❄️", home: "Frosthold Abyss",
                 lore: "Older than the ice. Her children are the cold; her voice is the wind that freezes breath mid-word."),
    ]

    public static func raidBoss(_ id: String) -> RaidBoss { raidBosses.first { $0.id == id } ?? raidBosses[0] }

    /// Rounds before it enrages (its attack doubles).
    public static let raidEnrageRound = 20

    /// Its home dungeon's floor 10 boss for this party, with three times
    /// the HP and 15% more attack, under the raid boss's own name.
    public static func raidFoe<D: Dice>(_ b: RaidBoss, party: [Player], dice: inout D) -> Foe {
        let base = foe(dungeon: b.home, floor: floors, party: party, dice: &dice)
        let hp = base.maxHp * 3
        let lo = jsRound(Double(base.atkLo) * 1.15), hi = jsRound(Double(base.atkHi) * 1.15)
        return Foe(name: b.name, icon: b.icon, hp: hp, maxHp: hp, atkLo: lo, atkHi: max(lo, hi), boss: true)
    }

    /// Enraged: twice the attack, once.
    public static func enrage(_ f: Foe) -> Foe {
        var e = f
        e.atkLo *= 2
        e.atkHi *= 2
        return e
    }

    /// Each player's rewards. Gold and XP every time; diamonds and gear only
    /// on the first win of the day (`daily`).
    public struct RaidReward: Equatable, Sendable {
        public var gold: Int
        public var xp: Int
        public var diamonds: Int
        public var item: Item?
    }

    public static func raidReward<D: Dice>(_ b: RaidBoss, won: Bool, daily: Bool, dice: inout D) -> RaidReward {
        guard won else { return RaidReward(gold: 200, xp: 150, diamonds: 0, item: nil) }
        var r = RaidReward(gold: 2500, xp: 1200, diamonds: 0, item: nil)
        if daily {
            r.diamonds = 5
            let gear = ItemTables.loot(for: b.home).filter { $0.isWeapon || $0.isArmor }
            if !gear.isEmpty {
                var item = gear[dice.roll(0...(gear.count - 1))]
                item.level = max(item.level ?? 1, 3)
                item.name = "Raid " + item.name
                r.item = item
            }
        }
        return r
    }
}
