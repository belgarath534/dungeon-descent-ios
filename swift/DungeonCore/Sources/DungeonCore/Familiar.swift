import Foundation

/// The familiar (FAMILIAR_SPECIES, getFamiliar, gainFamiliarBond,
/// familiarSpeak, openFamiliarOverlay): a small companion that bonds with you
/// across every run, saved account-wide in "dd_familiar". Bond grows from
/// fights won (+2), rooms searched (+1) and dungeons cleared (+15); every 30
/// is a level. Flavor only: it never changes a fight.
public enum Familiar {
    public struct Species: Sendable {
        public let id, label, name, icon, unlock: String
        let lines: [String]
        let deepLines: [String]
    }

    public static let species: [Species] = [
        Species(id: "raven", label: "Raven", name: "your Raven", icon: "🐦‍⬛", unlock: "Defeat the Void Reaper", lines: [
            "The raven circles once, then settles on your shoulder.",
            "A low caw. The raven has seen this corridor before.",
            "The raven ruffles its feathers, watching the dark ahead.",
            "It tilts its head at you, waiting.",
        ], deepLines: [
            "The raven no longer waits for a command. It just knows.",
            "It leans into you when you stop moving. Just for a moment.",
        ]),
        Species(id: "wisp", label: "Will-o’-Wisp", name: "your Will-o’-Wisp", icon: "✨", unlock: "Clear every dungeon at least once", lines: [
            "The wisp drifts closer, casting a faint blue light.",
            "A soft glow pulses beside you — the wisp is calm here.",
            "The wisp flickers, as if remembering something.",
            "It bobs gently at your side, lighting nothing in particular.",
        ], deepLines: [
            "The wisp glows brighter now, without you asking it to.",
            "It stopped flickering nervously a while ago. It trusts this now.",
        ]),
        Species(id: "imp", label: "Imp", name: "your Imp", icon: "👺", unlock: "Earn 100 trophies", lines: [
            "The imp cackles quietly, poking at a crack in the wall.",
            "It tugs at your sleeve, pointing at nothing you can see.",
            "The imp mutters something in a language you don’t know.",
            "It grins up at you, clearly pleased with itself.",
        ], deepLines: [
            "The imp’s grin has softened into something almost fond.",
            "It still causes trouble. Just less of it, lately.",
        ]),
        Species(id: "cat", label: "Spectral Cat", name: "your Spectral Cat", icon: "🐈‍⬛", unlock: "Reach Bond Level 10 with your current familiar", lines: [
            "The cat pads silently ahead, then stops to look back at you.",
            "It sits, tail flicking, ears turned toward the dark.",
            "The cat rubs against your leg without making a sound.",
            "It watches something you can’t see. Then loses interest.",
        ], deepLines: [
            "The cat sleeps closer to you now than it ever used to.",
            "It doesn’t flinch at the dark anymore. Not with you here.",
        ]),
    ]

    public struct State: Equatable, Sendable {
        public var speciesId: String
        public var startingSpeciesId: String
        public var bond: Int
        public var name: String

        public var level: Int { bond / 30 + 1 }
        /// Bond toward the next level, out of 30.
        public var intoLevel: Int { bond % 30 }
        public var kind: Species { Familiar.species.first { $0.id == speciesId } ?? Familiar.species[0] }
        /// Its name, or "your Raven".
        public var displayName: String {
            let n = name.trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? kind.name : n
        }
        /// familiarTitle: the Bonded at 5, the Loyal at 10, the Inseparable at 20.
        public var title: String { level >= 20 ? "the Inseparable" : level >= 10 ? "the Loyal" : level >= 5 ? "the Bonded" : "" }
        /// familiarEvolutionBadge
        public var badge: String { level >= 20 ? "★" : level >= 10 ? "✧" : level >= 5 ? "✦" : "" }
        /// The menu badge, "🐦‍⬛ ✦ Lv.5" (updateFamiliarBadge).
        public var menuBadge: String { kind.icon + (badge.isEmpty ? "" : " " + badge) + " Lv.\(level)" }
    }

    /// getFamiliar: a player without one gets a random species.
    public static func load(_ store: GameStore, dice: inout some Dice) -> State {
        var o: [String: JSONValue] = [:]
        if let s = store.getItem("dd_familiar"), let d = s.data(using: .utf8),
           case .object(let v)? = try? JSONDecoder().decode(JSONValue.self, from: d) { o = v }
        func str(_ k: String) -> String? { if case .string(let s)? = o[k], !s.isEmpty { return s }; return nil }
        guard let id = str("speciesId") else {
            let pick = species[dice.roll(0...(species.count - 1))].id
            let f = State(speciesId: pick, startingSpeciesId: pick, bond: 0, name: "")
            save(f, store)
            return f
        }
        var bond = 0
        if case .number(let n)? = o["bond"] { bond = Int(n) }
        return State(speciesId: id, startingSpeciesId: str("startingSpeciesId") ?? id, bond: bond,
                     name: { if case .string(let s)? = o["name"] { return s }; return "" }())
    }

    public static func load(_ store: GameStore) -> State {
        var d = SystemDice()
        return load(store, dice: &d)
    }

    static func save(_ f: State, _ store: GameStore) {
        let v = JSONValue.object(["speciesId": .string(f.speciesId), "startingSpeciesId": .string(f.startingSpeciesId),
                                  "bond": .number(Double(f.bond)), "name": .string(f.name)])
        if let d = try? JSONEncoder().encode(v), let s = String(data: d, encoding: .utf8) { store.setItem("dd_familiar", s) }
    }

    /// The species you can choose: the one you started with, and each whose
    /// milestone you've reached.
    public static func isUnlocked(_ sp: Species, _ f: State, achievements: AchievementBook) -> Bool {
        if sp.id == f.startingSpeciesId { return true }
        switch sp.id {
        case "raven": return achievements.stat("voidReaperDefeated") >= 1
        case "wisp": return achievements.stat("abyssalComplete") >= 1
        case "imp": return achievements.trophies >= 100
        case "cat": return achievements.stat("familiarBondLevel") >= 10
        default: return false
        }
    }

    @discardableResult
    public static func choose(_ id: String, store: GameStore, achievements: AchievementBook) -> Bool {
        var f = load(store)
        guard let sp = species.first(where: { $0.id == id }), isUnlocked(sp, f, achievements: achievements) else { return false }
        f.speciesId = id
        save(f, store)
        return true
    }

    public static func rename(_ name: String, store: GameStore) {
        var f = load(store)
        f.name = String(name.trimmingCharacters(in: .whitespaces).prefix(20))
        save(f, store)
    }

    /// gainFamiliarBond. Returns the line to say when it reaches a new level.
    @discardableResult
    public static func gainBond(_ amount: Int, store: GameStore, achievements: AchievementBook) -> String? {
        var f = load(store)
        let before = f.level
        f.bond += amount
        save(f, store)
        guard f.level > before else { return nil }
        achievements.setMax("familiarBondLevel", Double(f.level))
        return "\(f.displayName) grows closer to you. Bond level \(f.level)." + (f.title.isEmpty ? "" : " \(f.displayName), \(f.title).")
    }

    /// familiarSpeak: 12% of rooms, a line of its own; deeper ones from level 5.
    public static func speak(_ store: GameStore, dice: inout some Dice) -> String? {
        let f = load(store, dice: &dice)
        guard dice.chance(0.12) else { return nil }
        let pool = f.kind.lines + (f.level >= 5 ? f.kind.deepLines : [])
        return pool[dice.roll(0...(pool.count - 1))]
    }

    /// familiarRecognizeJulio / familiarRecognizeVoidReaper
    public static func recognizesJulio(_ store: GameStore) -> String { "\(load(store).displayName) seems unbothered by Julio. As if this has happened before." }
    public static func recognizesVoidReaper(_ store: GameStore) -> String { "\(load(store).displayName) goes very still. It knows exactly what this is." }
}
