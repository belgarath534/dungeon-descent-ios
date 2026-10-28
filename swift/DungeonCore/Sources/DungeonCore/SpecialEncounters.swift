import Foundation

/// The rest of the dungeon's special moments: the wandering NPCs
/// (NPC_ENCOUNTERS), the Abyssal Deep's Witness, the Easter Bunny and
/// Friday the 13th's Black Box.
public enum SpecialEncounters {
    // MARK: NPCs

    struct NPC {
        let id, name, icon, greeting: String
        let choices: [String]
    }

    static let npcs: [NPC] = [
        NPC(id: "wounded-warrior", name: "A Wounded Warrior", icon: "⚔️",
            greeting: "A warrior sits against the wall, clutching a wound. He looks up at you with tired eyes. \"Still standing?\" he rasps.",
            choices: ["🩹 Give him a potion", "💬 Ask about the boss", "🚶 Leave him be"]),
        NPC(id: "lost-merchant", name: "A Lost Merchant", icon: "🛒",
            greeting: "A small nervous man huddles behind an overturned cart. He spots you and waves frantically. \"Oh thank the gods! A real person! I got lost — I have wares but I need out of here!\"",
            choices: ["💰 Buy his secret item (80g)", "🗺 Give him directions", "🚶 Ignore him"]),
        NPC(id: "mysterious-stranger", name: "A Mysterious Stranger", icon: "🌑",
            greeting: "A figure stands in the center of the room, facing away from you. They do not move when you enter. After a long moment they speak. \"I have been watching you.\"",
            choices: ["⚡ Challenge them", "🤝 Ask who they are", "🚶 Back away slowly"]),
        NPC(id: "dungeon-child", name: "A Lost Child", icon: "👁️",
            greeting: "Impossible. There is a child here — sitting cross-legged in the middle of a dungeon room, arranging small bones into patterns. They look up at you with eyes too old for their face. \"Hello. Are you lost too?\"",
            choices: ["🛡 Protect them", "❓ Ask what they are", "🚶 Leave immediately"]),
    ]

    /// tryNPCEncounter: once a run, 12% of rooms on floors 2–9. (The web
    /// version allowed one per app session, not one per run.)
    public static func npc(_ run: inout Run, dice: inout some Dice) -> String? {
        guard !run.npcMet, (2...9).contains(run.floor), dice.chance(0.12) else { return nil }
        run.npcMet = true
        return "npc-" + npcs[dice.roll(0...(npcs.count - 1))].id
    }

    // MARK: The Black Box and the Easter Bunny

    /// Friday the 13th: 20% of rooms from floor 2, once a floor.
    public static func blackBox(_ run: inout Run, dice: inout some Dice) -> String? {
        guard run.event == "friday13", run.floor >= 2, run.blackBoxFloor != run.floor, dice.chance(0.20) else { return nil }
        run.blackBoxFloor = run.floor
        return "black-box"
    }

    /// Easter: 15% of fights.
    public static func easterBunny(_ run: Run, earned: Set<String>, dice: inout some Dice) -> String? {
        guard run.event == "easter", dice.chance(0.15) else { return nil }
        return earned.contains("easter-bunny") ? "easter-bunny-owned" : "easter-bunny"
    }

    static let bunnyText = "A rabbit sits in the middle of the room. It is larger than a rabbit should be. It is wearing a small bow tie. It looks at you with complete calm. It has a basket. The basket is full of eggs. You are not sure what is happening."

    public static func event(_ id: String) -> Encounters.Event? {
        if id.hasPrefix("npc-"), let n = npcs.first(where: { "npc-" + $0.id == id }) {
            return Encounters.Event(id: id, title: "\(n.icon) \(n.name)", text: n.greeting, choices: n.choices, weight: 0, dungeons: nil)
        }
        switch id {
        case "black-box":
            return Encounters.Event(id: id, title: "A Black Box",
                                    text: "You find a black box. It is not making any sound. It is not moving. It is watching you. Do you open it?",
                                    choices: ["🔲 Open It", "🚪 Leave It"], weight: 0, dungeons: nil)
        case "easter-bunny":
            return Encounters.Event(id: id, title: "The Easter Bunny", text: bunnyText,
                                    choices: ["⚔ Fight It", "🐰 Adopt It", "🕊 Let It Go"], weight: 0, dungeons: nil)
        case "easter-bunny-owned":
            return Encounters.Event(id: id, title: "The Easter Bunny", text: bunnyText + " You already adopted one.",
                                    choices: ["⚔ Fight It", "🕊 Let It Go"], weight: 0, dungeons: nil)
        default: return nil
        }
    }

    // MARK: The Witness

    /// The Witness: the Abyssal Deep's shark. Beat it and it chooses you.
    static var witness: Enemy {
        var e = Enemy(name: "The Witness", icon: "🦈", hp: 60, maxHp: 60, atk: 10...16, gold: 0...0)
        e.desc = "It was never really fighting you."
        e.mechanics["isWitness"] = .bool(true)
        return e
    }

    public static func isWitness(_ e: Enemy) -> Bool { e.flag("isWitness") }

    public static let witnessText = "The shark does not fall. It circles you one final time. Then it stops. It looks at you directly. You realize — it was never real. A projection. A test. The real shark rises from below. It has been watching you since you entered this dungeon. Every fight. Every floor. Every choice. It has decided. You passed."

    /// checkWitnessAfterKill: the Witness joins you as a minion for good.
    public static func witnessJoins(store: GameStore) -> Bool {
        var list = Home.minions(store)
        guard !list.contains(where: { $0.id == "the-witness" }) else { return false }
        list.append(Minion(id: "the-witness", name: "The Witness", icon: "🦈", atk: 12, tier: "elite",
                           capturedOn: (Date().timeIntervalSince1970 * 1000).rounded()))
        Home.saveMinions(list, store)
        return true
    }

    // MARK: The Unlucky One

    static var unluckyOne: Enemy {
        var e = Enemy(name: "The Unlucky One", icon: "🔲", hp: 120, maxHp: 120, atk: 18...28, gold: 50...80)
        e.isElite = true
        e.desc = "It has been waiting. It does not speak. It only takes. Your critical chance is zero, and it may steal your gold."
        e.mechanics["unlucky"] = .bool(true)
        return e
    }

    /// Half its turns, it takes 10–39 gold.
    static func steal(_ run: inout Run, dice: inout some Dice, log: inout [String]) {
        guard let e = run.enemy, e.flag("unlucky"), dice.chance(0.5) else { return }
        let n = min(run.gold, dice.roll(10...39))
        guard n > 0 else { return }
        run.gold -= n
        run.fight.stolenGold += n
        log.append("🔲 The Unlucky One takes \(n) gold. It does not spend gold. It just takes.")
    }

    // MARK: Choices

    static func choose(_ id: String, _ choice: Int, _ run: inout Run, dice: inout some Dice, wallet: Wallet) -> Encounters.Outcome {
        typealias Outcome = Encounters.Outcome
        func gold(_ g: Int) { run.gold += g; wallet.addGold(g) }
        switch (id, choice) {
        case ("abyssal-witness", _):
            return Outcome(message: "A shark drifts from the dark. Large. Calm. It circles you slowly. It does not attack. It watches. Something feels different about this fight.", enemy: witness)
        case ("black-box", 0):
            return Outcome(message: "You open the black box. Something steps out. The Unlucky One has found you. Your luck drops to zero. It wants your gold.", enemy: unluckyOne)
        case ("black-box", _):
            return Outcome(message: "You leave the box. It does not follow. It does not need to.")
        case ("easter-bunny", 0), ("easter-bunny-owned", 0):
            var e = Enemy(name: "The Easter Bunny", icon: "🐰", hp: 20, maxHp: 20, atk: 2...5, gold: 10...20)
            e.desc = "It is not very strong but it has dignity."
            return Outcome(message: "The Easter Bunny adjusts its bow tie. It does not look afraid. It should look afraid.", enemy: e)
        case ("easter-bunny", 1):
            run.spirit = "easter-bunny"
            var o = Outcome(message: "The Easter Bunny looks at you for a long moment. Then it hops over. It sits beside you. It is your spirit companion now — for this run and every run after. It brought the basket. You are not sure what to do with the eggs. Neither is it.")
            o.spirit = "easter-bunny"
            return o
        case ("easter-bunny", _), ("easter-bunny-owned", _):
            gold(15)
            return Outcome(message: "You step aside. The Easter Bunny hops past you without looking back. It leaves one egg behind, worth 15 gold. You are not sure if this is a gift or a warning.", gold: 15)
        // The NPCs
        case ("npc-wounded-warrior", 0):
            guard let i = run.inventory.firstIndex(where: { $0.type == "potion" }) else {
                var o = Outcome(message: "You do not have a potion to give.")
                o.retry = true
                return o
            }
            run.inventory.remove(at: i)
            gold(50)
            return Outcome(message: "He drinks it gratefully. \"You saved my life. Take this — I will not be needing it.\" He presses a gold coin pouch into your hand. You gained 50 gold.", gold: 50)
        case ("npc-wounded-warrior", 1):
            return Outcome(message: "He shakes his head slowly. \"Three phases. It gets meaner each time. Save your best skill for phase three — that is when it really wakes up.\" He closes his eyes.")
        case ("npc-wounded-warrior", _):
            return Outcome(message: "You nod and move on. Some burdens are not yours to carry.")
        case ("npc-lost-merchant", 0):
            guard run.gold >= 80, wallet.spendGold(80) else {
                var o = Outcome(message: "Not enough gold. You need 80 gold.")
                o.retry = true
                return o
            }
            run.gold -= 80
            let rare = [Item(name: "Dungeon Pearl", icon: "⚪", type: "material", desc: "A rare pearl found deep in the dungeon. Worth a lot to the right buyer.", cost: 150),
                        Item(name: "Ancient Coin", icon: "🪙", type: "material", desc: "From a civilization that no longer exists. Strangely warm to the touch.", cost: 200),
                        Item(name: "Void Crystal", icon: "💎", type: "material", desc: "Crystallized nothingness. The dungeon made something from nothing.", cost: 250)]
            let item = rare[dice.roll(0...2)]
            run.inventory.append(item)
            return Outcome(message: "He thrusts a wrapped package into your hands. \"Finest thing I had. Now please, is there an exit?\" He scurries off before you can answer. You received \(item.name).", item: item)
        case ("npc-lost-merchant", 1):
            gold(30)
            return Outcome(message: "\"The exit is back the way I came,\" you tell him. He looks relieved and hands you a small pouch. \"A tip! A tip for the nice adventurer!\" He runs off immediately. You gained 30 gold.", gold: 30)
        case ("npc-lost-merchant", _):
            return Outcome(message: "You keep moving. The dungeon is no place for merchants.")
        case ("npc-mysterious-stranger", 0):
            gold(75)
            return Outcome(message: "\"Brave.\" They turn. There is no face under the hood — just darkness. A pouch falls from their sleeve to the floor. When you look up they are gone. You gained 75 gold.", gold: 75)
        case ("npc-mysterious-stranger", 1):
            let rune = Item(name: "Wanderers Rune", icon: "🔮", type: "material", desc: "Left by someone who was here before you. Its purpose is unclear but it feels important.", cost: 100)
            run.inventory.append(rune)
            return Outcome(message: "Long pause. \"Someone who was where you are, once.\" They reach into their cloak and press something cold into your palm — a rune stone. Then they simply are not there anymore. You received a Wanderers Rune.", item: rune)
        case ("npc-mysterious-stranger", _):
            return Outcome(message: "You back toward the door. The figure does not move. When you glance back they are gone. The room feels colder.")
        case ("npc-dungeon-child", let c):
            var o = Outcome(message: [
                "\"Thank you,\" they say. They reach into their pocket and press something cold into your hand — a small dark shard that seems to absorb light. \"A piece of my story,\" they say quietly. Then they walk into the wall and are gone.",
                "\"I am what the dungeon keeps,\" they say. They press one of the small bones into your hand — then something else. A shard of something dark and cold. \"You are the first to ask,\" they say. \"Keep listening.\"",
                "You leave. Fast. Some things in dungeons are better left alone. As you go, you feel something slip into your pocket. You look back. She is gone.",
            ][min(c, 2)])
            o.voidFragment = true
            return o
        default:
            return Outcome(message: "")
        }
    }
}
