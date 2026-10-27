import SwiftUI
import DungeonCore

/// The Spire's climb: the run, its log and Auto Mode's 4-second timer.
@MainActor
final class SpireModel: ObservableObject {
    enum Stage { case setup, climbing, dead, won }

    @Published var stage: Stage = .setup
    @Published var run: SpireRun?
    @Published var log: [String] = []
    @Published var autoMode = false
    @Published var characterIndex = 0
    @Published var message = ""
    @Published var deathLine = ""
    /// Seconds until Auto Mode's next step (for the bar).
    @Published var autoProgress = 1.0
    @Published var blacksmith: BlacksmithModel?

    let game: GameModel
    private var dice = SystemDice()
    private var timer: Timer?
    private var autoStarted = Date()
    static let autoSeconds = 4.0

    init(game: GameModel) { self.game = game }

    var character: PlayerCharacter? {
        game.characters.indices.contains(characterIndex) ? game.characters[characterIndex] : nil
    }

    var characterLevel: Int { character?.persistLevel ?? 1 }

    /// The Time Eater has its own fight music; every other floor plays the Spire's.
    var spireTrack: String { run?.enemy?.name == "The Time Eater" && run?.cleared == false ? "time-eater" : "spire" }

    func toggleAuto() {
        if !autoMode && characterLevel < 5 {
            message = "Auto Mode unlocks at Level 5. Current level: \(characterLevel)."
            Feedback.announce("Auto Mode requires a Level 5 character. Your character is Level \(characterLevel). Keep descending and running AFK to level up, then return to unlock Auto Mode.")
            return
        }
        autoMode.toggle()
        message = ""
        if autoMode && game.store.getItem("dd_spire_auto_seen") == nil {
            game.store.setItem("dd_spire_auto_seen", "1")
            Feedback.announce("Auto Mode enabled. The Spire will advance automatically every 4 seconds. You can still open the Blacksmith or return to the menu at any time.")
        } else {
            Feedback.announce("Auto Mode \(autoMode ? "enabled." : "disabled.")")
        }
    }

    // MARK: Climbing

    func start() {
        guard let ch = character else {
            message = "Select a character first."
            Feedback.announce(message)
            return
        }
        var r = Spire.start(ch, store: game.store, wallet: game.wallet)
        log = []
        let lines = Spire.enter(&r, store: game.store, wallet: game.wallet, dice: &dice)
        run = r
        stage = .climbing
        add(lines)
        Sound.track(spireTrack)
        Feedback.announce("Entering The Spire. \(ch.name). Floor \(r.floor). HP: \(r.hp). "
            + (autoMode ? "Auto Mode active." : "Manual Mode. Defeat the enemy then press Next Floor.") + " " + lines.joined(separator: " "))
        afterStep()
    }

    private func add(_ lines: [String]) {
        log.insert(contentsOf: lines.reversed(), at: 0)
        if log.count > 200 { log.removeLast(log.count - 200) }
    }

    /// spireAttack: taking a turn by hand pauses Auto Mode.
    func act(_ a: Spire.Action) {
        if autoMode {
            autoMode = false
            stopTimer()
            add(["Auto Mode paused — you took manual control."])
        }
        step(a, spoken: true)
    }

    private func step(_ a: Spire.Action, spoken: Bool) {
        guard var r = run else { return }
        let lines = Spire.turn(&r, a, store: game.store, wallet: game.wallet, dice: &dice)
        run = r
        add(lines)
        if spoken || !AppSettings.combatAnnouncements { Feedback.announce(lines.joined(separator: " ") + status(r)) }
        else { Feedback.announce(lines.joined(separator: " ")) }
        Sound.sfx(a == .heavy ? "sfx-heavy-hit" : "sfx-attack")
        afterStep()
    }

    private func status(_ r: SpireRun) -> String {
        r.cleared ? " Press Next Floor to continue." : ""
    }

    func potion() {
        guard var r = run else { return }
        let msg = Spire.potion(&r)
        run = r
        add([msg])
        Feedback.announce(msg)
    }

    func next() {
        guard var r = run, r.cleared else { return }
        let lines = Spire.next(&r, store: game.store, wallet: game.wallet, dice: &dice)
        run = r
        add(lines)
        Sound.track(spireTrack)
        Feedback.announce(lines.joined(separator: " "))
        afterStep()
    }

    /// Records progress and moves on: death, victory, or Auto Mode's next tick.
    private func afterStep() {
        guard let r = run else { return }
        game.achievements.setGlobalMax("spireBestFloor", Double(Spire.bestFloor(game.store)))
        if r.won {
            stopTimer()
            stage = .won
            game.achievements.trackGlobal("timeEaterDefeated")
            game.achievements.award("ach-time-eater")
            Sound.track("menu")
            Sound.sfx("sfx-levelup")
            Feedback.announce("THE TIME EATER IS DEFEATED. You have climbed all 1800 floors of The Spire. 1000 gold awarded. 25 Mystery Coins awarded. 25 percent Blacksmith discount active for 2 hours. You have conquered The Spire. This has never been done before.")
            return
        }
        if r.dead {
            stopTimer()
            died(r)
            return
        }
        _ = game.achievements.check()
        if autoMode { scheduleAuto() }
    }

    private func died(_ r: SpireRun) {
        stage = .dead
        deathLine = Spire.deathLines.randomElement() ?? ""
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        if let ch = character {
            game.addToGraveyard(.object([
                "name": .string(ch.name), "cls": .string(ch.cls), "race": .string(ch.race),
                "level": .number(Double(ch.persistLevel ?? 1)), "dungeon": .string("The Spire"), "difficulty": .string("Spire"),
                "killedBy": .string("The Spire, Floor \(r.floor)"), "topFloor": .number(Double(r.floor)),
                "date": .string("\(c.month ?? 1)/\(c.day ?? 1)/\(c.year ?? 2026)"),
            ]))
            game.postDeath(.init(name: ch.name, cls: ch.cls, dungeon: "The Spire", killedBy: "The Spire at Floor \(r.floor)",
                                 floor: r.floor, kills: 0, gold: r.gold))
        }
        Sound.track("menu")
        Feedback.announce("You have fallen on floor \(r.floor). Your progress is saved. You can ascend again from floor \(Spire.bestFloor(game.store)).")
    }

    func leave() {
        stopTimer()
        run = nil
        stage = .setup
        Feedback.announce("Progress saved. You can return to The Spire anytime from the main menu.")
    }

    // MARK: Auto Mode

    private func scheduleAuto() {
        stopTimer()
        autoStarted = Date()
        autoProgress = 1
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(autoStarted)
        autoProgress = max(0, 1 - elapsed / Self.autoSeconds)
        guard elapsed >= Self.autoSeconds else { return }
        stopTimer()
        guard autoMode, stage == .climbing, blacksmith == nil, let r = run else { return }
        if r.cleared {
            Feedback.announce("Auto Mode — advancing to floor \(r.floor + 1).")
            next()
        } else {
            step(.attack, spoken: false)
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        autoProgress = 1
    }

    // MARK: Blacksmith

    /// openBlacksmithFromSpire: global gold, like the menu's Blacksmith.
    func openBlacksmith() {
        stopTimer()
        blacksmith = .menu(game)
    }

    func closeBlacksmith() {
        blacksmith = nil
        if var r = run, let ch = character {
            Spire.refreshGear(&r, ch, store: game.store, wallet: game.wallet)
            run = r
        }
        Sound.track(spireTrack)
        if autoMode { scheduleAuto() }
        Feedback.announce("Back in The Spire.")
    }
}
