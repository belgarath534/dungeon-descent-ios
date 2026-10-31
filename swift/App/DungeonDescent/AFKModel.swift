import SwiftUI
import DungeonCore

/// Runs Endless Descent. A fight happens every 15 seconds. While the app is
/// open, or in the background with music playing, the timer fights them as
/// they come and keeps the Live Activity current. When iOS has paused the
/// app, the fights it missed are fought the moment it's opened again, so the
/// run comes out where it would have been. The run is saved after every
/// fight, so closing the app doesn't lose it either.
@MainActor
final class AFKModel: ObservableObject {
    enum Phase { case setup, running, skills, summary, shop }

    @Published var phase: Phase = .setup
    @Published private(set) var run: AFKRun?
    @Published var picked = 0
    @Published private(set) var skillChoices: [Skill] = []
    @Published private(set) var skillsChosen: Set<String> = []
    /// What happened while the app wasn't looking, until the next fight.
    @Published private(set) var awayReport: String?
    @Published private(set) var shopMessage = ""

    /// False while the app is in the background: big moments then also alert
    /// on the Lock Screen.
    var inForeground = true

    private let game: GameModel
    private var timer: Timer?
    private var dice = SystemDice()
    static let saveKey = "swift_afk_run"

    init(game: GameModel) {
        self.game = game
        if let r = Self.saved(game.store), r.running {
            run = r
            phase = .running
            startTimer()
        } else {
            AFKLiveActivity.endAll()
        }
    }

    static func saved(_ store: GameStore) -> AFKRun? {
        guard let s = store.getItem(saveKey), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AFKRun.self, from: d)
    }

    /// A run is in progress (for the menu and the Live Activity's link).
    static func isRunning(_ store: GameStore) -> Bool { saved(store)?.running == true }

    var save: AFKSave { AFKSave.load(game.store) }

    private func persist() {
        guard let r = run, let d = try? JSONEncoder().encode(r), let s = String(data: d, encoding: .utf8) else { return }
        game.store.setItem(Self.saveKey, s)
        WatchBridge.shared.push()
    }

    // MARK: Running

    /// startAFKRun. Quiet when the Apple Watch starts it with the phone in a
    /// pocket: no music and nothing spoken on the phone.
    func begin(quiet: Bool = false) {
        guard game.characters.indices.contains(picked) else {
            Feedback.announce("Select a character first.")
            return
        }
        let ch = game.characters[picked]
        let inv = game.globalInventory
        let r = AFKRun(character: ch, index: picked, save: save, weapon: inv.equippedWeapon, armor: inv.equippedArmor)
        run = r
        awayReport = nil
        phase = .running
        persist()
        game.saveNow()
        if !quiet {
            Sound.track("afk")
            Feedback.announce("Endless Descent started. \(ch.name). Floor 1. HP: \(r.hp). Auto-combat every \(Int(r.fightSeconds)) seconds.")
        }
        AFKLiveActivity.start(r)
        startTimer()
    }

    /// Back on the AFK screen with a run going (or the app reopened).
    func resume() {
        guard let r = run, r.running else { return }
        Sound.track("afk")
        startTimer()
        if r.fightsDue(at: Date().timeIntervalSince1970) == 0 {
            Feedback.announce("Endless Descent. Floor \(r.floor). HP \(r.hp) of \(r.maxHp). \(r.points) points this run.")
        }
        catchUp()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.catchUp() }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Seconds until the next fight, for the timer bar.
    var nextFightIn: Double {
        guard let r = run, r.running else { return 0 }
        return max(0, r.lastFightAt + r.fightSeconds - Date().timeIntervalSince1970)
    }

    /// Fights every fight that's due: one on a normal tick, many after time away.
    func catchUp() {
        guard var r = run, r.running else { return }
        let due = r.fightsDue(at: Date().timeIntervalSince1970)
        guard due > 0 else { return }
        let floor0 = r.floor, points0 = r.points, level0 = r.level
        var s = save
        var spoken: [String] = []
        var alert: String?
        var fought = 0
        for _ in 0..<min(due, 50_000) {
            let at = r.lastFightAt + r.fightSeconds
            let step = r.fight(dice: &dice, save: s, now: at)
            fought += 1
            spoken += step.spoken
            if let a = step.alert { alert = a }
            if let c = s.checkChallenge(&r) {
                spoken.append(c)
                alert = alert ?? "Daily challenge complete"
            }
            if !r.running { break }
        }
        s.save(game.store)
        run = r
        persist()
        if fought == 1 {
            awayReport = nil
            if inForeground { Feedback.announce(spoken.joined(separator: " ")) }
        } else {
            let report = "While you were away: \(fought) fights. Floor \(floor0) to \(r.floor)."
                + (r.level > level0 ? " Level \(level0) to \(r.level)." : "")
                + " Plus \(r.points - points0) points. HP \(r.hp) of \(r.maxHp)."
                + (r.running ? "" : " " + (spoken.last ?? ""))
            awayReport = report
            if inForeground { Feedback.announce(report) }
        }
        if r.running {
            AFKLiveActivity.update(r, alert: inForeground ? nil : alert)
        } else {
            if !inForeground { AFKLiveActivity.update(r, alert: alert) }
            finish()
        }
    }

    /// afkUsePotion
    @discardableResult
    func usePotion() -> String {
        guard var r = run else { return "No run going." }
        let msg = r.usePotion()
        run = r
        persist()
        if r.running { AFKLiveActivity.update(r) }
        Sound.sfx("sfx-potion")
        Feedback.announce(msg)
        return msg
    }

    /// endAFKRun: the End Run button.
    func endRun() {
        guard var r = run, r.running else { phase = .setup; return }
        r.running = false
        run = r
        finish()
    }

    /// afkEndRun: points, best floor, the character's level, then skills or the summary.
    private func finish() {
        stopTimer()
        guard let r = run else { return }
        var s = save
        s.finish(r)
        s.save(game.store)
        let a = game.achievements
        a.setMax("afkBestFloor", Double(r.floor))
        a.setMax("afkTotalPoints", Double(s.totalPoints))
        a.setMax("afkMaxLevel", Double(r.level))
        if r.level >= 10 && r.floor >= 50 { a.setMax("afkLevel10Floor50", 1) }
        a.check()
        savePersistentLevel(r)
        game.store.removeItem(Self.saveKey)
        game.saveNow()
        AFKLiveActivity.end(r)
        WatchBridge.shared.push()

        let learned = Set(r.skills)
        let available = Skills.all(for: r.cls).filter { !learned.contains($0.effect) }
        if r.levelsGainedThisRun > 0 && !available.isEmpty {
            skillChoices = Array(available.shuffled().prefix(6))
            skillsChosen = []
            phase = .skills
            let n = r.levelsGainedThisRun
            Feedback.announce("Level up skill selection. You gained \(n) level\(n > 1 ? "s" : ""). Choose \(n) skill\(n > 1 ? "s" : "") for your character.")
        } else {
            showSummary()
        }
    }

    /// saveCharPersistentLevel: the level carries into every mode.
    private func savePersistentLevel(_ r: AFKRun) {
        guard game.characters.indices.contains(r.charIndex), game.characters[r.charIndex].name == r.charName else { return }
        game.updateCharacter(r.charIndex) { ch in
            ch.persistLevel = r.level
            ch.extra["persistXp"] = .number(Double(r.xp))
            ch.extra["persistSkills"] = .array(r.skills.map { .string($0) })
            ch.extra["persistMaxHp"] = .number(Double(r.maxHp))
            ch.extra["persistAtk"] = .number(Double(r.atk - 20))
        }
    }

    var skillsToChoose: Int { min(run?.levelsGainedThisRun ?? 0, skillChoices.count) }

    func pickSkill(_ s: Skill) {
        guard var r = run, !skillsChosen.contains(s.effect), skillsChosen.count < skillsToChoose else { return }
        skillsChosen.insert(s.effect)
        if !r.skills.contains(s.effect) { r.skills.append(s.effect) }
        run = r
        savePersistentLevel(r)
        Sound.sfx("sfx-select")
        Feedback.announce("\(s.name) selected.")
        if skillsChosen.count >= skillsToChoose {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.showSummary() }
        }
    }

    private func showSummary() {
        guard let r = run else { phase = .setup; return }
        phase = .summary
        Sound.track("menu")
        Feedback.announce("Run ended. Floor \(r.floor) reached. Level \(r.level). \(r.levelsGainedThisRun) levels gained. \(r.points) descent points earned. Your progress is saved and carries into all game modes.")
    }

    // MARK: Shop

    func buy(_ item: AFKRun.ShopItem) {
        var s = save
        let (msg, ok) = s.buy(item, store: game.store)
        if ok {
            s.save(game.store)
            if item.id == "afk-mystery-coins" { game.addMysteryCoins(2) }
            Sound.sfx("sfx-unlock")
        }
        shopMessage = msg
        Feedback.announce(msg)
    }
}
