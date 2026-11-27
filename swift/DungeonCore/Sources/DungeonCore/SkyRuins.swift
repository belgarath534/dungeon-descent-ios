import Foundation

/// The Sky Ruins (dungeon 10, 12.3): stacking poison, killer plants, wind,
/// The Garden Grows, and Queen Verdana. The web version is js/35-sky-ruins.js
/// with the same numbers. Enemies come from gamedata.json; their abilities are
/// flags there (poisonChance, thorns, gargoyle, bark, regrow …).
public enum SkyRuins {
    public static let name = "The Sky Ruins"
    static func inSky(_ run: Run) -> Bool { run.dungeon == name }

    /// The run's Sky Ruins state (optional, so older saves load).
    public struct State: Codable, Sendable, Equatable {
        public var poison = 0
        public var poisonTurns = 0
        public var gardenTurns = 0
        public var gardenStage = 0
        /// "strangle", "sleep", "ivy" or "gust": your next action is lost.
        public var loseTurn: String? = nil
        public var bleedTurns = 0
        public var falls = 0
        public var seedUsed = false
        public var antidoteUsed = false
        public var rootsBurnedEarly = false
        public var stoneUsed = false
        public init() {}
    }

    public static let gardenLines = ["",
        "The vines are thicker now. The garden is growing.",
        "Roots crack the floor behind you. The garden is growing.",
        "The garden has noticed you."]

    public static let floorLines = ["",
        "Broken stairs, open sky, and a garden that hasn't been tended in a thousand years. It tends itself now.",
        "Planters hang from chains over nothing. Some of them are breathing.",
        "Empty cages, every door bent outward.",
        "Corridors carved by roots, not hands. They're still carving.",
        "Tools on every wall. One hook is missing. You hear it scraping somewhere ahead.",
        "The water is green and sweet-smelling. Don't.",
        "The bell is wrapped in vines. Every so often, they ring it.",
        "The floor ends. The wind doesn't.",
        "Every plant here leans the same way: toward the throne.",
        "She has been waiting. She has been growing."]

    public static let rootTorch = Item(name: "Root Torch", icon: "🔥", type: "consumable",
        desc: "Burns roots. Use it in a fight to stop a plant (or Queen Verdana) from regrowing.", extraSky: "rootTorch")
    public static let seed = Item(name: "Seed of the Undying", icon: "🌰", type: "relic",
        desc: "Queen Verdana's trophy. Once per run, it saves you from a killing blow at 1 HP.", extraSky: "seed")
    public static let antidote = Item(name: "Antidote", icon: "🧴", type: "consumable",
        desc: "Clears all poison. Health potions don't.", extraSky: "antidote")

    /// isSkyRuinsUnlocked: clearing The Shadow World shows the way up.
    public static func unlocked(_ store: GameStore) -> Bool {
        if store.getItem("dd_dev_mode") == "1" || store.getItem("dd_skyruins_unlocked") == "1" { return true }
        if let s = store.getItem("dd_cleared_dungeons"), s.contains("The Shadow World") {
            store.setItem("dd_skyruins_unlocked", "1")
            return true
        }
        return false
    }

    static func isVerdana(_ e: Enemy) -> Bool { e.isBoss && e.name.hasSuffix("Queen Verdana") }
    static func has(_ run: Run, _ sky: String) -> Bool { run.inventory.contains { $0.extra["skyItem"] == .string(sky) } }
    static func burned(_ e: Enemy) -> Bool { e.flag("skyBurned") }
    static func roots(_ e: Enemy) -> Bool { e.number("regrow") != nil || e.number("bark") != nil || e.number("rootHeal") != nil || isVerdana(e) }

    // MARK: Poison

    public static func poisonPerTurn(_ run: Run) -> Int {
        guard let s = run.sky, s.poison > 0 else { return 0 }
        let d = s.poison * 2
        return run.cls == "Plague Doctor" ? (d + 1) / 2 : d
    }

    static func immune(_ run: Run) -> Bool {
        run.equippedArmor?.extra["skyItem"] == .string("barkMail") && run.hp * 2 > run.maxHp
    }

    static func addPoison(_ run: inout Run, _ stacks: Int, source: String, log: inout [String]) {
        guard stacks > 0 else { return }
        if immune(run) { log.append("🛡️ Your Bark Mail keeps the poison out."); return }
        var s = run.sky ?? State()
        s.poison = min(5, s.poison + stacks)
        s.poisonTurns = 4
        run.sky = s
        let per = poisonPerTurn(run)
        log.append("☠️ Poisoned by \(source): \(s.poison) stack\(s.poison > 1 ? "s" : ""), \(per) damage a turn.")
    }

    /// One poison turn: in a fight (bosses can finish you) or a room walked into (never below 1 HP).
    public static func tickPoison(_ run: inout Run, boss: Bool, log: inout [String]) {
        guard var s = run.sky, s.poison > 0 else { return }
        var dmg = poisonPerTurn(run)
        if !boss { dmg = min(dmg, max(0, run.hp - 1)) }
        run.hp = max(0, run.hp - dmg)
        s.poisonTurns -= 1
        if s.poisonTurns <= 0 { s.poison = 0; s.poisonTurns = 0 }
        run.sky = s
        log.append("☠️ Poison: \(dmg) damage." + (s.poison == 0 ? " The poison wears off." : ""))
    }

    /// A short status line for the dungeon screen ("" when there's nothing).
    public static func status(_ run: Run) -> String {
        guard inSky(run), let s = run.sky else { return "" }
        var parts: [String] = []
        if s.poison > 0 { parts.append("☠️ Poison \(s.poison) (\(poisonPerTurn(run)) a turn, \(s.poisonTurns) left)") }
        if s.gardenStage > 0 { parts.append("🌱 Garden \(s.gardenStage) of 3") }
        if s.bleedTurns > 0 { parts.append("🩸 Bleeding") }
        return parts.joined(separator: " · ")
    }

    // MARK: The Garden Grows

    static func applyStage(_ e: inout Enemy, _ run: Run) {
        let stage = run.sky?.gardenStage ?? 0
        var have = Int(e.number("skyStage") ?? 0)
        while have < stage {
            have += 1
            e.maxHp = jsRound(Double(e.maxHp) * 1.1)
            e.hp = jsRound(Double(e.hp) * 1.1)
            e.atk = jsRound(Double(e.atk.lowerBound) * 1.1)...jsRound(Double(e.atk.upperBound) * 1.1)
            e.phase1Hp = jsRound(Double(e.phase1Hp) * 1.1)
            e.phase2Hp = jsRound(Double(e.phase2Hp) * 1.1)
        }
        e.mechanics["skyStage"] = .number(Double(have))
    }

    /// A new floor: the garden starts over.
    public static func newFloor(_ run: inout Run) -> [String] {
        guard inSky(run) else { return [] }
        var s = run.sky ?? State()
        s.gardenTurns = 0; s.gardenStage = 0; s.loseTurn = nil
        if run.floor <= 1 { s = State() }
        run.sky = s
        var lines: [String] = []
        if floorLines.indices.contains(run.floor) {
            lines.append("☁️ \(floorLines[run.floor])")
        }
        // Nobody reaches Verdana without a way to burn her roots.
        if run.floor == 9 && !has(run, "rootTorch") {
            run.inventory.append(rootTorch)
            lines.append("🔥 A dead gardener by the stairs still clutches a Root Torch. You take it. You'll need it.")
        }
        return lines
    }

    // MARK: Fights

    /// combatStart: the garden's growth, Verdana's welcome.
    static func combatStart(_ run: inout Run, log: inout [String]) {
        guard inSky(run), var e = run.enemy else { return }
        var s = run.sky ?? State()
        s.stoneUsed = false
        run.sky = s
        applyStage(&e, run)
        run.enemy = e
        if isVerdana(e) { log.append("🌹 \"Welcome to my garden.\" Queen Verdana rises from a throne of thorns.") }
    }

    /// Fire burns roots and bark.
    static func burn(_ run: inout Run, how: String, log: inout [String]) {
        guard var e = run.enemy, roots(e), !burned(e) else { return }
        e.mechanics["skyBurned"] = .bool(true)
        if isVerdana(e) && !e.flag("skyPhase3") {
            var s = run.sky ?? State(); s.rootsBurnedEarly = true; run.sky = s
        }
        log.append(e.number("bark") != nil ? "🔥 \(how) — \(e.name)'s bark armor burns away!"
                                          : "🔥 \(how) — \(e.name)'s roots are burned. It can't regrow.")
        run.enemy = e
    }

    static let fireWords = ["fire", "flame", "burn", "blaze", "inferno", "ember", "immolat", "meteor", "pyro",
                            "scorch", "magma", "lava", "incinerat", "torch", "phoenix"]
    static func fiery(_ s: String) -> Bool { let l = s.lowercased(); return fireWords.contains { l.contains($0) } }

    /// A skill used: fire skills burn roots.
    public static func skillUsed(_ run: inout Run, name: String, effect: String = "", log: inout [String]) {
        guard inSky(run), fiery(name) || fiery(effect) else { return }
        burn(&run, how: name, log: &log)
    }

    /// The start of your turn. Returns true when the turn is lost (the enemy still attacks).
    static func turnStart(_ run: inout Run, attacking: Bool, log: inout [String]) -> Bool {
        guard inSky(run), var e = run.enemy, run.foes.isEmpty else { return false }
        var s = run.sky ?? State()
        // The garden grows every 8 turns on a floor (not during a boss fight:
        // Verdana's fight is long enough already).
        if !e.isBoss { s.gardenTurns += 1 }
        if !e.isBoss && s.gardenTurns % 8 == 0 && s.gardenStage < 3 {
            s.gardenStage += 1
            log.append("🌱 \(gardenLines[s.gardenStage]) (Enemies on this floor: +\(s.gardenStage * 10)% HP and attack.)")
        }
        run.sky = s
        applyStage(&e, run)
        let turn = Int(e.number("skyTurns") ?? 0) + 1
        e.mechanics["skyTurns"] = .number(Double(turn))
        run.enemy = e
        tickPoison(&run, boss: e.isBoss, log: &log)
        if e.flag("corpseBloom"), let p = run.sky, p.poison > 0 {
            let heal = poisonPerTurn(run)
            e.hp = min(e.maxHp, e.hp + heal)
            log.append("🌺 The Corpse Bloom drinks your poison and heals \(heal) HP.")
        }
        if var b = run.sky, b.bleedTurns > 0 {
            let d = min(4, max(0, run.hp - (e.isBoss ? 0 : 1)))
            run.hp -= d; b.bleedTurns -= 1; run.sky = b
            log.append("🩸 You bleed for \(d).")
        }
        // A fire weapon burns roots.
        if attacking, let w = run.equippedWeapon, fiery(w.name) || w.extra["element"] == .string("fire") {
            run.enemy = e
            burn(&run, how: "Your \(w.name)", log: &log)
            e = run.enemy ?? e
        }
        // Regrowth.
        let regrow: Int = {
            if let r = e.number("rootHeal") { return Int(r) }
            if let r = e.number("regrow"), !burned(e) { return Int(r) }
            if isVerdana(e) && e.flag("skyPhase3") && !burned(e) { return 20 }
            return 0
        }()
        if regrow > 0 && e.hp < e.maxHp {
            e.hp = min(e.maxHp, e.hp + regrow)
            log.append(isVerdana(e) ? "🌹 Verdana's roots drink from the stone. She regrows \(regrow) HP." : "🌿 \(e.name) regrows \(regrow) HP.")
        }
        if isVerdana(e) && !e.flag("skyWarned") && !burned(e) && Double(e.hp) <= Double(e.maxHp) * 0.45 {
            e.mechanics["skyWarned"] = .bool(true)
            log.append("🌹 Her roots are reaching into the stone. Burn them (a fire skill, a fire weapon or a Root Torch) before she drops below a third of her health, or she will regrow 20 HP every turn.")
        }
        if e.flag("gardener") && turn % 3 == 0 {
            if run.cls == "Plague Doctor" { log.append("🍄 The Gardener plants a Spore Pod. Your bird mask filters the spores.") }
            else { log.append("🍄 The Gardener plants a Spore Pod. It bursts in your face."); run.enemy = e; addPoison(&run, 1, source: "a Spore Pod", log: &log) }
        }
        if e.flag("sweep") && turn % 3 == 0 {
            var b = run.sky ?? State(); b.bleedTurns = 3; run.sky = b
            log.append("🪓 The Groundskeeper sweeps the pruning hook low. You're bleeding: 4 a turn for 3 turns.")
        }
        run.enemy = e
        if let why = run.sky?.loseTurn {
            var b = run.sky!; b.loseTurn = nil; run.sky = b
            log.append(why == "sleep" ? "💤 You shake off the sleep. Your turn is gone."
                     : why == "gust" ? "🌪️ The gust knocks you off your feet. Your turn is gone."
                     : why == "ivy" ? "🌿 You tear yourself free of the ivy. Your turn is gone."
                     : "🌳 You break free of the grip. Your turn is gone.")
            return true
        }
        if e.flag("kingGust") && turn % 3 == 0 {
            if run.race == "Goliath" { log.append("🌪️ The King calls a gust. You don't move. Mountain Born.") }
            else { var b = run.sky ?? State(); b.loseTurn = "gust"; run.sky = b
                   log.append("🌪️ The Windbroken King calls a gust! You'll lose your next action.") }
        }
        return false
    }

    /// Your damage landing (dealDamage): thorn walls, stone moss, bark, thorns.
    static func onDamage(_ run: inout Run, _ dmg: Int, log: inout [String]) -> Int {
        guard inSky(run), dmg > 0, var e = run.enemy else { return dmg }
        var d = dmg
        defer { run.enemy = e }
        if isVerdana(e) && e.flag("skyThornwall") {
            e.mechanics["skyThornwall"] = .bool(false)
            log.append("🌹 You cut through the wall of thorns. Her attacks are back to full strength, but she's exposed.")
            return 0
        }
        if let g = e.number("gargoyle"), Int(e.number("skyGargoyleHits") ?? 0) < Int(g) {
            e.mechanics["skyGargoyleHits"] = .number((e.number("skyGargoyleHits") ?? 0) + 1)
            d -= d / 2
            log.append("🗿 The moss is hard as stone. Half damage (\(d)).")
        } else if let bark = e.number("bark"), !burned(e) {
            if d >= 20 { e.mechanics["skyBurned"] = .bool(true); log.append("🛡️ Your blow splits the Verdant Knight's bark armor!") }
            else { let b = min(Int(bark), d - 1); d -= b; if b > 0 { log.append("🛡️ The bark armor blocks \(b) damage.") } }
        }
        if let th = e.number("thorns"), run.hp > 1 {
            let t = min(Int(th), run.hp - 1)
            run.hp -= t
            log.append("🌱 The thorns cut you for \(t).")
        }
        if run.equippedWeapon?.extra["skyItem"] == .string("verdantBlade") {
            e.dotDamage = max(e.dotDamage, 3); e.dotTurns = max(e.dotTurns, 3)
        }
        // Verdana's phases (the game's boss phases: two thirds and one third).
        if isVerdana(e) {
            let left = e.hp - d
            if !e.flag("skyPhase2") && Double(left) <= Double(e.maxHp) * 0.66 {
                e.mechanics["skyPhase2"] = .bool(true); e.mechanics["skyThornwall"] = .bool(true)
            }
            if !e.flag("skyPhase3") && Double(left) <= Double(e.maxHp) * 0.33 { e.mechanics["skyPhase3"] = .bool(true) }
        }
        return d
    }

    /// Before the enemy's hit: the thorn wall halves Verdana's attacks.
    static func attackMultiplier(_ run: Run) -> Double {
        guard inSky(run), let e = run.enemy, isVerdana(e), e.flag("skyThornwall") else { return 1 }
        return 0.5
    }

    /// The hit about to land: the Goliath's Stone's Endurance.
    static func incoming(_ run: inout Run, _ taken: Int, log: inout [String]) -> Int {
        guard inSky(run) || run.race == "Goliath", taken > 0 else { return taken }
        if run.race == "Goliath", run.sky?.stoneUsed != true, Double(taken) >= Double(run.maxHp) * 0.15 {
            var s = run.sky ?? State(); s.stoneUsed = true; run.sky = s
            log.append("🗿 Stone's Endurance — you take the blow like a mountain. Damage halved.")
            return jsRound(Double(taken) / 2)
        }
        return taken
    }

    /// After the enemy's hit: poison, strangling, sleep.
    static func afterAttack(_ run: inout Run, taken: Int, dice: inout some Dice, log: inout [String]) {
        guard inSky(run), taken > 0, run.hp > 0, var e = run.enemy else { return }
        if isVerdana(e) { addPoison(&run, 1, source: "her vines", log: &log) }
        else if let p = e.number("poisonChance"), dice.chance(p) {
            addPoison(&run, Int(e.number("poisonStacks") ?? 1), source: e.name, log: &log)
        }
        if e.flag("strangle") && !e.flag("skyStrangled") && dice.chance(0.35) {
            e.mechanics["skyStrangled"] = .bool(true)
            var s = run.sky ?? State(); s.loseTurn = "strangle"; run.sky = s
            log.append("🌳 The Strangler Fig wraps around you! You'll spend your next turn breaking free.")
        }
        if let sl = e.number("sleepChance"), run.sky?.loseTurn == nil, dice.chance(sl) {
            var s = run.sky ?? State(); s.loseTurn = "sleep"; run.sky = s
            log.append("💤 The pollen gets in your eyes. You fall asleep for a moment.")
        }
        run.enemy = e
    }

    /// A kill: spore bursts, harpy gusts, Root Torches, Verdana's seed.
    /// Returns achievement stats to count (dd_ach_stats).
    static func onKill(_ run: inout Run, _ e: Enemy, dice: inout some Dice, log: inout [String]) -> [String] {
        guard inSky(run) else { return [] }
        var earned: [String] = []
        if let b = e.number("burstPoison") {
            if run.cls == "Plague Doctor" { log.append("🍄 The Spore Drifter bursts. Your bird mask filters the cloud.") }
            else { log.append("🍄 The Spore Drifter bursts into a poison cloud!"); addPoison(&run, Int(b), source: "the spore cloud", log: &log) }
        }
        if let g = e.number("harpyGust"), run.race != "Goliath", dice.chance(g) {
            let d = min(6, max(0, run.hp - 1)); run.hp -= d
            log.append("🦅 The harpy's last gust slams you into a wall. You take \(d) damage.")
        }
        if e.flag("gardener") && dice.chance(0.35) {
            run.inventory.append(rootTorch); log.append("🔥 The Hollow Gardener drops a Root Torch.")
        }
        if isVerdana(e) {
            run.inventory.append(seed)
            log.append("🌰 A single seed falls from Verdana's last root: the Seed of the Undying.")
            earned.append("skyVerdanaKills")
            if run.sky?.rootsBurnedEarly == true { earned.append("skyRootsBurnedEarly") }
            if run.sky?.antidoteUsed != true { earned.append("skyNoAntidoteWins") }
            var s = run.sky ?? State(); s.poison = 0; s.poisonTurns = 0; run.sky = s
        } else if dice.chance(0.08) {
            run.inventory.append(antidote); log.append("🧴 You find an Antidote.")
        }
        return earned
    }

    /// Seed of the Undying: once a run, a killing blow leaves you at 1 HP.
    static func seedSaves(_ run: inout Run, log: inout [String]) -> Bool {
        guard run.hp <= 0, run.sky?.seedUsed != true, has(run, "seed") else { return false }
        var s = run.sky ?? State(); s.seedUsed = true; run.sky = s
        run.hp = 1
        log.append("🌰 The Seed of the Undying cracks open. Roots hold you together. You stand at 1 HP.")
        return true
    }

    // MARK: Items

    static func use(_ run: inout Run, at i: Int) -> Inventory.Outcome? {
        guard case .string(let k)? = run.inventory[i].extra["skyItem"] else { return nil }
        switch k {
        case "antidote":
            guard (run.sky?.poison ?? 0) > 0 else { return Inventory.Outcome(message: "You aren't poisoned. Keep the Antidote for later.", used: false) }
            run.inventory.remove(at: i)
            var s = run.sky!; s.poison = 0; s.poisonTurns = 0; s.antidoteUsed = true; run.sky = s
            return Inventory.Outcome(message: "🧴 You drink the Antidote. The poison is gone.")
        case "rootTorch":
            guard run.inCombat, let e = run.enemy else { return Inventory.Outcome(message: "Use the Root Torch in a fight, against something with roots.", used: false) }
            guard roots(e) else { return Inventory.Outcome(message: "This enemy has no roots to burn.", used: false) }
            guard !burned(e) else { return Inventory.Outcome(message: "Its roots are already burned.", used: false) }
            run.inventory.remove(at: i)
            var log: [String] = []
            burn(&run, how: "The Root Torch", log: &log)
            return Inventory.Outcome(message: log.joined(separator: " "))
        default:
            return nil
        }
    }

    // MARK: Rooms: plants and wind

    /// A plant or a gust instead of the room (1 in 6 wind, 15% plants, more as the garden grows).
    public static func hazard(_ run: inout Run, dice: inout some Dice) -> String? {
        guard inSky(run), run.floor < 10 else { return nil }
        let stage = Double(run.sky?.gardenStage ?? 0)
        let r = dice.roll(0...9999)
        let x = Double(r) / 10000
        if x < 1.0 / 6 {
            if run.floor <= 8 && dice.chance(0.18) { return "sky-edge" }
            return "sky-gust"
        }
        if x < 1.0 / 6 + 0.15 + stage * 0.05 {
            let p = dice.roll(0...99)
            return p < 30 ? "sky-ivy" : p < 60 ? "sky-spore" : p < 88 ? "sky-thornwall" : "sky-siren"
        }
        return nil
    }

    static func safeFall(_ run: Run) -> Bool { run.race == "Aarakocra" || has(run, "featherfall") }

    public static func event(_ id: String, run: Run? = nil) -> Encounters.Event? {
        let goliath = run?.race == "Goliath"
        switch id {
        case "sky-gust":
            return goliath
                ? Encounters.Event(id: id, title: "🌪️ A Gust", text: "The wind tears at you, but you don't move. Mountain Born.", choices: ["Walk on"], weight: 0, dungeons: nil)
                : Encounters.Event(id: id, title: "🌪️ A Gust", text: "The wind tears at you! Brace yourself, or let it carry you ahead?", choices: ["Brace (lose 5 HP)", "Let it carry you"], weight: 0, dungeons: nil)
        case "sky-edge":
            let safe = run.map(safeFall) ?? false
            return Encounters.Event(id: id, title: "🌪️ The Edge",
                text: "The floor crumbles under you and the wind pulls you over the edge. You fall to the floor below." + (safe ? " You won't be hurt." : ""),
                choices: [safe ? "Glide down" : "Fall"], weight: 0, dungeons: nil)
        case "sky-ivy":
            return Encounters.Event(id: id, title: "🌿 Strangling Ivy", text: "Ivy wraps around your legs. You'll spend your next action in a fight tearing free.", choices: ["Pull free"], weight: 0, dungeons: nil)
        case "sky-spore":
            return Encounters.Event(id: id, title: "🍄 Spore Pod", text: "A fat spore pod swells on the wall. It's about to burst.", choices: ["Hold your breath and move on", "Search anyway"], weight: 0, dungeons: nil)
        case "sky-thornwall":
            return Encounters.Event(id: id, title: "🌹 Thornwall", text: "A wall of thorns blocks the room. Cut through it, or go around and leave the room unsearched?", choices: ["Cut through (take 8 damage)", "Go around"], weight: 0, dungeons: nil)
        case "sky-siren":
            return Encounters.Event(id: id, title: "🌸 Siren Bloom", text: "A huge flower with a sweet, heavy smell. Breathing it in would heal you… probably.", choices: ["Breathe it in (+15 HP, 2 poison)", "Ignore it"], weight: 0, dungeons: nil)
        default: return nil
        }
    }

    static func hurt(_ run: inout Run, _ n: Int) -> Int { let d = min(n, max(0, run.hp - 1)); run.hp -= d; return d }

    /// The choice for a plant or a gust. `fall`: drop to the next floor.
    public static func choose(_ id: String, _ choice: Int, _ run: inout Run) -> (Encounters.Outcome, fall: Bool, carried: Bool) {
        var log: [String] = []
        var fall = false, carried = false
        switch (id, choice) {
        case ("sky-gust", 0) where run.race == "Goliath": log.append("🌪️ You walk on through the wind.")
        case ("sky-gust", 0): log.append("🌪️ You brace against the wind. You take \(hurt(&run, 5)) damage.")
        case ("sky-gust", _): log.append("🌪️ The wind carries you past this room."); carried = true
        case ("sky-edge", _):
            var s = run.sky ?? State(); s.falls += 1; run.sky = s
            if safeFall(run) { log.append("🪶 You land softly on the floor below.") }
            else { log.append("💥 You hit the ground hard. You take \(hurt(&run, jsRound(Double(run.maxHp) * 0.10))) damage.") }
            fall = true
        case ("sky-ivy", _):
            if run.race == "Goliath" || run.cls == "Artificer" { log.append("🌿 You rip the ivy off without breaking stride.") }
            else { var s = run.sky ?? State(); s.loseTurn = "ivy"; run.sky = s; log.append("🌿 The ivy holds on. Your next action in a fight goes to tearing free.") }
        case ("sky-spore", 0): log.append("🍄 You hold your breath and slip past."); run.searched = true
        case ("sky-spore", _):
            if run.cls == "Plague Doctor" { log.append("🍄 The pod bursts. Your bird mask filters every spore.") }
            else { addPoison(&run, 1, source: "the spores", log: &log) }
        case ("sky-thornwall", 0): log.append("🌹 You hack through the thorns. You take \(hurt(&run, 8)) damage.")
        case ("sky-thornwall", _): log.append("🌹 You go the long way around."); run.searched = true
        case ("sky-siren", 0):
            run.hp = min(run.maxHp, run.hp + 15)
            log.append("🌸 Warmth floods through you. +15 HP.")
            addPoison(&run, 2, source: "the Siren Bloom", log: &log)
        default: log.append("🌸 You leave the flower alone. It turns to watch you go.")
        }
        var out = Encounters.Outcome(message: log.joined(separator: " "))
        if (run.sky?.falls ?? 0) >= 3 && fall { out.stat = "skyFeatherweight" }
        return (out, fall, carried)
    }
}

extension Item {
    init(name: String, icon: String, type: String, desc: String, extraSky: String) {
        self.init(name: name, icon: icon, type: type, desc: desc)
        extra["skyItem"] = .string(extraSky)
    }
}
