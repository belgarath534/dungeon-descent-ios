import Foundation
import UIKit
import DungeonCore

#if targetEnvironment(macCatalyst) || os(visionOS)
/// No Apple Watch on a Mac or Apple Vision Pro: nothing to connect to.
final class WatchBridge {
    static let shared = WatchBridge()
    func activate() {}
    @MainActor func push() {}
    @MainActor func alert(_ kind: WatchLink.Alert, _ text: String) {}
}
#else
import WatchConnectivity

/// The iPhone's end of the Apple Watch app. The watch picks a character and
/// starts, checks, heals or ends an Endless Descent run; the phone does it
/// with the same AFKModel the AFK screen uses, so both always show the same run.
/// A message from the watch wakes the app in the background if it has to.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let s = session else { return }
        s.delegate = self
        s.activate()
    }

    // MARK: State for the watch

    @MainActor
    func snapshot(message: String? = nil) -> WatchLink.Snapshot {
        let game = GameModel.shared
        let afk = game.afk
        let chars = game.characters.enumerated().map { i, ch in
            WatchLink.Character(index: i, name: ch.name, cls: ch.cls, level: ch.persistLevel ?? 1, dungeon: ch.dungeon)
        }
        var run: WatchLink.Run?
        if let r = afk.run, r.running || afk.phase == .summary || afk.phase == .skills {
            run = WatchLink.Run(charName: r.charName, cls: r.cls, floor: r.floor, hp: r.hp, maxHp: r.maxHp,
                                level: r.level, points: r.points, potions: r.potions,
                                enemiesDefeated: r.enemiesDefeated, bossesDefeated: r.bossesDefeated,
                                running: r.running, nextFightAt: r.lastFightAt + r.fightSeconds,
                                startedAt: r.startedAt, log: Array(r.log.prefix(4).map(\.text)))
        }
        let save = afk.save
        return WatchLink.Snapshot(characters: chars, run: run, totalPoints: save.totalPoints, bestFloor: save.bestFloor,
                                  message: message, sentAt: Date().timeIntervalSince1970,
                                  boss: bossInfo(), pass: passInfo(), daily: dailyInfo(),
                                  coop: CoopModel.current?.watchState)
    }

    // MARK: 12.0: World Boss, Battle Pass, daily reward

    /// Everyone's damage on today's boss, as last checked (the cloud).
    private var bossShared: (season: String, damage: Int)?
    private var bossCheckedAt = Date.distantPast

    @MainActor
    private func bossInfo() -> WatchLink.Boss {
        let store = GameModel.shared.store
        let day = WorldBoss.day()
        let mine = WorldBoss.myDamage(day, store: store)
        let signedIn = CloudAccount.shared.user != nil
        var hp: Int?
        if let s = bossShared, s.season == day.season { hp = WorldBoss.remaining(totalDamage: s.damage + (signedIn ? 0 : mine)) }
        return WatchLink.Boss(name: day.boss.name, strikesLeft: WorldBoss.strikesLeft(day, store: store),
                              strikesPerDay: WorldBoss.strikesPerDay, myDamage: mine, hpLeft: hp,
                              maxHp: WorldBoss.hp, hoursLeft: WorldBoss.hoursLeft())
    }

    /// Checks everyone's damage (at most once a minute) and collects a fallen
    /// boss's reward, then tells the watch.
    @MainActor
    private func refreshBoss(force: Bool = false) {
        guard force || Date().timeIntervalSince(bossCheckedAt) > 60 else { return }
        bossCheckedAt = Date()
        let game = GameModel.shared
        let day = WorldBoss.day()
        Task { @MainActor in
            guard let total = await CloudAccount.shared.worldBossDamage(day.season) else { return }
            self.bossShared = (day.season, total)
            let signedIn = CloudAccount.shared.user != nil
            let all = total + (signedIn ? 0 : WorldBoss.myDamage(day, store: game.store))
            if let r = WorldBoss.claim(day, totalDamage: all, store: game.store, wallet: game.wallet) {
                game.refresh()
                self.alert(.reward, "\(day.boss.name) has fallen! You earn \(r.gold) gold and \(r.fragments) Soul Fragments.")
            }
            self.push()
        }
    }

    @MainActor
    private func passInfo() -> WatchLink.Pass {
        let store = GameModel.shared.store
        let season = BattlePass.season()
        let p = BattlePass.load(store)
        let quests = BattlePass.quests().quests.map { q in
            WatchLink.Quest(text: q.text, have: min(q.target, p.quest[q.id] ?? 0), target: q.target, done: p.questsDone.contains(q.id))
        }
        let next = p.tier < BattlePass.tiers
            ? BattlePass.reward(tier: p.tier + 1, season: season.number).map(\.text).joined(separator: " and ") : ""
        return WatchLink.Pass(season: season.number, tier: p.tier, tiers: BattlePass.tiers, xpIntoTier: p.xpIntoTier,
                              xpPerTier: BattlePass.xpPerTier, daysLeft: season.daysLeft(), next: next, quests: quests)
    }

    @MainActor
    private func dailyInfo() -> WatchLink.Daily {
        let d = DailyDescent.status(GameModel.shared.store)
        return WatchLink.Daily(claimed: d.claimed, streak: d.streak,
                               next: Language.t("Day \(d.next.day):") + " \(d.next.icon) \(Language.t(d.next.name)), " + d.next.parts.joined(separator: ", "))
    }

    // MARK: Taps on the wrist

    private var lastAlert: [WatchLink.Alert: Date] = [:]

    /// A tap on the watch for danger in a run or your co-op turn, when the
    /// watch app can hear it right now. The same kind at most every 20 seconds.
    @MainActor
    func alert(_ kind: WatchLink.Alert, _ text: String) {
        guard let s = session, s.activationState == .activated, s.isPaired, s.isWatchAppInstalled, s.isReachable else { return }
        if let t = lastAlert[kind], Date().timeIntervalSince(t) < 20 { return }
        lastAlert[kind] = Date()
        s.sendMessage([WatchLink.alertKey: kind.rawValue, WatchLink.alertTextKey: Language.t(text)], replyHandler: nil, errorHandler: nil)
    }

    /// Sends the latest state; the watch gets it the next time it can.
    @MainActor
    func push() {
        guard let s = session, s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        try? s.updateApplicationContext(WatchLink.encode(snapshot()))
    }

    // MARK: Commands from the watch

    @MainActor
    private func handle(_ msg: [String: Any]) -> [String: Any] {
        let game = GameModel.shared
        let afk = game.afk
        let cmd = WatchLink.Command(rawValue: msg[WatchLink.commandKey] as? String ?? "") ?? .status
        var note: String?
        afk.catchUp()
        switch cmd {
        case .status:
            refreshBoss()
        case .strike:
            let day = WorldBoss.day()
            if let i = msg[WatchLink.indexKey] as? Int, game.characters.indices.contains(i) {
                let ch = game.characters[i]
                var dice = SystemDice()
                if let s = WorldBoss.strike(day, level: ch.persistLevel ?? 1, store: game.store, dice: &dice) {
                    game.pass(.worldBossStrike)
                    if CloudAccount.shared.user != nil, let b = bossShared, b.season == day.season {
                        bossShared = (b.season, b.damage + s.damage)
                    }
                    let left = WorldBoss.strikesLeft(day, store: game.store)
                    note = (s.crit ? "💥 Critical! " : "⚔ ") + "\(ch.name) deals \(s.damage) damage. \(left) strike\(left == 1 ? "" : "s") left."
                    Task { @MainActor in
                        if CloudAccount.shared.user != nil {
                            await CloudAccount.shared.uploadLadder(score: s.myTotal, season: day.season, name: ch.name)
                        }
                        self.refreshBoss(force: true)
                    }
                } else {
                    note = "No strikes left today. A new boss comes at midnight UTC."
                }
            } else {
                note = "That character is gone. Pull to refresh."
            }
        case .coopAct:
            if let model = CoopModel.current, let raw = msg[WatchLink.actionKey] as? String, let a = Coop.Action(raw) {
                model.act(a)
                note = model.myAction != nil ? "\(model.name(of: a)) chosen." : model.status
            } else {
                note = "The co-op fight has ended."
            }
        case .claimDaily:
            if let r = DailyDescent.claim(store: game.store, wallet: game.wallet) {
                game.refresh()
                note = "Claimed! \(r.gold) gold\(r.bonus != nil ? " and a bonus" : ""). Come back tomorrow to keep your streak."
            } else {
                note = "Already claimed today. Come back tomorrow."
            }
        case .start:
            if afk.run?.running == true {
                note = "A run is already going."
            } else if afk.phase == .skills {
                note = "Pick your new skills on your iPhone first."
            } else if let i = msg[WatchLink.indexKey] as? Int, game.characters.indices.contains(i) {
                afk.picked = i
                afk.begin(quiet: UIApplication.shared.applicationState != .active)
                note = "Endless Descent started with \(game.characters[i].name)."
            } else {
                note = "That character is gone. Pull to refresh."
            }
        case .potion:
            if afk.run?.running == true { note = afk.usePotion() } else { note = "No run going." }
        case .end:
            if afk.run?.running == true {
                afk.endRun()
                note = afk.phase == .skills ? "Run ended. You leveled up — pick your new skills on your iPhone." : "Run ended."
            } else { note = "No run going." }
        }
        // Changed from the watch with the phone in a pocket: new plan for the Lock Screen.
        if cmd != .status && UIApplication.shared.applicationState != .active {
            if afk.run?.running == true { LiveActivityPush.planAndSend() } else { LiveActivityPush.cancel() }
        }
        return WatchLink.encode(snapshot(message: note.map { Language.t($0) }))
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.push() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in replyHandler(self.handle(message)) }
    }

    /// A button press the watch queued while the phone couldn't answer.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in _ = self.handle(userInfo); self.push() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in _ = self.handle(message); self.push() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.push() } }
}
#endif
