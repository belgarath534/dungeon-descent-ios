import Foundation

/// 12.4: damage types, and enemies that are weak or strong to them
/// (docs/12.4-CORRUPTION.md, sections 1 and 2). The game never says "super
/// effective": the number shows it. The web version (js/38) uses the same
/// words and numbers.
public enum DamageType: String, CaseIterable, Codable, Sendable {
    case physical, fire, ice, storm, poison, holy, arcane, corruption

    public var icon: String {
        switch self {
        case .physical: return "⚔️"
        case .fire: return "🔥"
        case .ice: return "❄️"
        case .storm: return "⚡"
        case .poison: return "☠️"
        case .holy: return "✨"
        case .arcane: return "🔮"
        case .corruption: return "🌑"
        }
    }

    /// "fire damage", read by VoiceOver with the number.
    public var word: String { self == .physical ? "" : rawValue }
}

public enum DamageTypes {
    // MARK: Affinities

    public static let veryWeak = 2.5
    public static let weak = 1.75
    public static let resists = 0.5
    /// Ghosts and spirits: blades pass partly through them (not half: the
    /// Crypt's very first enemy is a shade).
    public static let slightly = 0.75
    public static let immune = 0.0
    /// Absorbs: heals by half the hit (only void things, against Corruption).
    public static let absorbs = -0.5

    // MARK: Which type a skill is

    /// First match wins, in this order (a fire curse is Corruption).
    static let skillWords: [(DamageType, [String])] = [
        (.corruption, ["corrupt", "void", "shadow", "curse", "cursed", "hex", "abyss", "abyssal", "soul", "souls", "dark", "darkness", "doom", "necrotic", "necro", "unholy", "lich", "lichform", "corpse", "death", "decay", "nightmare", "apocalypse"]),
        (.holy, ["holy", "divine", "smite", "radiant", "sacred", "light", "prayer", "judgment", "judgement", "blessed", "blessing", "consecrat", "heaven", "celestial", "sanctified"]),
        (.fire, ["fire", "flame", "flames", "burn", "burning", "burns", "ember", "embers", "inferno", "blaze", "blazing", "ash", "magma", "pyre", "scorch", "immolat", "molten", "fireball", "soulfire"]),
        (.ice, ["ice", "icy", "frost", "freeze", "frozen", "freezing", "cold", "glacier", "glacial", "snow", "rime", "blizzard", "chill"]),
        (.storm, ["storm", "lightning", "thunder", "shock", "tempest", "wind", "winds", "tornado", "gale", "static", "zap", "cyclone", "tesla", "electric", "thunderstrike"]),
        (.poison, ["poison", "poisoned", "venom", "venomous", "toxic", "toxin", "plague", "blight", "acid", "spore", "spores", "rot", "flask", "miasma"]),
        (.arcane, ["arcane", "mana", "spell", "rune", "runes", "time", "astral", "mystic", "ether", "aether", "chrono", "temporal", "magic", "missile"])
    ]

    /// Skills whose words say the wrong thing.
    static let skillOverrides: [String: DamageType] = [
        "soulfire": .fire,
        "blood rage": .physical,
        "shadow step": .physical,
        "shadow strike": .physical,
        "light step": .physical,
        "time out": .arcane,
        "deadly poison": .poison,
        "backstab": .physical,
        "soul surge": .arcane,
        "explosive flask": .fire,
        "crimson storm": .physical,
        "crimson nova": .physical,
        "rapid fire": .physical,
        "rain of arrows": .physical,
        "mana burn": .arcane,
        "fever dream": .poison,
        "moonfire": .holy,
        "sunfire": .holy,
        "steam vent": .fire,
        "death from afar": .physical,
        "hunter's end": .physical,
        "remedy": .physical,
        "black death": .poison
    ]

    /// A word counts when a word of the text starts with it ("burn" in
    /// "burning"), except these, which must match whole ("light" is not
    /// "lightning", "ash" is not "ashamed", "time" is not "timely").
    static let wholeWords: Set<String> = ["light", "ash", "time", "rot", "hex", "cold", "dark", "soul", "spell", "rune", "wind", "ice", "static", "doom", "death", "decay", "lich"]

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0 == "-") }.map(String.init)
    }

    static func matches(_ words: [String], _ keys: [String]) -> Bool {
        keys.contains { k in
            wholeWords.contains(k) ? words.contains(k) : words.contains { $0.hasPrefix(k) }
        }
    }

    /// The type of a skill, from its name, then its description.
    public static func of(skillName name: String, desc: String) -> DamageType {
        if let t = skillOverrides[name.lowercased()] { return t }
        let n = words(name)
        for (t, keys) in skillWords where matches(n, keys) { return t }
        let d = words(desc)
        for (t, keys) in skillWords where matches(d, keys) { return t }
        return .physical
    }

    public static func of(_ skill: Skill) -> DamageType { of(skillName: skill.name, desc: skill.desc) }

    // MARK: What an enemy is weak or strong to

    public typealias Affinities = [DamageType: Double]

    /// Bosses written by hand (the rules below fill in the rest).
    static let bosses: [String: Affinities] = [
        "Malachar the Undying": [.holy: veryWeak, .corruption: resists, .poison: resists],
        "Malchar Reborn": [.holy: veryWeak, .corruption: resists, .fire: resists],
        "Queen Verdana": [.fire: weak, .poison: resists],
        "The Root Mother": [.fire: weak, .poison: resists],
        "The Witch Who Remains": [.holy: weak, .corruption: resists],
        "The Howling Alpha": [.fire: weak, .poison: weak],
        "The Time Eater": [.arcane: weak, .physical: 0.75, .fire: 0.75, .ice: 0.75, .storm: 0.75, .poison: 0.75, .holy: 0.75, .corruption: 0.75],
        "The Void Reaper": [.holy: weak, .corruption: absorbs],
        "The Shapeshifter": [:],
        "The Echo": [.holy: weak, .physical: slightly],
        "The House Itself": [.fire: weak, .holy: weak, .physical: resists],
        "Leviathan of the Deep": [.storm: weak, .fire: resists],
        "The Leviathan": [.storm: weak, .fire: resists, .ice: resists],
        "The Leviathan Eye": [.storm: veryWeak, .fire: resists],
        "The Drowned God": [.storm: weak, .holy: weak, .fire: resists]
    ]

    /// Name words, first match per type wins.
    static let nameRules: [([String], Affinities)] = [
        (["void", "shadow", "abyss", "umbral", "null", "rift", "hollow-born"], [.holy: weak, .corruption: absorbs]),
        (["angel", "saint", "priest", "seraph", "holy", "paladin", "abbot", "choir", "templar", "cleric", "nun"], [.corruption: veryWeak, .holy: resists]),
        (["frost", "ice", "icy", "snow", "glacier", "glacial", "rime", "frozen", "winter", "khyros", "yeti", "blizzard"], [.fire: weak, .ice: immune]),
        (["flame", "fire", "ember", "ash", "ashen", "magma", "infernal", "cinder", "pyre", "pyrax", "scorching", "burning", "molten", "lava", "salamander", "imp"], [.ice: weak, .fire: immune]),
        (["storm", "thunder", "lightning", "sky", "wind", "gale", "tempest", "harpy"], [.ice: weak, .storm: resists]),
        (["drowned", "tide", "deep", "leviathan", "kraken", "eel", "siren", "water", "sunken", "abyssal"], [.storm: weak, .fire: resists]),
        (["plant", "vine", "thorn", "bloom", "root", "fig", "moss", "spore", "fungal", "mushroom", "briar", "bramble", "flower", "blossom", "treant", "pollen", "verdant"], [.fire: weak, .poison: resists]),
        (["golem", "construct", "armored", "armoured", "stone", "iron", "colossus", "statue", "gargoyle", "sentinel", "engine", "siege"], [.physical: resists, .storm: weak]),
        (["skeleton", "bone", "bones", "skull", "lich", "zombie", "ghoul", "corpse", "revenant", "wight", "mummy", "undying", "deathless", "grave"], [.holy: weak, .poison: immune, .ice: resists]),
        (["ghost", "wraith", "spirit", "phantom", "specter", "spectre", "banshee", "shade", "wisp", "haunt", "poltergeist", "apparition"], [.holy: weak, .physical: slightly]),
        (["demon", "devil", "fiend", "hellhound", "succubus"], [.holy: weak, .fire: resists]),
        (["wolf", "spider", "rat", "bat", "boar", "bear", "beast", "hound", "serpent", "snake", "swarm", "crawler", "scorpion", "beetle", "worm"], [.fire: weak, .poison: weak])
    ]

    static let typeRules: [String: Affinities] = [
        "undead": [.holy: weak, .poison: immune, .ice: resists],
        "spirit": [.holy: weak, .physical: slightly],
        "beast": [.fire: weak, .poison: weak],
        "demon": [.holy: weak, .fire: resists],
        "elemental": [.storm: weak]
    ]

    static let dungeonRules: [String: Affinities] = [
        "The Ashbound Wastes": [.fire: resists, .ice: weak],
        "The Infernal Descent": [.fire: resists, .ice: weak],
        "Frosthold Abyss": [.ice: resists, .fire: weak],
        "The Sunken Archives": [.storm: weak],
        "The Abyssal Deep": [.storm: weak, .holy: weak],
        "The Shadow World": [.holy: weak],
        "The Hollow": [.holy: weak],
        "The Whispering Forest": [.fire: weak],
        "The Sky Ruins": [.fire: weak, .poison: resists],
        "Crypt of Malachar": [.holy: weak]
    ]

    /// Creature types from the Bestiary (by enemy name), filled in by the app
    /// at launch from its bestiary data (enemyType).
    nonisolated(unsafe) public static var creatureTypes: [String: String] = [:]

    /// Everything one enemy is weak or strong to.
    public static func affinities(_ enemy: Enemy, dungeon: String) -> Affinities {
        let name = baseName(enemy.name)
        var out: Affinities = [:]
        func fill(_ a: Affinities) { for (t, v) in a where out[t] == nil { out[t] = v } }
        if let b = bosses[name] { return guarded(b) }
        let w = words(name)
        for (keys, a) in nameRules where matches(w, keys) { fill(a) }
        if let t = creatureTypes[name] ?? (Bestiary.undeadNames.contains(name) ? "undead" : nil), let a = typeRules[t] { fill(a) }
        if let a = dungeonRules[dungeon] { fill(a) }
        return guarded(out)
    }

    /// No enemy is immune to more than one type, and Physical is never worse
    /// than ×0.5, so every class can still win every fight.
    static func guarded(_ a: Affinities) -> Affinities {
        var a = a
        if let p = a[.physical], p < resists { a[.physical] = resists }
        let immunities = DamageType.allCases.filter { a[$0] == immune }
        for t in immunities.dropFirst() { a[t] = resists }
        return a
    }

    /// "Cursed Frost Wraith" and other prefixed names are the same enemy.
    static func baseName(_ n: String) -> String {
        for p in ["Cursed ", "Elite ", "Ancient ", "Enraged ", "Corrupted "] where n.hasPrefix(p) {
            return String(n.dropFirst(p.count))
        }
        return n
    }

    public static func multiplier(_ type: DamageType, against enemy: Enemy, dungeon: String) -> Double {
        affinities(enemy, dungeon: dungeon)[type] ?? 1
    }

    // MARK: Hitting

    /// The damage after the enemy's weakness or resistance. Absorbing heals
    /// the enemy (returns 0). Immune still takes 1, so a hit always counts.
    /// Records what the player has learned about this enemy (the Bestiary).
    public static func apply(_ dmg: Int, _ type: DamageType, enemy e: inout Enemy, run: inout Run, log: inout [String]) -> Int {
        guard dmg > 0 else { return dmg }
        let m = multiplier(type, against: e, dungeon: run.dungeon)
        learn(&run, enemy: e.name, type: type, m: m)
        if m < 0 {
            let heal = Int((Double(dmg) * -m).rounded())
            e.hp = min(e.maxHp, e.hp + heal)
            log.append("\(type.icon) \(e.name) drinks in the \(type.rawValue). It heals \(heal) HP.")
            return 0
        }
        if m == 1 { return dmg }
        return max(1, jsRound(Double(dmg) * m))
    }

    /// The Bestiary remembers each type you've hit an enemy with, and how it
    /// took it ("Frost Wraith" → ["fire": 1.75]). Saved by the app.
    static func learn(_ run: inout Run, enemy: String, type: DamageType, m: Double) {
        let key = baseName(enemy)
        var all = run.learnedAffinities ?? [:]
        var one = all[key] ?? [:]
        guard one[type.rawValue] == nil else { return }
        one[type.rawValue] = m
        all[key] = one
        run.learnedAffinities = all
    }

    /// How the Bestiary says it: "Weak to 🔥 Fire · Resists ❄️ Ice".
    public static func describe(_ learned: [String: Double]) -> String {
        func names(_ f: (Double) -> Bool) -> [String] {
            DamageType.allCases.filter { t in learned[t.rawValue].map(f) ?? false }
                .map { "\($0.icon) \($0.rawValue.capitalized)" }
        }
        var parts: [String] = []
        let vw = names { $0 >= veryWeak }, w = names { $0 > 1 && $0 < veryWeak }
        let r = names { $0 > 0 && $0 < 1 }, i = names { $0 == 0 }, a = names { $0 < 0 }
        if !vw.isEmpty { parts.append("Very weak to " + vw.joined(separator: ", ")) }
        if !w.isEmpty { parts.append("Weak to " + w.joined(separator: ", ")) }
        if !r.isEmpty { parts.append("Resists " + r.joined(separator: ", ")) }
        if !i.isEmpty { parts.append("Immune to " + i.joined(separator: ", ")) }
        if !a.isEmpty { parts.append("Absorbs " + a.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
