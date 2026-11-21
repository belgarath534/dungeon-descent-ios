import Foundation

/// THE HUNTING GROUNDS: send a character into the forest and listen. Every
/// 25–45 seconds something happens (a fight, a find, a rest), narrated by
/// Brian. It pays gold and Bounty Rank XP (dd_bounty_rank), and ranks make
/// the forest richer.
public enum Hunt {
    public struct Rank: Sendable, Equatable {
        public let rank: Int, name: String, xpNeeded: Int, desc: String
    }

    /// BOUNTY_RANKS
    public static let ranks: [Rank] = [
        Rank(rank: 1, name: "Scout", xpNeeded: 0, desc: "Basic bounties available."),
        Rank(rank: 2, name: "Tracker", xpNeeded: 100, desc: "Rare items found in forest."),
        Rank(rank: 3, name: "Hunter", xpNeeded: 250, desc: "Elite bounties unlocked."),
        Rank(rank: 4, name: "Stalker", xpNeeded: 500, desc: "Bonus gold from hunts."),
        Rank(rank: 5, name: "Predator", xpNeeded: 900, desc: "Legendary items can drop."),
        Rank(rank: 6, name: "Warden", xpNeeded: 1400, desc: "Hunt duration increased."),
        Rank(rank: 7, name: "Shadowblade", xpNeeded: 2000, desc: "Critical hunt strikes unlocked."),
        Rank(rank: 8, name: "Deathstalker", xpNeeded: 2800, desc: "Legendary bounties unlocked."),
        Rank(rank: 9, name: "Forest Reaper", xpNeeded: 3800, desc: "Maximum bounty rewards."),
        Rank(rank: 10, name: "The Unseen", xpNeeded: 5000, desc: "Master hunter. All rewards unlocked."),
    ]

    /// getBountyRankData: {"rank":1,"xp":0}
    public static func xp(_ store: GameStore) -> Int {
        guard let s = store.getItem("dd_bounty_rank"), let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return 0 }
        return (o["xp"] as? NSNumber)?.intValue ?? 0
    }

    public static func rank(xp: Int) -> Rank { ranks.last { xp >= $0.xpNeeded } ?? ranks[0] }
    public static func rank(_ store: GameStore) -> Rank { rank(xp: xp(store)) }
    public static func next(after r: Rank) -> Rank { ranks[min(r.rank, ranks.count - 1)] }

    /// addBountyXP. Returns the new rank when this was a rank up.
    public static func addXP(_ n: Int, store: GameStore) -> Rank? {
        let before = rank(store)
        let total = xp(store) + n
        let now = rank(xp: total)
        store.setItem("dd_bounty_rank", "{\"rank\":\(now.rank),\"xp\":\(total)}")
        return now.rank > before.rank ? now : nil
    }

    struct Foe { let name: String, hp: Int, atk: ClosedRange<Int>, gold: Int, xp: Int }

    /// HUNT_ENEMIES: the first 2 + rank of them hunt you.
    static let foes: [Foe] = [
        Foe(name: "Shadow Wolf", hp: 60, atk: 8...14, gold: 25, xp: 15),
        Foe(name: "Forest Wraith", hp: 50, atk: 10...16, gold: 30, xp: 18),
        Foe(name: "Cursed Boar", hp: 80, atk: 7...12, gold: 20, xp: 12),
        Foe(name: "Vine Strangler", hp: 70, atk: 9...14, gold: 28, xp: 16),
        Foe(name: "Hollow Scout", hp: 55, atk: 11...17, gold: 35, xp: 20),
        Foe(name: "Night Stalker", hp: 90, atk: 12...18, gold: 40, xp: 25),
        Foe(name: "Bone Archer", hp: 65, atk: 10...15, gold: 32, xp: 18),
        Foe(name: "Swamp Horror", hp: 100, atk: 13...20, gold: 45, xp: 28),
    ]

    struct Find { let name, icon, type, rarity: String; var gold = 0 }

    /// HUNT_ITEMS: rares from rank 5.
    static let finds: [Find] = [
        Find(name: "Iron Scrap", icon: "🪨", type: "material", rarity: "common"),
        Find(name: "Shadow Essence", icon: "🌑", type: "material", rarity: "uncommon"),
        Find(name: "Forest Herb", icon: "🌿", type: "potion", rarity: "common"),
        Find(name: "Bone Fragment", icon: "🦴", type: "material", rarity: "common"),
        Find(name: "Void Crystal", icon: "💎", type: "material", rarity: "rare"),
        Find(name: "Ancient Coin", icon: "🪙", type: "gold", rarity: "uncommon", gold: 50),
        Find(name: "Hunters Rune", icon: "✨", type: "material", rarity: "rare"),
        Find(name: "Dark Pelt", icon: "🐺", type: "material", rarity: "uncommon"),
    ]

    /// HUNT_NARRATION
    public static let narration: [String: [String]] = [
        "enter": ["The forest swallows you whole. Something watches from the dark.", "Leaves crunch beneath your feet. The hunt begins.", "The trees close in. You are not alone here."],
        "enemy": ["Something emerges from the shadows.", "A creature blocks your path.", "You are not alone. Something approaches.", "The undergrowth stirs. An enemy reveals itself."],
        "kill": ["The creature falls. The forest grows quiet.", "Another enemy defeated. Your blade runs dark.", "It is done. You press deeper into the forest.", "The hunt continues. Another falls before you."],
        "item": ["Something catches your eye in the dirt.", "A glint in the darkness. You reach down.", "Among the fallen leaves, you find something useful."],
        "hurt": ["You take a wound. Stay focused.", "The enemy draws blood. Keep moving.", "That one hurt. You press on regardless."],
        "lowHp": ["Your wounds are severe. The forest senses weakness.", "You are bleeding. The darkness grows bolder.", "Critical condition. One more hit could end this hunt."],
        "rest": ["A moment of stillness. You catch your breath.", "The forest is quiet for now.", "Nothing stirs. You recover slightly."],
        "return": ["You emerge from the forest. The hunt is over.", "Daylight returns. You carry your spoils home.", "The forest releases you. For now."],
    ]

    public static func say(_ kind: String, dice: inout some Dice) -> String {
        let l = narration[kind] ?? ["The hunt continues."]
        return l[dice.roll(0...(l.count - 1))]
    }

    /// The hunter: the character's class stats. (The web version read HP and
    /// attack fields characters don't have, so every hunter was the same
    /// 100 HP, 8–14 attack nobody.)
    public struct Hunter: Equatable, Sendable {
        public let name: String
        public var hp, maxHp: Int
        public let atk: ClosedRange<Int>
        public let def: Int
        public var kills = 0, items = 0, gold = 0

        public init(_ ch: PlayerCharacter) {
            let info = GameData.classInfo(ch.cls)
            name = ch.name
            maxHp = info.maxHp
            hp = info.maxHp
            atk = info.atk
            def = info.def
        }
        public var dead: Bool { hp <= 0 }
    }

    /// What one moment of the hunt did.
    public struct Moment: Sendable {
        /// Lines for the hunt log.
        public var log: [String] = []
        /// What Brian says (nil: he stays quiet this time).
        public var brian: [String] = []
        public var gold = 0
        public var xp = 0
        /// A find for your saved items.
        public var item: Item? = nil
        public var killed: String? = nil
    }

    /// huntTick: 55% a fight, 20% a find, 15% a rest, 10% nothing.
    public static func tick(_ h: inout Hunter, rank r: Rank, dice: inout some Dice) -> Moment {
        var m = Moment()
        let roll = dice.roll(0...99)
        if roll < 55 { fight(&h, r, &m, dice: &dice) }
        else if roll < 75 { find(&h, r, &m, dice: &dice) }
        else if roll < 90 {
            let heal = jsRound(Double(h.maxHp) * 0.08)
            h.hp = min(h.maxHp, h.hp + heal)
            m.log.append("💚 Rest. Recovered \(heal) HP. (\(h.hp) HP)")
            if dice.chance(0.45) { m.brian.append(say("rest", dice: &dice)) }
        } else {
            m.log.append("The forest is still. Nothing moves.")
        }
        if h.dead {
            h.hp = 0
            m.log.append("💀 \(h.name) has fallen. The hunt ends.")
            m.brian.append("Your hunter has fallen. The forest claims another. The hunt is over.")
        }
        return m
    }

    /// huntEncounterEnemy: you win 55% of fights, 4% more per rank. Your
    /// strength decides how hard a lost fight hits you. From rank 4 kills pay
    /// 30% more; from rank 7 critical strikes (12%) pay double XP.
    static func fight(_ h: inout Hunter, _ r: Rank, _ m: inout Moment, dice: inout some Dice) {
        let pool = foes.prefix(min(foes.count, 2 + r.rank))
        let foe = pool[pool.startIndex + dice.roll(0...(pool.count - 1))]
        m.log.append("⚔️ \(foe.name) appears!")
        let crit = dice.chance(0.12)
        if dice.chance(0.55 + Double(r.rank) * 0.04) {
            let gold = foe.gold + (r.rank >= 4 ? jsRound(Double(foe.gold) * 0.3) : 0)
            let xp = foe.xp * (crit && r.rank >= 7 ? 2 : 1)
            h.kills += 1
            h.gold += gold
            m.gold = gold
            m.xp = xp
            m.killed = foe.name
            m.log.append((crit ? "💥 CRITICAL! " : "") + "Defeated \(foe.name). +\(gold)g +\(xp) XP")
            if dice.chance(0.70) {
                m.brian.append(say("enemy", dice: &dice))
                m.brian.append(say("kill", dice: &dice))
            }
            if [10, 25, 50].contains(h.kills) { m.brian.append("Remarkable. \(h.kills) enemies have fallen before you.") }
        } else {
            let hit = max(1, dice.roll(foe.atk) - h.def)
            h.hp -= hit
            m.log.append("🩸 \(foe.name) wounds you for \(hit) damage. (\(max(0, h.hp)) HP)")
            if Double(h.hp) < Double(h.maxHp) * 0.3 { m.brian.append(say("lowHp", dice: &dice)) }
            else if dice.chance(0.65) { m.brian.append(say("hurt", dice: &dice)) }
        }
    }

    /// huntFindItem: 8 rank XP for every find.
    static func find(_ h: inout Hunter, _ r: Rank, _ m: inout Moment, dice: inout some Dice) {
        let pool = r.rank >= 5 ? finds : finds.filter { $0.rarity != "rare" }
        let f = pool[dice.roll(0...(pool.count - 1))]
        h.items += 1
        m.xp = 8
        m.log.append("✨ Found: \(f.icon) \(f.name) (\(f.rarity))")
        if f.type == "gold" {
            h.gold += f.gold
            m.gold = f.gold
            m.log.append("  → +\(f.gold) gold")
            if dice.chance(0.55) { m.brian.append("An ancient coin catches the light. Worth \(f.gold) gold.") }
        } else {
            m.item = Item(name: f.name, icon: f.icon, type: f.type, desc: "Found in the Hunting Grounds.", heal: f.type == "potion" ? 30 : nil)
            if f.rarity == "rare" { m.brian.append(say("item", dice: &dice) + " Something rare. \(f.name).") }
            else if dice.chance(0.55) { m.brian.append(say("item", dice: &dice) + " \(f.name).") }
        }
    }
}
