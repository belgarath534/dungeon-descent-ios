import Foundation
import WatchConnectivity
import WatchKit

/// The watch's view of the game: whatever the iPhone last sent, plus the
/// commands it sends back. The phone keeps the save; nothing is stored here
/// but the last state, so the app opens on it even with the phone away.
@MainActor
final class WatchStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchLink.Snapshot?
    @Published private(set) var reachable = false
    @Published private(set) var busy = false
    /// The answer to the last command, or why it couldn't be sent.
    @Published var message: String?

    private let cacheKey = "dd_watch_snapshot"

    override init() {
        super.init()
        // App Store screenshots: started with -demo (characters) or -demoRun
        // (a run going), the watch shows sample data instead of the phone's.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demo") || args.contains("-demoRun") {
            snapshot = Self.demo(running: args.contains("-demoRun"))
            return
        }
        if let d = UserDefaults.standard.data(forKey: cacheKey),
           let s = try? JSONDecoder().decode(WatchLink.Snapshot.self, from: d) { snapshot = s }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    static func demo(running: Bool) -> WatchLink.Snapshot {
        let now = Date().timeIntervalSince1970
        let chars = [
            WatchLink.Character(index: 0, name: "Seraphine", cls: "Paladin", level: 14, dungeon: "The Hollow"),
            WatchLink.Character(index: 1, name: "Grimwald", cls: "Necromancer", level: 9, dungeon: "Crypt of Malachar"),
            WatchLink.Character(index: 2, name: "Kestrel", cls: "Ranger", level: 6, dungeon: "Frosthold Abyss"),
        ]
        let run = WatchLink.Run(charName: "Seraphine", cls: "Paladin", floor: 27, hp: 640, maxHp: 1000, level: 15,
                                points: 412, potions: 3, enemiesDefeated: 58, bossesDefeated: 2, running: true,
                                nextFightAt: now + 11, startedAt: now - 1800,
                                log: ["⚔ Bone Colossus defeated! +18 points.", "🧪 Potion used. Restored 250 HP.",
                                      "⬇ Descended to floor 27."])
        return WatchLink.Snapshot(characters: chars, run: running ? run : nil, totalPoints: 1280, bestFloor: 41,
                                  message: nil, sentAt: now)
    }

    var run: WatchLink.Run? { snapshot?.run }
    var characters: [WatchLink.Character] { snapshot?.characters ?? [] }

    func refresh() { send(.status) }
    func start(_ c: WatchLink.Character) { send(.start, index: c.index) }
    func potion() { send(.potion) }
    func end() { send(.end) }

    private func send(_ cmd: WatchLink.Command, index: Int? = nil) {
        let s = WCSession.default
        guard s.activationState == .activated else {
            if cmd != .status { message = "Connecting to your iPhone… try again in a moment." }
            return
        }
        var msg: [String: Any] = [WatchLink.commandKey: cmd.rawValue]
        if let index { msg[WatchLink.indexKey] = index }
        // isReachable is often false for a moment even with the phone in hand
        // (right after opening, or while the phone app sleeps), so always try:
        // a message wakes the phone app when it can.
        busy = cmd != .status
        s.sendMessage(msg, replyHandler: { reply in
            Task { @MainActor in
                self.busy = false
                if let snap = WatchLink.decode(reply) {
                    self.apply(snap)
                    if let m = snap.message { self.message = m }
                    if cmd != .status { WKInterfaceDevice.current().play(.click) }
                }
            }
        }, errorHandler: { error in
            Task { @MainActor in
                self.busy = false
                // A status check that fails stays quiet: the last state the
                // phone sent is still on screen.
                guard cmd != .status else { return }
                // A button press waits in line and happens as soon as they connect.
                s.transferUserInfo(msg)
                self.message = "Sent — your iPhone will do it as soon as it connects."
                WKInterfaceDevice.current().play(.click)
            }
        })
    }

    /// New state from the phone. A run that just ended (or died) taps your wrist.
    private func apply(_ snap: WatchLink.Snapshot) {
        let wasRunning = snapshot?.run?.running == true
        let oldLevel = snapshot?.run?.level ?? 0
        snapshot = snap
        if let d = try? JSONEncoder().encode(snap) { UserDefaults.standard.set(d, forKey: cacheKey) }
        if let r = snap.run {
            if wasRunning && !r.running { WKInterfaceDevice.current().play(r.hp <= 0 ? .failure : .success) }
            else if r.running && oldLevel > 0 && r.level > oldLevel { WKInterfaceDevice.current().play(.notification) }
        }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        let reach = session.isReachable
        Task { @MainActor in
            self.reachable = reach
            if let snap = WatchLink.decode(ctx), snap.sentAt > (self.snapshot?.sentAt ?? 0) { self.apply(snap) }
            self.refresh()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            if let snap = WatchLink.decode(applicationContext), snap.sentAt > (self.snapshot?.sentAt ?? 0) { self.apply(snap) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reach = session.isReachable
        Task { @MainActor in
            self.reachable = reach
            if reach { self.refresh() }
        }
    }
}
