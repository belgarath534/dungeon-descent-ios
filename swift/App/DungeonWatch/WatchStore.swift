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
        if let d = UserDefaults.standard.data(forKey: cacheKey),
           let s = try? JSONDecoder().decode(WatchLink.Snapshot.self, from: d) { snapshot = s }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var run: WatchLink.Run? { snapshot?.run }
    var characters: [WatchLink.Character] { snapshot?.characters ?? [] }

    func refresh() { send(.status) }
    func start(_ c: WatchLink.Character) { send(.start, index: c.index) }
    func potion() { send(.potion) }
    func end() { send(.end) }

    private func send(_ cmd: WatchLink.Command, index: Int? = nil) {
        let s = WCSession.default
        guard s.activationState == .activated else { message = "Connecting to your iPhone…"; return }
        guard s.isReachable else {
            message = "Your iPhone isn't in reach. Bring it closer and try again."
            if cmd != .status { WKInterfaceDevice.current().play(.failure) }
            return
        }
        var msg: [String: Any] = [WatchLink.commandKey: cmd.rawValue]
        if let index { msg[WatchLink.indexKey] = index }
        busy = true
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
                self.message = "Couldn't reach your iPhone. Open Dungeon Descent on it and try again."
                if cmd != .status { WKInterfaceDevice.current().play(.failure) }
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
