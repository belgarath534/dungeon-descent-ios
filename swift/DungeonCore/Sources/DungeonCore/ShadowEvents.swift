import Foundation

/// The Shadow World's events (THE SHADOW WORLD EVENTS in DUNGEON_EVENTS):
/// The Mirror, The Voice, The Handwriting, The Offering, the Security Room and
/// The Two Doors. Their corruption is Shadow Corruption: the web version
/// added it with the Whispering Forest's meter, which ignores every other
/// dungeon, so these events never corrupted anyone.
public enum ShadowEvents {
    /// _DOOR_DESCS
    static let doors: [(String, String)] = [
        ("A door that looks exactly like every other door you have ever opened.",
         "A door with no handle. You are not sure how it opens. You are not sure it does."),
        ("A door that is slightly warm to the touch.",
         "A door that has your name carved into it in handwriting you do not recognize."),
        ("A door with light coming from under it. The light is the wrong color.",
         "A door that sounds like it is breathing. Very slowly. Very deeply."),
        ("A door made of something that is not wood and is not stone.",
         "A door that was not there when you entered this corridor."),
        ("A door that feels like it is watching you decide.",
         "A door that opens before you touch it, then closes when you step back."),
    ]

    /// The Security Room's clock, once its announcement has had time to be heard.
    public static let securitySeconds = 15.0

    /// Where the Security Room's Darkness Swallower is, for the growl.
    public static func securityDirection(_ id: String?) -> Compass? {
        guard let id, id.hasPrefix("shadow-security-") else { return nil }
        return Compass(rawValue: String(id.dropFirst("shadow-security-".count)))
    }

    static func has(_ run: Run, _ shadowItem: String) -> Bool {
        run.inventory.contains { $0.extra["shadowItem"] == .string(shadowItem) }
    }

    /// One of SHADOW_LOOT, into your bag.
    static func loot(_ run: inout Run, dice: inout some Dice) -> Item? {
        let table = GameContent.shared.dungeon(ShadowWorld.name).loot
        guard !table.isEmpty else { return nil }
        let item = table[dice.roll(0...(table.count - 1))]
        run.inventory.append(item)
        return item
    }

    static func corrupt(_ run: inout Run, _ n: Int, _ source: String) -> String {
        var log: [String] = []
        ShadowWorld.corrupt(&run, n, source: source, log: &log)
        return log.isEmpty ? "" : " " + log.joined(separator: " ")
    }

    static func choose(_ id: String, _ choice: Int, _ run: inout Run, dice: inout some Dice, wallet: Wallet) -> Encounters.Outcome {
        let before = run.gold
        let out = outcome(id, choice, &run, dice: &dice)
        if run.gold > before { wallet.addGold(run.gold - before) }
        return out
    }

    static func outcome(_ id: String, _ choice: Int, _ run: inout Run, dice: inout some Dice) -> Encounters.Outcome {
        typealias Outcome = Encounters.Outcome
        if let dir = securityDirection(id) { return security(dir, choice, &run, dice: &dice) }
        if id.hasPrefix("shadow-two-doors-") { return twoDoors(choice, &run, dice: &dice) }
        switch (id, choice) {
        case ("shadow-mirror", 0):
            run.hp = run.maxHp
            return Outcome(message: "Your reflection smiles as you trade places. You are at full health. Something is different now." + corrupt(&run, 2, "The Mirror"))
        case ("shadow-mirror", 2):
            if dice.chance(0.5) {
                let shard = Item(name: "Mirror Shard", icon: "🔷", type: "atk-potion",
                                 desc: "A shard of the shadow mirror. +15 ATK for 3 turns when used.", atk: 15)
                run.inventory.append(shard)
                return Outcome(message: "The mirror shatters. Something bright falls from it. You pick up a Mirror Shard: plus 15 attack for 3 turns when used.", item: shard)
            }
            return Outcome(message: "The shards cut you as they fall. Shadow seeps from the cracks into you." + corrupt(&run, 1, "Mirror shards"))
        case ("shadow-mirror", _):
            return Outcome(message: "You walk past. The mirror shows your reflection walking in the opposite direction. You do not look back.")
        case ("shadow-voice", 0):
            if dice.chance(0.6) {
                run.gold += 120
                return Outcome(message: "You find a cache of 120 gold where the voice led. You understand now. Your future self was trying to help.", gold: 120)
            }
            var echo = Enemy(name: "The Echo", icon: "🔄", hp: 80, maxHp: 80, atk: 10...18, gold: 12...20)
            echo.desc = "It was imitating your voice. It has been waiting."
            echo.mechanics["isEcho"] = .bool(true)
            echo.mechanics["corruptOnHit"] = .number(1)
            return Outcome(message: "The voice was not yours. An Echo steps out of the dark. Its hits add corruption.", enemy: echo)
        case ("shadow-voice", _):
            return Outcome(message: "You keep walking. Behind you, your voice says the frightened words anyway. You do not hear what they were.")
        case ("shadow-handwriting", 0):
            run.shadowNotes = true
            return Outcome(message: "📝 You study the notes. Your next attack is a guaranteed critical hit. You already knew this somehow.")
        case ("shadow-handwriting", _):
            return Outcome(message: "You walk past. The notes fade as you leave, as if they were only there for you.")
        case ("shadow-offering", 0):
            let cloth = has(run, "offeringCloth")
            // The Offering Cloth guarantees a real gift: loot or gold.
            let roll = cloth ? dice.roll(0...1) : dice.roll(0...2)
            let note = cloth ? "🩶 Offering Cloth — the shadow guarantees its gift is real. " : ""
            if roll == 0, let item = loot(&run, dice: &dice) {
                return Outcome(message: note + "Inside — \(item.name). The offering was genuine. You are not sure that is a good thing.", item: item)
            }
            if roll <= 1 {
                run.gold += 80
                return Outcome(message: note + "Inside — 80 gold. The shadow knows what you need. That is terrifying.", gold: 80)
            }
            return Outcome(message: "Inside — nothing. The shadow was empty. The corruption was in the act of taking." + corrupt(&run, 2, "The Offering"))
        case ("shadow-offering", _):
            return Outcome(message: "You walk past. When you look back, it is gone. It was only ever meant for you.")
        default:
            return Outcome(message: "")
        }
    }

    /// chooseDoor: 40% a chest, 35% something waiting, 25% shadow passing
    /// through you. The Door Key always finds the chest.
    static func twoDoors(_ choice: Int, _ run: inout Run, dice: inout some Dice) -> Encounters.Outcome {
        let n = choice + 1
        let key = has(run, "doorKey")
        let roll = key ? 0 : dice.roll(0...99)
        let note = key ? "🗝️ Door Key — the good path is revealed. " : ""
        if roll < 40 {
            let item = loot(&run, dice: &dice)
            run.gold += 60
            return Encounters.Outcome(message: note + "🚪 Door \(n) opens into a small room. A chest. Inside — \(item.map { $0.name + " and " } ?? "")60 gold. The other door was probably worse.",
                                      item: item, gold: 60)
        }
        if roll < 75 {
            let t = Bestiary.enemies(for: ShadowWorld.name, difficulty: run.difficulty)
            let pool = run.floor <= 3 ? t.t1 : run.floor <= 6 ? t.t2 : t.t3
            if !pool.isEmpty {
                let e = Enemy.spawn(pool[dice.roll(0...(pool.count - 1))], floor: run.floor, playerLevel: run.level,
                                    ngPlusCount: Combat.ngCount(run))
                return Encounters.Outcome(message: "🚪 Door \(n) opens. \(e.name) was waiting behind it. Fight.", enemy: e)
            }
        }
        return Encounters.Outcome(message: "🚪 Door \(n) opens into darkness. Something passes through you as you enter." + corrupt(&run, 1, "The Wrong Door"))
    }

    /// securityRoomEscape / securityRoomCaught. A choice of -1 is time running out.
    static func security(_ swallower: Compass, _ choice: Int, _ run: inout Run, dice: inout some Dice) -> Encounters.Outcome {
        let chosen = Compass.allCases.indices.contains(choice) ? Compass.allCases[choice] : nil
        if let c = chosen, c == swallower.opposite {
            let item = loot(&run, dice: &dice)
            run.gold += 50
            return Encounters.Outcome(message: "📹 You escaped! The Darkness Swallower was on the \(swallower.rawValue) camera and you fled \(c.rawValue). The room rewards the aware. You found \(item.map { $0.name + " and " } ?? "")50 gold.",
                                      item: item, gold: 50)
        }
        let dmg = jsRound(Double(run.maxHp) * 0.30)
        run.hp = max(1, run.hp - dmg)
        let why = chosen == nil
            ? "📹 Time ran out. The Darkness Swallower was on the \(swallower.rawValue) camera. It was already behind you."
            : "📹 Wrong direction. The Darkness Swallower was on the \(swallower.rawValue) camera. You ran straight toward it."
        return Encounters.Outcome(message: why + " \(dmg) shadow damage." + corrupt(&run, 1, "Security Room"))
    }
}
