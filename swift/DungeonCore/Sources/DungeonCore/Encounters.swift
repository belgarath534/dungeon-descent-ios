import Foundation

/// Special rooms and dungeon events. Ports of SPECIAL_ROOMS / generateFloorRooms
/// and DUNGEON_EVENTS / rollDungeonEvent.
public enum Encounters {
    // MARK: Special rooms

    public struct SpecialRoom: Sendable {
        public let type: String
        public let icon: String
        public let name: String
        public let desc: String
        let chance: Double
    }

    public static let specialRooms: [SpecialRoom] = [
        SpecialRoom(type: "treasure", icon: "💎", name: "Treasure Chamber",
                    desc: "The walls glitter with forgotten wealth. No enemies — just riches waiting to be claimed.", chance: 0.10),
        SpecialRoom(type: "rest", icon: "🕯️", name: "Sanctuary",
                    desc: "A moment of stillness. Ancient candles burn. The darkness holds no threat here.", chance: 0.08),
        SpecialRoom(type: "cursed", icon: "💀", name: "Cursed Chamber",
                    desc: "Dark energy radiates from the walls. Something powerful stirs. The reward will be great — if you survive.", chance: 0.08),
        SpecialRoom(type: "secret", icon: "🔍", name: "Hidden Passage",
                    desc: "A crack in the wall reveals a forgotten path. Someone was here before you.", chance: 0.07),
        SpecialRoom(type: "merchant", icon: "🛒", name: "Wandering Merchant",
                    desc: "A hooded figure sits cross-legged in the darkness, wares spread before them.", chance: 0.06),
    ]

    /// Plans the floor: the first and last rooms are normal, the ones between
    /// may be special (generateFloorRooms).
    public static func planFloor(_ run: inout Run, dice: inout some Dice) {
        let total = max(1, run.floorRoomsNeeded)
        var plan = ["normal"]
        if total > 2 {
            for _ in 1..<(total - 1) {
                var roll = 0.0
                // One roll against the running total, done as a chain of chances.
                var picked = "normal"
                for room in specialRooms {
                    let chance = room.type == "merchant" ? Festival.merchantChance(run, room.chance) : room.chance
                    if dice.chance(chance / max(0.0001, 1 - roll)) { picked = room.type; break }
                    roll += chance
                }
                plan.append(picked)
            }
        }
        if total > 1 { plan.append("normal") }
        run.roomPlan = plan
    }

    /// The planned type of the room being entered (roomsOnFloor already counts it).
    public static func plannedRoom(_ run: Run) -> SpecialRoom? {
        let i = run.roomsOnFloor - 1
        guard run.roomPlan.indices.contains(i) else { return nil }
        return specialRooms.first { $0.type == run.roomPlan[i] }
    }

    public struct Outcome: Sendable {
        public var message: String
        public var enemy: Enemy? = nil
        public var openShop = false
        public var item: Item? = nil
        public var gold = 0
        public var playerDied = false
        /// An achievement stat to count (dd_ach_stats).
        public var stat: String? = nil
        /// A music track to play over the moment.
        public var music: String? = nil
        /// Nothing happened yet (a requirement wasn't met): the choice stays open.
        public var retry = false
        /// A spirit to keep for good.
        public var spirit: String? = nil
        /// A Void Fragment for the Void Chronicles.
        public var voidFragment = false
    }

    public static func enterSpecial(_ room: SpecialRoom, _ run: inout Run, dice: inout some Dice,
                                    wallet: Wallet, store: GameStore) -> Outcome {
        switch room.type {
        case "treasure":
            let gold = 20 + run.floor * 5
            run.gold += gold
            wallet.addGold(gold)
            var msg = "💎 Treasure Chamber! +\(gold) gold"
            let loot = ItemTables.loot(for: run.dungeon)
            var found: Item?
            if !loot.isEmpty {
                let item = loot[dice.roll(0...(loot.count - 1))]
                let got = Inventory.pickUp(&run, item, wallet: wallet)
                if got.kept != nil { found = item; msg += " and found \(item.name)" }
            }
            msg += "."
            if dice.chance(0.30) {
                let coins = (jsParseInt(store.getItem("dd_mystery_coins")) ?? 0) + 1
                store.setItem("dd_mystery_coins", String(coins))
                msg += " +1 mystery coin!"
            }
            if dice.chance(0.10) {
                wallet.addDiamonds(1)
                msg += " +1 diamond!"
            }
            return Outcome(message: msg + " No enemies here.", item: found, gold: gold)
        case "rest":
            let heal = jsRound(Double(run.maxHp) * 0.20)
            run.hp = min(run.maxHp, run.hp + heal)
            run.sp = min(run.maxSp, run.sp + 10)
            return Outcome(message: "🕯️ Sanctuary. You rest briefly. Restored \(heal) HP and 10 SP. No enemies here.")
        case "cursed":
            // The web version looked this enemy up in the wrong kind of table, so the
            // Cursed Chamber never actually spawned one. This is what it meant to do.
            let base = Combat.nextEnemy(for: run, dice: &dice)
            var e = base
            e.name = "Cursed " + base.name
            e.hp = jsRound(Double(base.hp) * 1.8)
            e.maxHp = e.hp
            e.gold = (base.gold.lowerBound * 3)...(base.gold.upperBound * 3)
            return Outcome(message: "💀 Cursed Chamber! A \(e.name) blocks your path. It is stronger than normal but carries triple gold.", enemy: e)
        case "secret":
            let gold = 15 + run.floor * 3
            run.gold += gold
            wallet.addGold(gold)
            let loot = ItemTables.loot(for: run.dungeon)
            if dice.chance(0.4), !loot.isEmpty {
                let item = loot[dice.roll(0...(loot.count - 1))]
                _ = Inventory.pickUp(&run, item, wallet: wallet)
                return Outcome(message: "🔍 Hidden Passage. You find \(gold) gold and \(item.name) tucked away in the dark.", item: item, gold: gold)
            }
            return Outcome(message: "🔍 Hidden Passage. You find \(gold) gold hidden in the shadows.", gold: gold)
        case "merchant":
            return Outcome(message: "🛒 Wandering Merchant! A trader has set up shop here.", openShop: true)
        default:
            return Outcome(message: room.desc)
        }
    }

    // MARK: Dungeon events

    public struct Event: Sendable {
        public let id: String
        public let title: String
        public let text: String
        public let choices: [String]
        let weight: Int
        let dungeons: [String]?
    }

    public static let events: [Event] = [
        Event(id: "abyssal-singing", title: "The Singing",
              text: "From somewhere below, a voice drifts upward through the water. Beautiful. Wrong. A Siren call.",
              choices: ["Follow the voice", "Ignore it"], weight: 2, dungeons: ["The Abyssal Deep"]),
        Event(id: "abyssal-crack", title: "Pressure Crack",
              text: "A crack runs through the wall. Water seeps through it. The pressure here could shatter the room at any moment.",
              choices: ["Seal the crack (costs 10 HP)", "Leave it"], weight: 2, dungeons: ["The Abyssal Deep"]),
        Event(id: "abyssal-ship", title: "The Sunken Ship",
              text: "A wrecked vessel is wedged between the walls. Old. Very old. The hull is intact enough to search.",
              choices: ["Search the ship", "Pass by"], weight: 2, dungeons: ["The Abyssal Deep"]),
        Event(id: "abyssal-shrine", title: "Bioluminescent Shrine",
              text: "A glowing altar rises from the ocean floor. Ancient. The light it produces is alive.",
              choices: ["Pray at the shrine", "Ignore it"], weight: 2, dungeons: ["The Abyssal Deep"]),
        Event(id: "abyssal-witness", title: "The Witness",
              text: "A shark drifts from the dark. Large. Calm. It circles you slowly. It does not attack immediately. It watches. It has been watching for a long time.",
              choices: ["Fight the shark"], weight: 1, dungeons: ["The Abyssal Deep"]),
        Event(id: "julio", title: "A Familiar Stranger",
              text: "A figure sits in the corner of the room. He does not look up. His name tag reads: JULIO. You have no idea who this is or how he got here.",
              choices: ["Talk to Julio", "Offer Julio gold", "Leave quietly"], weight: 1, dungeons: nil),
        Event(id: "shrine", title: "Ancient Shrine",
              text: "A crumbling shrine stands here, still faintly warm. Something about it feels like an offer.",
              choices: ["Pray at the shrine", "Leave it alone"], weight: 3, dungeons: nil),
        Event(id: "chest", title: "Mysterious Chest",
              text: "A chest sits in the middle of the room. It was not here last time someone passed through. Or if it was, it moved.",
              choices: ["Open the chest", "Leave it"], weight: 3, dungeons: nil),
        Event(id: "wounded", title: "Wounded Adventurer",
              text: "A figure slumps against the wall. Still breathing. Their eyes find yours and they hold up one hand — not attacking. Asking.",
              choices: ["Give them a potion", "Keep moving"], weight: 2, dungeons: nil),
        Event(id: "shadow-mirror", title: "The Mirror",
              text: "A mirror stands in the corridor. It should not be here. It shows you — but the version in the mirror is at full health. It looks at you with something like pity. It offers you a deal.",
              choices: ["Accept the deal", "Ignore it", "Shatter it"], weight: 3, dungeons: [ShadowWorld.name]),
        Event(id: "shadow-voice", title: "The Voice",
              text: "You hear your own voice coming from the next room. It says something you have not said yet. It sounds frightened. You recognize the words — you will say them eventually. The question is when.",
              choices: ["Follow the voice", "Ignore it and move on"], weight: 3, dungeons: [ShadowWorld.name]),
        Event(id: "shadow-handwriting", title: "The Handwriting",
              text: "Notes on the wall. Your handwriting. You have no memory of writing them. They describe the next enemy in precise detail — its weaknesses, its patterns, how it moves. You do not know how you knew this.",
              choices: ["Read the notes carefully", "Ignore them"], weight: 3, dungeons: [ShadowWorld.name]),
        Event(id: "shadow-offering", title: "The Offering",
              text: "Something left on the floor. It was not there a moment ago. It is wrapped in shadow cloth. It is addressed to you — your name, your class, your current floor. Whatever left it knows exactly who you are.",
              choices: ["Take it", "Leave it"], weight: 3, dungeons: [ShadowWorld.name]),
        Event(id: "shadow-security-room", title: "The Security Room", text: "", choices: [], weight: 2, dungeons: [ShadowWorld.name]),
        Event(id: "shadow-two-doors", title: "The Two Doors", text: "", choices: [], weight: 2, dungeons: [ShadowWorld.name]),
        Event(id: "inscription", title: "Ancient Inscription",
              text: "Words carved into the wall in a language older than this kingdom. You can read three of them. They say something about what is below.",
              choices: ["Study the inscription", "Move on"], weight: 2, dungeons: nil),
    ]

    /// An event by id. The Two Doors and the Security Room carry their roll in
    /// the id ("shadow-two-doors-2", "shadow-security-east").
    public static func event(_ id: String) -> Event? {
        if id.hasPrefix("shadow-two-doors-"), let n = Int(id.dropFirst("shadow-two-doors-".count)), ShadowEvents.doors.indices.contains(n) {
            let d = ShadowEvents.doors[n]
            return Event(id: id, title: "The Two Doors",
                         text: "The corridor ends in two doors. There is no going back. You must choose one. The dungeon does not offer alternatives. Door one: \(d.0) Door two: \(d.1)",
                         choices: ["Door One: \(d.0)", "Door Two: \(d.1)"], weight: 0, dungeons: nil)
        }
        if id.hasPrefix("shadow-security-"), let dir = Compass(rawValue: String(id.dropFirst("shadow-security-".count))) {
            return Event(id: id, title: "The Security Room",
                         text: "Four camera feeds — North, South, East, West. The Darkness Swallower is on one feed. Listen for the growl: it comes from its camera. Then escape the opposite direction. You have \(Int(ShadowEvents.securitySeconds)) seconds. The growl is coming from the \(dir.rawValue).",
                         choices: Compass.allCases.map { "Escape \($0.rawValue)" }, weight: 0, dungeons: nil)
        }
        if let e = HollowEvents.event(id) { return e }
        if let e = SpecialEncounters.event(id) { return e }
        return events.first { $0.id == id }
    }

    /// A quiet room has a 10% chance of an event (rollDungeonEvent). General events
    /// don't happen in the Abyssal Deep, which has its own.
    public static func rollEvent(_ run: Run, dice: inout some Dice) -> Event? {
        // The Watching: no event rooms.
        guard !RunModifiers.noEvents(run), dice.chance(0.10) else { return nil }
        var pool: [Event] = []
        for e in events {
            if let d = e.dungeons, !d.contains(run.dungeon) { continue }
            if e.dungeons == nil && (run.dungeon == "The Abyssal Deep" || run.dungeon == ShadowWorld.name) { continue }
            pool += Array(repeating: e, count: e.weight)
        }
        guard !pool.isEmpty else { return nil }
        let e = pool[dice.roll(0...(pool.count - 1))]
        if e.id == "shadow-two-doors" { return event("shadow-two-doors-\(dice.roll(0...(ShadowEvents.doors.count - 1)))") }
        if e.id == "shadow-security-room" { return event("shadow-security-\(Compass.allCases[dice.roll(0...3)].rawValue)") }
        return e
    }

    static let potion = Item(name: "Health Potion", icon: "🧪", type: "potion", desc: "Restores 40 HP.", heal: 40)
    static let greaterPotion = Item(name: "Greater Potion", icon: "💊", type: "potion", desc: "Restores 80 HP.", heal: 80)
    static let spiritTonic = Item(name: "Spirit Tonic", icon: "🔵", type: "sp-potion", desc: "Restores 15 SP.", sp: 15)

    /// Carries out the player's choice for the pending event.
    public static func choose(_ choice: Int, _ run: inout Run, dice: inout some Dice, wallet: Wallet) -> Outcome {
        guard let id = run.pendingEvent else { return Outcome(message: "") }
        run.pendingEvent = nil
        func gold(_ g: Int) { run.gold += g; wallet.addGold(g) }

        if id.hasPrefix("npc-") || ["black-box", "easter-bunny", "easter-bunny-owned", "abyssal-witness"].contains(id) {
            return SpecialEncounters.choose(id, choice, &run, dice: &dice, wallet: wallet)
        }
        if id.hasPrefix("weeping-") { return HollowEvents.choose(id, choice, &run, dice: &dice, wallet: wallet) }
        if id.hasPrefix("shadow-") { return ShadowEvents.choose(id, choice, &run, dice: &dice, wallet: wallet) }

        switch (id, choice) {
        case ("abyssal-singing", 0):
            if dice.chance(0.5) {
                run.inventory.append(Item(id: "rune-strength", name: "Coral Charm", icon: "🪸", type: "rune", desc: "A charm from the deep. +6 attack for the rest of this run."))
                return Outcome(message: "You find a Coral Charm where the voice led. It is beautiful. You take it.")
            }
            let siren = Enemy(name: "Siren", icon: "🧜", hp: 65, maxHp: 65, atk: 12...20, gold: 9...17)
            return Outcome(message: "The voice belonged to a Siren. It was waiting. It is no longer singing.", enemy: siren)
        case ("abyssal-singing", _):
            return Outcome(message: "You walk past the corridor. The singing fades. You feel watched.")
        case ("abyssal-crack", 0):
            guard run.hp > 10 else { return Outcome(message: "You are too weak to seal it. The crack widens.") }
            run.hp -= 10
            let g = 25 + run.floor * 5
            gold(g)
            return Outcome(message: "You seal the crack with your hands. It costs you 10 HP. The room holds. You find \(g) gold in the wall as it seals.", gold: g)
        case ("abyssal-crack", _):
            run.hp = max(1, run.hp - 5)
            return Outcome(message: "The crack widens as you pass. The pressure punishes your indifference. Minus 5 HP.")
        case ("abyssal-ship", 0):
            let roll = dice.roll(0...9)
            if roll < 4 {
                let item = [potion, greaterPotion, spiritTonic][dice.roll(0...2)]
                run.inventory.append(item)
                return Outcome(message: "Inside the hull you find a \(item.name). The crew left in a hurry.", item: item)
            }
            if roll < 7 {
                let g = 30 + run.floor * 8
                gold(g)
                return Outcome(message: "The captain's chest is still sealed. Inside: \(g) gold and nothing else. The captain valued simplicity.", gold: g)
            }
            let t2 = Bestiary.enemies(for: "The Abyssal Deep").t2
            let t = t2[dice.roll(0...(t2.count - 1))]
            return Outcome(message: "Something was living in the ship. It is not happy.",
                           enemy: Enemy(name: t.name, icon: t.icon, hp: t.hp, maxHp: t.hp, atk: t.atk, gold: t.gold))
        case ("abyssal-ship", _):
            return Outcome(message: "You leave the ship undisturbed. It earned its rest.")
        case ("abyssal-shrine", 0):
            switch dice.roll(0...2) {
            case 0:
                run.hp = min(run.maxHp, run.hp + 30)
                return Outcome(message: "The shrine heals you. Plus 30 HP. The light dims slightly after. A fair trade.")
            case 1:
                run.sp = min(run.maxSp, run.sp + 20)
                return Outcome(message: "The shrine restores your spirit. Plus 20 SP. The ocean approves.")
            default:
                run.atkBonus += 3
                return Outcome(message: "The shrine grants strength. Plus 3 attack for the rest of this run.")
            }
        case ("abyssal-shrine", _):
            return Outcome(message: "You leave the shrine alone. It continues to glow behind you as you walk away.")
        case ("julio", 0):
            let msgs = [
                "He looks up slowly. \"The audit went well,\" he says. Then he is gone.",
                "He slides a potion across the floor without looking at you. You gain a Health Potion.",
                "\"Three hundred fifty-nine million years,\" he says quietly. \"Give or take.\" He does not elaborate.",
                "He hands you a crumpled note. It reads: COMPLIANCE IS MANDATORY. The handwriting is yours somehow.",
                "He nods once. You feel 10 HP restored. He returns to staring at the wall.",
                "\"The Department is watching,\" he says. \"It is always watching.\" He gestures vaguely at everything.",
            ]
            let roll = dice.roll(0...(msgs.count - 1))
            if roll == 1 { run.inventory.append(potion) }
            if roll == 4 { run.hp = min(run.maxHp, run.hp + 10) }
            // julioRestoresSanity: he is completely unbothered, which is grounding.
            if Sanity.active(run) {
                Sanity.restore(&run, 15)
                return Outcome(message: "Julio. " + msgs[roll] + " Julio is completely unbothered by everything around him. This is somehow grounding. Plus 15 sanity.")
            }
            return Outcome(message: "Julio. " + msgs[roll])
        case ("julio", 1):
            guard run.gold >= 10, wallet.spendGold(10) else {
                return Outcome(message: "You do not have enough gold. Julio watches you search your pockets. He says nothing. This is somehow worse.")
            }
            run.gold -= 10
            switch dice.roll(0...3) {
            case 0:
                run.maxHp += 5
                run.hp = min(run.maxHp, run.hp + 5)
                return Outcome(message: "He accepts the gold without comment. Your max HP increases by 5.")
            case 1:
                return Outcome(message: "He looks at the gold. He looks at you. He puts it in his pocket. Nothing happens. Nothing was supposed to happen.")
            case 2:
                gold(10)
                return Outcome(message: "He refuses. \"The DDDI does not accept bribes,\" he says. \"The DDDI accepts compliance.\" Your gold is returned.")
            default:
                run.inventory.append(spiritTonic)
                return Outcome(message: "He takes the gold and hands you a Spirit Tonic in return.")
            }
        case ("julio", _):
            let msgs = [
                "You back away slowly. He watches you go. His expression does not change. It never changes.",
                "As you leave you hear him say: \"Noted.\" You do not know what he noted. You do not ask.",
                "You leave. When you glance back the room is empty. The name tag is on the floor.",
                "He waves. It is the most unsettling wave you have ever seen.",
            ]
            return Outcome(message: msgs[dice.roll(0...(msgs.count - 1))])
        case ("shrine", 0):
            switch dice.roll(0...3) {
            case 0:
                run.hp = min(run.maxHp, run.hp + 20)
                return Outcome(message: "The shrine's warmth heals you. +20 HP.")
            case 1:
                run.atkBonus += 2
                return Outcome(message: "Your weapon feels keener. +2 attack.")
            case 2:
                run.defBonus += 2
                return Outcome(message: "Your resolve hardens. +2 defense.")
            default:
                run.sp = min(run.maxSp, run.sp + 8)
                return Outcome(message: "Your mind clears. +8 SP.")
            }
        case ("shrine", _):
            return Outcome(message: "You leave the shrine undisturbed.")
        case ("chest", 0):
            if dice.chance(0.35) {
                let bite = dice.roll(10...20)
                run.hp = max(0, run.hp - bite)
                return Outcome(message: "MIMIC! The chest bites you for \(bite) damage! HP: \(run.hp) of \(run.maxHp).", playerDied: run.isDead)
            }
            let g = dice.roll(15...35)
            gold(g)
            return Outcome(message: "The chest contains \(g) gold and something that smells like old paper.", gold: g)
        case ("chest", _):
            return Outcome(message: "You leave the chest. Some decisions are wisdom.")
        case ("wounded", 0):
            guard let i = run.inventory.firstIndex(where: { $0.type == "potion" }) else {
                return Outcome(message: "You have no potions to give. They nod and close their eyes.")
            }
            run.inventory.remove(at: i)
            Progression.gainXP(&run, 40)
            return Outcome(message: "They drink it and their color returns. They press a coin into your hand and point down a side passage. +40 XP.")
        case ("wounded", _):
            return Outcome(message: "You step over them and keep moving. The dungeon does not judge. Probably.")
        case ("inscription", 0):
            let xp = dice.roll(20...35)
            Progression.gainXP(&run, xp)
            return Outcome(message: "You spend time translating. Most of it is a warning. Some of it is a map. +\(xp) XP.")
        case ("inscription", _):
            return Outcome(message: "The inscription watches you leave. Inscriptions cannot watch. You are fairly certain.")
        default:
            return Outcome(message: "")
        }
    }
}

// MARK: - Julio's fragments (JULIO_FRAGMENTS, collectJulioFragment)

/// Talking to Julio hands you one of five fragments, kept across characters;
/// the fifth unlocks his story in the Chronicles Library (dd_julio_story).
public enum JulioFragments {
    public struct Fragment: Sendable, Equatable { public let id, text: String }

    public static let all: [Fragment] = [
        Fragment(id: "jf1", text: "A folded piece of paper. It reads: \"Back at 3AM. — J\""),
        Fragment(id: "jf2", text: "A name tag. It says JULIO. Someone has written underneath in small letters: \"still here.\""),
        Fragment(id: "jf3", text: "A memo. \"RE: Founding Charter signatures. I signed it because it was on my desk. I thought it needed a signature. — J\""),
        Fragment(id: "jf4", text: "A lunch schedule. 3AM to 3:15AM. Every day. The dungeon is listed as the lunch location."),
        Fragment(id: "jf5", text: "A note. \"The Department keeps asking where I am. I am right here. I am always right here. — Julio\""),
    ]

    public static func collected(_ store: GameStore) -> [String] {
        guard let s = store.getItem("dd_julio_fragments"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return v
    }

    /// One not yet found (nil once all five are); `storyUnlocked` the moment
    /// the fifth is found.
    public static func collect(_ store: GameStore, dice: inout some Dice) -> (fragment: Fragment, count: Int, storyUnlocked: Bool)? {
        var have = collected(store)
        let left = all.filter { !have.contains($0.id) }
        guard !left.isEmpty else { return nil }
        let f = left[dice.roll(0...(left.count - 1))]
        have.append(f.id)
        if let d = try? JSONEncoder().encode(have), let s = String(data: d, encoding: .utf8) { store.setItem("dd_julio_fragments", s) }
        var unlocked = false
        if have.count >= all.count && store.getItem("dd_julio_story") == nil {
            store.setItem("dd_julio_story", "true")
            unlocked = true
        }
        return (f, have.count, unlocked)
    }
}

// MARK: - The Sunken Archives' lore pages (SUNKEN_LORE_FRAGMENTS)

/// Eight pages of the Archives' records. The web version wrote them but
/// never handed them out; in Swift, studying an inscription in the Sunken
/// Archives finds the next one (kept across characters).
public enum SunkenPages {
    public struct Page: Sendable, Equatable { public let name, text: String }

    public static let all: [Page] = [
        Page(name: "Page 1 of the Founding Record", text: "The Archives were established in the year of the Second Tide. We chose this location because the water preserves. The Chancellor said nothing drowns here. The Chancellor has not been seen in forty years."),
        Page(name: "A Cataloguer Log", text: "Day 847. Found another section today that does not appear on any map of the building. The books there are in perfect condition. I cannot read the title of a single one. They seem different each time I look."),
        Page(name: "Torn Research Note", text: "The Leviathan arrived three hundred years before the Archives were built. We built around it. This was not a choice. This was the only option. You cannot move something that has always been there."),
        Page(name: "The Last Curator Manifesto", text: "I have been here long enough to understand. The Archives do not preserve knowledge. The Archives preserve everything. Every thought that has ever been thought in this place still exists here. That includes the bad ones."),
        Page(name: "Expedition Journal — Final Entry", text: "The water is rising again. This happens twice a year. The books do not get wet. The researchers do. I have stopped questioning this. I have stopped questioning most things. It is easier."),
        Page(name: "Classification Record — Item 7,891", text: "Item: Unknown. Origin: Unknown. Date catalogued: Unknown. Current location: Unknown. Notes: Do not look for it. It will find the catalog entry on its own. This is fine. This has always been fine."),
        Page(name: "A Child Drawing", text: "[A drawing of the Archives, rendered in faded ink. Everything is accurate — the shelves, the reading desks, the flooded floors — except in the drawing, every bookshelf has eyes. In the corner, in small handwriting: I found the special section. I did not come back out the same way I went in. This is an improvement.]"),
        Page(name: "The Archivist Oath — Partial", text: "...and I swear to preserve what is written, to catalog what is found, to shelve what arrives, and to ask no questions about where it came from. The Archives hold all knowledge. Some of it is knowledge of things that should not be known. This is not my concern. My concern is correct shelving procedure."),
    ]

    /// The next page not yet found, or nil once all eight are.
    public static func next(_ store: GameStore) -> (page: Page, number: Int)? {
        let have = Int(store.getItem("swift_sunken_pages") ?? "0") ?? 0
        guard have < all.count else { return nil }
        store.setItem("swift_sunken_pages", String(have + 1))
        return (all[have], have + 1)
    }
}
