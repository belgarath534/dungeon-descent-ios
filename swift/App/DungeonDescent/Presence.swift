import SwiftUI
import FirebaseDatabase
import DungeonCore

/// initPresence, cleanStalePresence: this player is marked online in the
/// shared "presence" list every two minutes, and the menu counts everyone
/// seen in the last five.
@MainActor
final class Presence: ObservableObject {
    static let shared = Presence()
    @Published private(set) var online = 0
    private var started = false
    private var timer: Timer?
    private var root: DatabaseReference { Database.database().reference(withPath: "presence") }

    func start(_ store: GameStore) {
        guard !started else { return }
        started = true
        var id = store.getItem("dd_presence_id") ?? ""
        if id.isEmpty {
            id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))
            store.setItem("dd_presence_id", id)
        }
        let me = root.child(id)
        func beat() { me.setValue(["online": true, "t": (Date().timeIntervalSince1970 * 1000).rounded()]) }
        beat()
        me.onDisconnectRemoveValue()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in beat() }
        root.observe(.value) { [weak self] snap in
            let now = Date().timeIntervalSince1970 * 1000
            var count = 0
            for case let child as DataSnapshot in snap.children {
                guard let v = child.value as? [String: Any], let t = (v["t"] as? NSNumber)?.doubleValue else { continue }
                if now - t < 300_000 { count += 1 } else { child.ref.removeValue() }
            }
            Task { @MainActor in self?.online = count }
        }
    }
}
