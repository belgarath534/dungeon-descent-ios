import Foundation
import UIKit
import DungeonCore

#if targetEnvironment(macCatalyst)
/// No Apple Watch on a Mac: nothing to connect to.
final class WatchBridge {
    static let shared = WatchBridge()
    func activate() {}
    @MainActor func push() {}
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
                                  message: message, sentAt: Date().timeIntervalSince1970)
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
            break
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
        return WatchLink.encode(snapshot(message: note))
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
