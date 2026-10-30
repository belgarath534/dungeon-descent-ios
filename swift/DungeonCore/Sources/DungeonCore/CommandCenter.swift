import Foundation

/// The Command Center (executeCommand, ccHandleInput): play by typing or
/// speaking commands — go places, start or schedule Endless Descent, claim the
/// Daily Descent, check gold and stats, redeem codes, play music, and build a
/// character step by step. This works out what a line means; the app carries
/// out the action.
public struct CommandCenter: Sendable {
    public enum Kind: Sendable { case cmd, info, ok, err }

    public struct Line: Sendable, Equatable {
        public let text: String
        public let kind: Kind
        public init(text: String, kind: Kind) { self.text = text; self.kind = kind }
    }

    public enum Action: Sendable {
        /// One of `destinations`.
        case go(String)
        case afk
        case scheduleAFK(Date)
        case cancelSchedule
        case daily
        case play(String)
        case stopMusic
        case redeem(String)
        /// A finished character; launch Endless Descent with it or not.
        case create(PlayerCharacter, afk: Bool)
    }

    public struct Reply: Sendable {
        public var lines: [Line] = []
        public var spoken = ""
        public var action: Action?
    }

    /// What the stats command reads out.
    public struct Account: Sendable {
        public var gold: Int
        public var characters: Int
        public var fragments: Int
        public var coins: Int
        public init(gold: Int, characters: Int, fragments: Int, coins: Int) {
            self.gold = gold; self.characters = characters; self.fragments = fragments; self.coins = coins
        }
    }

    public static let destinations = ["blacksmith", "spire", "chronicles", "events", "bestiary", "settings", "menu", "highscore", "hall of records"]

    /// The difficulties a character can be made on.
    static let difficulties: [GameData.Difficulty] = GameData.Difficulty.allCases.filter { $0 != .endless }

    enum Step: Sendable { case cls, race, prof, dungeon, difficulty, name, confirm }
    var step: Step?
    var draft: [String: String] = [:]
    var difficulty: GameData.Difficulty = .wanderer

    public init() {}

    public var creating: Bool { step != nil }

    public mutating func run(_ raw: String, account: Account, scheduled: Bool, now: Date = Date()) -> Reply {
        var r = Reply()
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return r }
        r.lines.append(Line(text: "> " + line, kind: .cmd))
        let cmd = line.lowercased()
        let words = cmd.split(whereSeparator: \.isWhitespace).map(String.init)
        let verb = words.first ?? ""
        let args = words.dropFirst().joined(separator: " ")
        func ok(_ t: String) { r.lines.append(Line(text: t, kind: .ok)) }
        func err(_ t: String) { r.lines.append(Line(text: t, kind: .err)) }

        if ["create character", "create", "new character"].contains(cmd) {
            startCreation(&r)
            return r
        }
        if step != nil {
            handleCreation(line, &r)
            return r
        }
        if ["go", "open", "navigate"].contains(verb) {
            if Self.destinations.contains(args) {
                ok("Opening \(args.capitalized)...")
                r.spoken = "Going to \(args)."
                r.action = .go(args)
            } else {
                err("Unknown destination: \"\(args)\". Try: blacksmith, spire, chronicles, events, bestiary, settings, menu.")
                r.spoken = "Unknown destination."
            }
            return r
        }
        if ["start afk", "afk", "endless descent"].contains(cmd) {
            ok("Opening Endless Descent...")
            r.spoken = "Opening Endless Descent."
            r.action = .afk
            return r
        }
        for p in ["start afk at ", "afk at ", "schedule afk "] where cmd.hasPrefix(p) {
            let t = String(cmd.dropFirst(p.count))
            guard let target = Self.parseTime(t, now: now) else {
                err("Could not parse time \"\(t)\". Try: start afk at 12am, afk at 11:30pm")
                r.spoken = "Could not understand that time."
                return r
            }
            let mins = Int(target.timeIntervalSince(now) / 60)
            let f = DateFormatter()
            f.timeStyle = .short
            let label = f.string(from: target)
            ok("AFK run scheduled for \(label) (\(mins / 60)h \(mins % 60)m from now).")
            r.spoken = "AFK run scheduled for \(label). \(mins / 60) hours and \(mins % 60) minutes from now. Sleep well."
            r.action = .scheduleAFK(target)
            return r
        }
        if ["cancel schedule", "cancel afk", "unschedule"].contains(cmd) {
            if scheduled {
                ok("Scheduled command cancelled.")
                r.spoken = "Scheduled AFK run cancelled."
                r.action = .cancelSchedule
            } else {
                err("No scheduled command to cancel.")
                r.spoken = "No scheduled command to cancel."
            }
            return r
        }
        if ["claim daily", "daily", "claim reward"].contains(cmd) {
            ok("Opening Daily Descent reward...")
            r.spoken = "Opening Daily Descent."
            r.action = .daily
            return r
        }
        if ["gold", "how much gold", "money"].contains(cmd) {
            ok("You have \(account.gold) gold.")
            r.spoken = "You have \(account.gold) gold."
            return r
        }
        if cmd.hasPrefix("play ") {
            r.lines.append(Line(text: "Attempting to play: \(args)...", kind: .info))
            r.spoken = "Playing \(args)."
            r.action = .play(args)
            return r
        }
        if ["stop music", "mute music", "pause music"].contains(cmd) {
            ok("Music stopped.")
            r.spoken = "Music stopped."
            r.action = .stopMusic
            return r
        }
        if ["stats", "my stats", "status"].contains(cmd) {
            ok("Gold: \(account.gold)g")
            ok("Characters: \(account.characters)")
            ok("Soul Fragments: \(account.fragments)")
            ok("Mystery Coins: \(account.coins)")
            r.spoken = "Gold \(account.gold). Characters \(account.characters). Soul Fragments \(account.fragments). Mystery Coins \(account.coins)."
            return r
        }
        if cmd == "time" || cmd == "what time is it" {
            let f = DateFormatter()
            f.timeStyle = .short
            let t = f.string(from: now)
            ok("Current time: \(t)")
            r.spoken = "The time is \(t)."
            return r
        }
        if verb == "redeem" || verb == "code", !args.isEmpty {
            r.action = .redeem(args.uppercased())
            return r
        }
        if ["help", "?", "commands"].contains(cmd) {
            let help = [
                "── NAVIGATION ──────────────────",
                "go blacksmith         → Open Blacksmith",
                "go spire              → Open The Spire",
                "go chronicles         → Open Chronicles",
                "go events             → Open Events",
                "go bestiary           → Open Bestiary",
                "go settings           → Open Settings",
                "go highscore          → Open High Score",
                "go hall of records    → Open Hall of Records",
                "go menu               → Main menu",
                "── CHARACTER ───────────────────",
                "create character      → Build a character in terminal",
                "── AFK ─────────────────────────",
                "start afk             → Launch AFK mode now",
                "start afk at 12am     → Schedule AFK at midnight",
                "start afk at 11:30pm  → Schedule at specific time",
                "cancel schedule       → Cancel scheduled command",
                "── REWARDS ─────────────────────",
                "claim daily           → Claim Daily Descent reward",
                "gold                  → Check your gold",
                "stats                 → Full account stats",
                "redeem DDBD26         → Redeem a code",
                "── MUSIC ───────────────────────",
                "play [track]          → Play a music track",
                "stop music            → Stop music",
                "── OTHER ───────────────────────",
                "time                  → Current time",
                "help                  → Show this list",
            ]
            r.lines += help.map { Line(text: $0, kind: .info) }
            r.spoken = "Help displayed. \(help.count) commands available."
            return r
        }
        err("Unknown command: \"\(line)\". Type help to see all commands.")
        r.spoken = "Unknown command. Type help to see all available commands."
        return r
    }

    /// parseTime: "12am", "11:30pm", "23:00"; the next time it comes round.
    public static func parseTime(_ s: String, now: Date, calendar: Calendar = .current) -> Date? {
        let str = s.lowercased().trimmingCharacters(in: .whitespaces)
        var h: Int, m: Int
        if let r = str.range(of: #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#, options: .regularExpression), r == str.startIndex..<str.endIndex {
            let pm = str.hasSuffix("pm")
            let digits = str.dropLast(2).trimmingCharacters(in: .whitespaces).split(separator: ":")
            guard let hh = Int(digits[0]) else { return nil }
            h = hh
            m = digits.count > 1 ? Int(digits[1]) ?? 0 : 0
            guard (1...12).contains(h), (0...59).contains(m) else { return nil }
            if pm && h != 12 { h += 12 }
            if !pm && h == 12 { h = 0 }
        } else if str.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil {
            let p = str.split(separator: ":")
            h = Int(p[0]) ?? 99
            m = Int(p[1]) ?? 99
            guard (0...23).contains(h), (0...59).contains(m) else { return nil }
        } else {
            return nil
        }
        guard var target = calendar.date(bySettingHour: h, minute: m, second: 0, of: now) else { return nil }
        if target <= now { target = calendar.date(byAdding: .day, value: 1, to: target) ?? target }
        return target
    }

    // MARK: Terminal character creator

    static func pick<T>(_ input: String, _ list: [T], _ name: (T) -> String, contains: Bool = false) -> T? {
        let s = input.lowercased()
        if let n = Int(s), list.indices.contains(n - 1) { return list[n - 1] }
        guard !s.isEmpty else { return nil }
        return list.first { contains ? name($0).lowercased().contains(s) : name($0).lowercased().hasPrefix(s) }
    }

    mutating func startCreation(_ r: inout Reply) {
        draft = [:]
        step = .cls
        r.lines.append(Line(text: "── CHARACTER CREATOR ───────────────", kind: .cmd))
        r.lines.append(Line(text: "Creating a new character through the terminal.", kind: .info))
        r.lines.append(Line(text: "Type a number or name. Type cancel to stop.", kind: .info))
        r.lines.append(Line(text: "STEP 1 — Choose your Class:", kind: .cmd))
        r.lines += GameData.classes.enumerated().map { Line(text: "\($0.offset + 1). \($0.element.id) — \($0.element.tagline)", kind: .info) }
        r.spoken = "Step 1. Choose your class. " + GameData.classes.enumerated().map { "\($0.offset + 1) \($0.element.id)" }.joined(separator: ", ")
    }

    mutating func handleCreation(_ raw: String, _ r: inout Reply) {
        let input = raw.lowercased()
        func ok(_ t: String) { r.lines.append(Line(text: t, kind: .ok)) }
        func err(_ t: String, _ said: String) { r.lines.append(Line(text: t, kind: .err)); r.spoken = said }
        func header(_ t: String) { r.lines.append(Line(text: t, kind: .cmd)) }
        if ["cancel", "quit", "exit"].contains(input) {
            step = nil
            draft = [:]
            err("Character creation cancelled.", "Character creation cancelled.")
            return
        }
        switch step {
        case .cls:
            guard let c = Self.pick(input, GameData.classes, { $0.id }) else {
                return err("Invalid class. Type a number 1-\(GameData.classes.count) or a class name.", "Invalid class. Try again.")
            }
            draft["cls"] = c.id
            ok("✓ Class: \(c.id)")
            step = .race
            header("STEP 2 — Choose your Race:")
            r.lines += GameData.races.enumerated().map { Line(text: "\($0.offset + 1). \($0.element.id) — \($0.element.desc)", kind: .info) }
            r.spoken = "Step 2. Choose your race. " + GameData.races.enumerated().map { "\($0.offset + 1) \($0.element.id)" }.joined(separator: ", ")
        case .race:
            guard let x = Self.pick(input, GameData.races, { $0.id }) else {
                return err("Invalid race. Type a number 1-\(GameData.races.count) or a race name.", "Invalid race. Try again.")
            }
            draft["race"] = x.id
            ok("✓ Race: \(x.id)")
            step = .prof
            header("STEP 3 — Choose your Profession:")
            r.lines += GameData.professions.enumerated().map { Line(text: "\($0.offset + 1). \($0.element.id) — \($0.element.desc)", kind: .info) }
            r.spoken = "Step 3. Choose your profession. " + GameData.professions.enumerated().map { "\($0.offset + 1) \($0.element.id)" }.joined(separator: ", ")
        case .prof:
            guard let x = Self.pick(input, GameData.professions, { $0.id }) else {
                return err("Invalid profession. Type a number 1-\(GameData.professions.count) or a profession name.", "Invalid profession. Try again.")
            }
            draft["prof"] = x.id
            ok("✓ Profession: \(x.id)")
            step = .dungeon
            header("STEP 4 — Choose your Dungeon:")
            r.lines += GameData.dungeons.enumerated().map { Line(text: "\($0.offset + 1). \($0.element)", kind: .info) }
            r.spoken = "Step 4. Choose your dungeon. " + GameData.dungeons.enumerated().map { "\($0.offset + 1) \($0.element)" }.joined(separator: ", ")
        case .dungeon:
            guard let d = Self.pick(input, GameData.dungeons, { $0 }, contains: true) else {
                return err("Invalid dungeon. Type a number 1-\(GameData.dungeons.count).", "Invalid dungeon. Try again.")
            }
            draft["dungeon"] = d
            ok("✓ Dungeon: \(d)")
            step = .difficulty
            header("STEP 5 — Choose your Difficulty:")
            r.lines += Self.difficulties.enumerated().map { Line(text: "\($0.offset + 1). \($0.element.rawValue)", kind: .info) }
            r.spoken = "Step 5. Choose difficulty. " + Self.difficulties.enumerated().map { "\($0.offset + 1) \($0.element.rawValue)" }.joined(separator: ", ") + "."
        case .difficulty:
            guard let d = Self.pick(input, Self.difficulties, { $0.rawValue }) else {
                return err("Invalid difficulty. Type 1-\(Self.difficulties.count).", "Invalid difficulty. Try again.")
            }
            difficulty = d
            ok("✓ Difficulty: \(d.rawValue)")
            step = .name
            header("STEP 6 — What is your character's name?")
            r.spoken = "Step 6. What is your character name? Type it and press run."
        case .name:
            let name = String(raw.prefix(20))
            draft["name"] = name
            ok("✓ Name: \(name)")
            step = .confirm
            header("── CHARACTER SUMMARY ───────────────")
            for (k, v) in [("Name:      ", name), ("Class:     ", draft["cls"] ?? ""), ("Race:      ", draft["race"] ?? ""),
                           ("Profession:", draft["prof"] ?? ""), ("Dungeon:   ", draft["dungeon"] ?? ""), ("Difficulty:", difficulty.rawValue)] {
                ok("\(k) \(v)")
            }
            header("Launch into AFK mode? Type yes or no.")
            r.spoken = "Character summary. \(name) the \(draft["race"] ?? "") \(draft["cls"] ?? ""), \(draft["prof"] ?? ""). Dungeon: \(draft["dungeon"] ?? ""). Difficulty: \(difficulty.rawValue). Launch into AFK mode? Type yes or no."
        case .confirm:
            let yes = input == "yes" || input == "y"
            guard yes || input == "no" || input == "n" else {
                return err("Type yes to launch AFK or no to save without launching.", "Type yes or no.")
            }
            let ch = PlayerCharacter(name: draft["name"] ?? "", cls: draft["cls"] ?? "Warrior", race: draft["race"] ?? "Human",
                                     prof: draft["prof"] ?? "Blacksmith", dungeon: draft["dungeon"] ?? GameData.dungeons[0],
                                     difficulty: difficulty)
            r.action = .create(ch, afk: yes)
            step = nil
            draft = [:]
        case nil: break
        }
    }
}
