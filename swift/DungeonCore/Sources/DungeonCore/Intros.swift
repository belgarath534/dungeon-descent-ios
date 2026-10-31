import Foundation

/// Boss previews (BOSS_INTROS, showBossPreview), dungeon intros (DUNGEON_INTROS,
/// showDungeonIntro), run start quotes (RUN_START_QUOTES, showRunStartQuote) and the
/// class item in every floor shop (getClassShopItem).
public enum Intros {
    public static let bossIntros: [String: String] = [
        "Malachar the Undying": "He refused to die. He still refuses. He has been refusing for a very long time.",
        "The Bone Colossus": "Assembled from every skeleton in the Crypt. It remembers all of their deaths.",
        "The Crypt Sovereign": "The dungeon itself built this thing. For occasions exactly like this one.",
        "Vel Ashara Reborn": "The city did not just burn. It became this.",
        "The Eternal Pyre": "The fire became aware three hundred years ago. It has been thinking ever since.",
        "The Ash Sovereign": "It rules what the flames left behind. Which is everything.",
        "The Glacial Titan": "It has been here since before the ice. The ice formed around it.",
        "The Frosthold Sovereign": "Nothing survives the Abyss. Except this.",
        "The Eternal Winter": "The cold does not want you here. It will make this very clear.",
        "The Drowned Curator": "It has read every book in the Archives. It did not enjoy what it learned.",
        "Leviathan of the Deep": "The Archives were built around it. Not on top of it. Around it.",
        "The Last Librarian": "She stayed when everyone else drowned. She has had a very long time to be angry.",
        "The Dungeon Itself": "You have descended far enough that the dungeon noticed you. This is not good.",
        "The Nightmare Sovereign": "It was always here. You simply could not see it until now.",
        "Void Incarnate": "The void has a name. You cannot pronounce it. This is for the best.",
        "Grand Overseer of the DDDI": "The audit begins NOW.",
        "The Leviathan": "It did not come here. It has always been here. You descended into it.",
        "The Ancient Tide": "The ocean remembers every ship that sank. This is what memory becomes.",
        "The Drowned God": "It was worshipped once. Then the sea rose. It is still waiting for the prayers to resume.",
        "The Abyssal Crown": "Something at the bottom of everything decided it wanted to be in charge.",
        "The Deep Archivist": "It has catalogued every creature that ever drowned. You are about to become an entry.",
        "The Echo": "It is a copy of something you already killed. It remembers the fight. It will not make the same mistakes.",
        "The Shapeshifter": "It has waited 3000 years for someone worth copying. Now it wears your face. It knows every move you will make.",
    ]
    public static let bossFallback = "Something ancient stirs at the end of the hall. Something that has been waiting."

    public static let dungeonIntros: [String: (eyebrow: String, text: String)] = [
        "Crypt of Malachar": ("Entering the Crypt", "Malachar has been waiting. He has been waiting for a very long time. He is patient in the way that only things which cannot die are patient."),
        "The Ashbound Wastes": ("Entering the Wastes", "The fire remembers everyone who has come here. It has a very good memory. It has had a long time to practice."),
        "Frosthold Abyss": ("Entering the Abyss", "The cold is not a temperature. It is a presence. It has noticed you. It is deciding what to do about that."),
        "The Sunken Archives": ("Entering the Archives", "The water is perfectly still. The candles are still lit. Something has been cataloguing. It has found a new entry."),
        "The Hollow": ("Entering the Hollow", "The house knows you are here. It has always known. It has been waiting for you specifically. It does not explain how it knew."),
        "The Whispering Forest": ("Entering the Forest", "The trees do not move in the wind here. There is no wind. The sound you hear is not the wind. The forest would like you to know that."),
        "The Infernal Descent": ("Entering the Infernal", "Everything here has already burned. It burns still. The things that live in the fire have stopped noticing the fire. They will notice you."),
        "The Abyssal Deep": ("Descending into the Deep", "The deepest dungeon. Every boss here has four phases and at least 600 HP. It hits harder than anything you have faced. Stock every potion. Use every skill. Cast every spell. You have been warned."),
        "The Shadow World": ("Entering the Shadow World", "It has existed for 3000 years beneath a cursed forest. It does not obey your rules. The Shapeshifter waits at the end — wearing your face, using your skills, knowing your every move. Nothing that enters here leaves unchanged."),
    ]

    public static let runStartQuotes: [String: [String: String]] = [
        "Crypt of Malachar": [
            "Warrior": "The Crypt has broken stronger than you. That is not a warning. It is a challenge.",
            "Monk": "The dead here have forgotten stillness. You have not. Remind them.",
            "Assassin": "The Crypt sees everything. Move anyway.",
            "Paladin": "The divine light you carry is the first light this place has seen in a thousand years. Use it.",
            "Naturalist": "Nothing grows in the Crypt. You are about to change that.",
            "Sorcerer": "The magic here is old and angry. Yours is newer. Show it the difference.",
            "Necromancer": "The dead here are not your enemies. They are your colleagues. Introduce yourself.",
            "Berserker": "The undead have been angry for a thousand years. You have been angry longer. You win.",
            "Bard": "You will sing in the Crypt. The dead will listen. They have not heard music in centuries.",
            "Alchemist": "The Crypt is one giant experiment. You are the variable it did not account for.",
            "BloodKnight": "Blood answers blood. The Crypt has plenty. So do you.",
            "Druid": "Nothing lives here. Yet. Give it time.",
        ],
        "The Ashbound Wastes": [
            "Warrior": "The fire has never met a wall before. You are the wall.",
            "Monk": "The Wastes burn everything. Find the stillness inside the fire.",
            "Assassin": "Everything in the Wastes is on fire. Smoke makes excellent cover.",
            "Paladin": "Your faith burns hotter than this place. Prove it.",
            "Naturalist": "The Wastes forgot what living things feel like. Be a reminder.",
            "Sorcerer": "The fire here is ancient. Ancient things can still be surprised.",
            "Necromancer": "Even ash remembers what it was. Ask it.",
            "Berserker": "The Wastes want to make you rage. You were already raging. You are ahead.",
            "Bard": "No one has sung in the Wastes. The silence has gone on long enough.",
            "Alchemist": "Heat plus pressure plus the right compound equals opportunity. Calculate accordingly.",
            "BloodKnight": "The Wastes run red beneath the ash. You will feel at home.",
            "Druid": "One green thing. That is all you need to leave behind. Start small.",
        ],
        "Frosthold Abyss": [
            "Warrior": "The cold slows everything down. Not you. Never you.",
            "Monk": "The Abyss is perfectly still. So are you. One of you will move first.",
            "Assassin": "Ice reflects everything. Do not let it reflect you.",
            "Paladin": "The cold cannot touch what has already been claimed by the divine.",
            "Naturalist": "The Abyss has been frozen so long it forgot spring exists. Teach it.",
            "Sorcerer": "Old cold magic versus new hot magic. The math is in your favor.",
            "Necromancer": "The frozen dead are the most patient dead. They have been waiting for someone to talk to.",
            "Berserker": "The cold tries to slow your anger. Your anger is faster than cold.",
            "Bard": "The Abyss has been silent forever. That ends today.",
            "Alchemist": "Freezing point. Boiling point. You know exactly where the interesting things happen.",
            "BloodKnight": "Blood does not freeze. You have tested this.",
            "Druid": "Under all that ice something is still alive. Find it.",
        ],
        "The Sunken Archives": [
            "Warrior": "The Archives recorded every warrior who entered. None of them finished the index.",
            "Monk": "The Archives contain every answer ever written. The question is whether you survive long enough to read them.",
            "Assassin": "The Archives know everything. Make sure they do not learn too much about you.",
            "Paladin": "The drowned scholars chose knowledge over faith. Show them what faith chose.",
            "Naturalist": "The Archives catalogued every living thing. They missed a few. You will find them.",
            "Sorcerer": "Every spell ever written is in here somewhere. Try not to accidentally read one.",
            "Necromancer": "The drowned scholars died for knowledge. They will appreciate the professional courtesy.",
            "Berserker": "Knowledge is power. Power is what you hit things with. You are ready.",
            "Bard": "You are about to become the most dramatic entry in the Archives. Make it worth reading.",
            "Alchemist": "The restricted section exists for a reason. That reason is about to become your opportunity.",
            "BloodKnight": "The Archives are written in ink. You prefer a different medium. Make your mark.",
            "Druid": "The waterlogged plants in the Archives are trying very hard. Help them.",
        ],
        "The Hollow": [
            "Warrior": "The house wants you afraid. Refuse.",
            "Monk": "The Hollow is full of noise disguised as silence. Listen through it.",
            "Assassin": "The house watches every room. Every room except the one you are already in.",
            "Paladin": "The Hollow has not felt holy light in a very long time. It is about to.",
            "Naturalist": "Something alive is in the Hollow. Something that should not be. It might be you.",
            "Sorcerer": "The Hollow runs on old grief. Grief is just energy with nowhere to go. Redirect it.",
            "Necromancer": "The dead in the Hollow were not expecting a colleague. The surprise is yours to exploit.",
            "Berserker": "The house is built on fear. You are not afraid. This is already over.",
            "Bard": "The Hollow has been silent for decades. You are going to fix that whether it wants you to or not.",
            "Alchemist": "The Hollow is a controlled environment. You are the uncontrolled variable.",
            "BloodKnight": "The house keeps what it takes. Make sure it remembers what it took from you.",
            "Druid": "The garden died when the house did. One of you is going to fix that today.",
        ],
    ]

    /// classItems: the type, then heal / atk / sp.
    static let classItems: [String: Item] = [
        "Warrior": Item(name: "War Banner", icon: "🏴", type: "atk-potion", desc: "Permanent +5 attack this run.", cost: 20, atk: 5),
        "Monk": Item(name: "Meditation Stone", icon: "🧘", type: "sp-potion", desc: "Restore 25 SP instantly.", cost: 18, sp: 25),
        "Assassin": Item(name: "Shadow Oil", icon: "🌑", type: "def-potion", desc: "Next attack guaranteed critical hit.", cost: 15),
        "Paladin": Item(name: "Holy Water", icon: "✝️", type: "potion", desc: "Restores 60 HP with divine blessing.", heal: 60, cost: 20),
        "Naturalist": Item(name: "Nature Salve", icon: "🍃", type: "potion", desc: "Natural remedy. Restores 45 HP.", heal: 45, cost: 14),
        "Sorcerer": Item(name: "Spell Scroll", icon: "📜", type: "sp-potion", desc: "Restores 35 SP. Arcane knowledge.", cost: 22, sp: 35),
        "Necromancer": Item(name: "Soul Shard", icon: "💠", type: "sp-potion", desc: "Crystallized soul energy. +20 SP.", cost: 16, sp: 20),
        "Berserker": Item(name: "Rage Brew", icon: "🍺", type: "atk-potion", desc: "Permanent +8 attack. Pure fury.", cost: 22, atk: 8),
        "Bard": Item(name: "Inspiration", icon: "🎵", type: "sp-potion", desc: "Musical inspiration. +20 SP.", cost: 15, sp: 20),
        "Alchemist": Item(name: "Base Reagents", icon: "⚗️", type: "cursed", desc: "Raw alchemical components. Unpredictable.", cost: 5),
        "BloodKnight": Item(name: "Blood Vial", icon: "🩸", type: "potion", desc: "Dark crimson brew. Restores 50 HP.", heal: 50, cost: 18),
        "Druid": Item(name: "Ancient Root", icon: "🌿", type: "potion", desc: "Ancient healing root. Restores 45 HP.", heal: 45, cost: 14),
        "Warlock": Item(name: "Soul Fragment", icon: "🧿", type: "sp-potion", desc: "Dark soul energy. Restores 30 SP.", cost: 18, sp: 30),
        "DeathKnight": Item(name: "Death Rune", icon: "💀", type: "atk-potion", desc: "Runic power. Permanent +6 attack this run.", cost: 20, atk: 6),
        "Dragonborn": Item(name: "Dragon Scale", icon: "🐉", type: "atk-potion", desc: "A scale that radiates ancient power. +7 attack.", cost: 22, atk: 7),
        "Cleric": Item(name: "Holy Relic", icon: "✝️", type: "potion", desc: "Sacred relic. Restores 70 HP with divine light.", heal: 70, cost: 24),
        "Wizard": Item(name: "Spell Scroll", icon: "📜", type: "sp-potion", desc: "Arcane scroll. Restores 40 SP instantly.", cost: 20, sp: 40),
    ]

    /// One item for your class in every floor shop; on NG+ the Veteran Elixir instead.
    /// Class items that say "permanent" add to your attack for the run, and Shadow Oil
    /// makes your next attack a critical (the web version's handler for it never ran).
    public static func classShopItem(_ run: Run) -> Item? {
        if run.ngPlus {
            return Item(name: "Veteran Elixir", icon: "⭐", type: "potion", desc: "NG+ exclusive. Restores 100 HP. For survivors.", heal: 100, cost: 35)
        }
        guard var item = classItems[run.cls] else { return nil }
        if item.name == "Shadow Oil" { item.extra["classItem"] = .string("crit") }
        else if item.type == "atk-potion" { item.extra["classItem"] = .string("permanent") }
        return item
    }

    /// Using a class item. Nil when the item is an ordinary one.
    static func use(_ run: inout Run, at index: Int) -> Inventory.Outcome? {
        let item = run.inventory[index]
        switch item.extra["classItem"] {
        case .string("crit")?:
            run.markedKill = true
            run.inventory.remove(at: index)
            return Inventory.Outcome(message: "Shadow Oil applied. Next attack guaranteed critical!")
        case .string("permanent")?:
            let n = item.atk ?? 4
            run.atkBonus += n
            run.inventory.remove(at: index)
            return Inventory.Outcome(message: "Used \(item.name). +\(n) attack for the rest of this run.")
        default:
            return nil
        }
    }

    public static func bossIntro(_ name: String) -> String { bossIntros[name] ?? bossFallback }

    /// showRunStartQuote: the quote for this dungeon and class, if there is one.
    public static func runStartQuote(dungeon: String, cls: String) -> String? { runStartQuotes[dungeon]?[cls] }
}
