import Foundation

// Character-creation tables, copied from the web version
// (_CLASSES, HP_MAP, ATK_MAP, DEF_MAP, _RACES, _PROFS, _DIFFS, LIVES_MAP, _DUNGS).
// Names are kept as the exact strings the web version saves, so old saves load.

public struct ClassInfo: Sendable {
    public let id: String
    public let tagline: String
    public let maxHp: Int
    public let atk: ClosedRange<Int>
    public let def: Int
}

public enum GameData {
    /// Every class in creation order. Classes without their own stats in the
    /// web version fall back to 100 HP, 6–12 attack, 0 defense, same as there.
    public static let classes: [ClassInfo] = [
        c("Warrior", "Frontline Fighter", 120, 8...16, 3),
        c("Monk", "Spiritual Striker", 90, 7...14, 1),
        c("Assassin", "Shadow Predator", 80, 10...18, 0),
        c("Paladin", "Divine Guardian", 130, 6...13, 5),
        c("Naturalist", "Wild Caller", 85, 6...12, 1),
        c("Sorcerer", "Glass Cannon", 70, 12...22, 0),
        c("Necromancer", "Death Wielder", 75, 7...14, 0),
        c("Berserker", "Rage Engine", 110, 9...17, 2),
        c("Bard", "Silver Tongue", 80, 6...12, 1),
        c("Alchemist", "Master Brewer", 85, 7...14, 1),
        c("BloodKnight", "Blood Harvester", 100, 10...20, 2),
        c("Druid", "Nature's Bond", 95, 7...14, 2),
        c("Warlock", "Soul Drainer", 75, 9...17, 0),
        c("DeathKnight", "Undying Resolve", 115, 8...16, 4),
        c("Ranger", "Swift Hunter", 90, 9...17, 1),
        c("Sentinel", "Unbreakable Wall", 145, 5...11, 7),
        c("Cleric", "Sacred Healer", 105, 6...12, 3),
        c("Wizard", "Arcane Scholar", 60, 14...24, 0),
        c("Elementalist", "", 100, 6...12, 0),
        c("VoidWalker", "", 100, 6...12, 0),
        c("ShadowMage", "", 100, 6...12, 0),
        c("TimeMage", "", 100, 6...12, 0),
        c("Shaman", "", 100, 6...12, 0),
        c("Arcanist", "", 100, 6...12, 0),
    ]

    public static func classInfo(_ id: String) -> ClassInfo {
        classes.first { $0.id == id } ?? c(id, "", 100, 6...12, 0)
    }

    public static let races: [(id: String, desc: String)] = [
        ("Human", "Adaptable · +All Stats"),
        ("Elf", "+AGI +INT"),
        ("Dwarf", "+STR +DEF"),
        ("Orc", "+STR+STR -DEF"),
        ("Tiefling", "+LCK +INT"),
        ("Shade", "+AGI +LCK"),
        ("Vampire", "Drain 5 HP per kill"),
        ("Goblin", "+25% gold"),
        ("Angel", "+1 extra life"),
        ("Demon", "+15% damage dealt and taken"),
        ("Golem", "+5 defense · Immune to status"),
        ("Halfling", "+LCK+LCK -STR"),
        ("Dragonborn", "10% burn damage · Scales with floor"),
        ("Gnome", "+INT +LCK · Skills cost less SP"),
        ("Merfolk", "+AGI · Bonus in Sunken Archives · Potions +heal"),
    ]

    public static let professions: [(id: String, desc: String)] = [
        ("Blacksmith", "Armor and Weapon Durability"),
        ("Herbalist", "Potions twice as effective"),
        ("Scholar", "Trap and Curse Detection"),
        ("Mercenary", "Starting Gold +1 Weapon"),
        ("Gravedigger", "Undead Resistance"),
        ("Thief", "Hidden Loot Discovery"),
        ("Pilgrim", "Holy Relic · +15% XP"),
        ("Grave Robber", "Start with 50g · Bonus loot"),
    ]

    public enum Difficulty: String, CaseIterable, Codable, Sendable {
        case wanderer = "Wanderer"
        case ironblood = "Ironblood"
        case condemned = "Condemned"
        case forsaken = "Forsaken"
        case nightmare = "Nightmare"
        case insane = "Insane"
        case endless = "Endless"

        public var lives: Int {
            switch self {
            case .wanderer: return 3
            case .endless: return 2
            default: return 1
            }
        }

        /// How much harder enemies hit (doFight's diffMult).
        public var enemyDamageMultiplier: Double {
            switch self {
            case .nightmare: return 1.75
            case .forsaken: return 1.5
            case .condemned: return 1.25
            case .ironblood: return 1.1
            default: return 1.0
            }
        }

        public var summary: String {
            switch self {
            case .wanderer: return "3 lives · Normal damage"
            case .ironblood: return "1 life · +10% damage"
            case .condemned: return "1 life · +25% damage"
            case .forsaken: return "1 life · +50% damage"
            case .nightmare: return "1 life · Nightmare enemies"
            case .insane: return "1 life · Sanity bar"
            case .endless: return "Infinite floors · No victory"
            }
        }
    }

    /// Dungeons in unlock order. Finishing one unlocks the next.
    public static let dungeons = [
        "Crypt of Malachar",
        "The Ashbound Wastes",
        "Frosthold Abyss",
        "The Sunken Archives",
        "The Hollow",
        "The Whispering Forest",
        "The Infernal Descent",
        "The Abyssal Deep",
    ]

    public static let maxCharacters = 5

    private static func c(_ id: String, _ tag: String, _ hp: Int, _ atk: ClosedRange<Int>, _ def: Int) -> ClassInfo {
        ClassInfo(id: id, tagline: tag, maxHp: hp, atk: atk, def: def)
    }
}
