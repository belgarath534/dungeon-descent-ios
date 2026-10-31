import ActivityKit
import Foundation
import UIKit
import FirebaseAuth
import DungeonCore

/// Keeps the Endless Descent Live Activity moving while the app is closed.
/// iOS pauses the app soon after you leave it, so it can't update the Lock
/// Screen itself. On the way out, the app works out the next fights with the
/// run's own dice and sends them to the liveActivity cloud function
/// (functions-live/), which pushes each one to the Lock Screen at its time.
/// Opening the app cancels what's left; the game then fights the same fights.
@MainActor
enum LiveActivityPush {
    static let endpoint = URL(string: "https://us-central1-dungeon-descent-fbaf2.cloudfunctions.net/liveActivity")!
    /// Two hours of fights, one every 15 seconds.
    static let horizon = 480
    private static let tokenKey = "dd_live_activity_push_token"
    private static var observing: Set<String> = []

    static var token: String? { UserDefaults.standard.string(forKey: tokenKey) }

    /// Remembers the activity's push token (it can change while it runs).
    @available(iOS 16.1, *)
    static func observe<A: ActivityAttributes>(_ activity: Activity<A>) {
        guard !observing.contains(activity.id) else { return }
        observing.insert(activity.id)
        Task { @MainActor in
            for await data in activity.pushTokenUpdates {
                UserDefaults.standard.set(data.map { String(format: "%02x", $0) }.joined(), forKey: tokenKey)
            }
        }
    }

    /// Leaving the app (or waking in the background): send the next fights.
    static func planAndSend() {
        guard #available(iOS 16.2, *), let token, Auth.auth().currentUser != nil else { return }
        let fights = GameModel.shared.afk.plannedFights(horizon)
        guard !fights.isEmpty else { return }
        let enc = JSONEncoder()
        let states: [[String: Any]] = fights.compactMap { f in
            let s = AFKLiveActivity.state(f.run, status: f.run.log.first?.text ?? "")
            guard let d = try? enc.encode(s), let obj = try? JSONSerialization.jsonObject(with: d) else { return nil }
            var e: [String: Any] = ["at": f.run.lastFightAt, "state": obj, "end": !f.run.running]
            if let a = f.alert { e["alert"] = a }
            return e
        }
        send(token: token, states: states)
    }

    /// Back in the app: the app updates the Live Activity itself again.
    static func cancel() {
        guard Auth.auth().currentUser != nil else { return }
        send(token: token ?? "", states: [])
    }

    private static func send(token: String, states: [[String: Any]]) {
        // Finish the upload even if iOS is putting the app to sleep.
        let bg = BackgroundTime()
        Task {
            defer { bg.end() }
            guard let id = try? await Auth.auth().currentUser?.getIDToken() else { return }
            #if DEBUG
            let sandbox = true
            #else
            let sandbox = false
            #endif
            let body: [String: Any] = ["planId": UUID().uuidString, "token": token, "sandbox": sandbox, "states": states]
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.setValue("Bearer " + id, forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 25
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}

/// A little extra time in the background for one upload.
@MainActor
private final class BackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid
    init() {
        id = UIApplication.shared.beginBackgroundTask { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
