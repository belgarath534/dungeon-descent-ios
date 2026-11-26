import SwiftUI
import UserNotifications
import AVFoundation
import AudioToolbox
import FirebaseAuth
import FirebaseFirestore

/// Notification choices and the game sounds they play. Saved in
/// chat_members/{uid}/private/push, which only you (and the push server) read.
@MainActor
final class Push: ObservableObject {
    static let shared = Push()

    struct Sound: Identifiable, Hashable {
        let id: String       // file name without ".caf" ("" is the iPhone's own sound)
        let name: String
    }

    static let sounds: [Sound] = [
        Sound(id: "", name: "iPhone default"),
        Sound(id: "dd-ach-gold", name: "Gold Achievement"),
        Sound(id: "dd-ach-silver", name: "Silver Achievement"),
        Sound(id: "dd-ach-special", name: "Special Achievement"),
        Sound(id: "dd-levelup", name: "Level Up"),
        Sound(id: "dd-loot", name: "Loot"),
        Sound(id: "dd-quest", name: "Quest Complete"),
        Sound(id: "dd-tier", name: "Tier Up"),
        Sound(id: "dd-purchase", name: "Purchase"),
        Sound(id: "dd-potion", name: "Potion"),
        Sound(id: "dd-firework", name: "Firework"),
        Sound(id: "dd-victory", name: "Victory"),
        Sound(id: "dd-unlock", name: "Unlock"),
    ]

    /// Which channels notify you (by channel id), and private messages and groups.
    @Published var channels: Set<String> = ["announcements"]
    @Published var dms = true
    @Published var groups = true
    /// Sound per channel id, "dm" and "group".
    @Published var soundFor: [String: String] = ["announcements": "dd-ach-gold", "dm": "dd-ach-silver", "group": "dd-quest"]
    @Published private(set) var loaded = false
    @Published private(set) var chosen = false
    private var token: String?
    private var player: AVAudioPlayer?

    private func ref() -> DocumentReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return Account.db.collection("chat_members").document(uid).collection("private").document("push")
    }

    func load() async {
        guard let ref = ref() else { return }
        if let d = try? await ref.getDocument(), d.exists {
            channels = Set(d["channels"] as? [String] ?? ["announcements"])
            dms = d["dms"] as? Bool ?? true
            groups = d["groups"] as? Bool ?? true
            soundFor.merge(d["sounds"] as? [String: String] ?? [:]) { _, new in new }
            chosen = d["chosen"] as? Bool ?? false
        }
        loaded = true
    }

    func save() async {
        guard let ref = ref() else { return }
        var data: [String: Any] = ["channels": Array(channels), "dms": dms, "groups": groups, "sounds": soundFor,
                                   "chosen": true, "updatedAt": FieldValue.serverTimestamp()]
        if let token { data["token"] = token; data["env"] = Self.apnsEnvironment }
        try? await ref.setData(data, merge: true)
        chosen = true
    }

    /// Asks iOS for permission and registers for push.
    func requestPermission() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    func gotToken(_ data: Data) {
        token = data.map { String(format: "%02x", $0) }.joined()
        Task { await save() }
    }

    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    func preview(_ sound: String) {
        guard !sound.isEmpty, let url = Bundle.main.url(forResource: sound, withExtension: "caf") else {
            AudioServicesPlaySystemSound(1007)
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func soundName(_ id: String?) -> String {
        Self.sounds.first { $0.id == (id ?? "") }?.name ?? "iPhone default"
    }

    /// Tells the push server about a new message, so it can notify the
    /// people who asked for it (with their sounds). The server checks your
    /// sign-in token and the message itself; until it's set up (the
    /// ChatPushURL in Info.plist is empty), this does nothing.
    static func notify(room: Room, text: String, from: String) async {
        guard let base = Bundle.main.object(forInfoDictionaryKey: "ChatPushURL") as? String, !base.isEmpty,
              let url = URL(string: base), let token = try? await Auth.auth().currentUser?.getIDToken() else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["kind": room.kind.rawValue, "room": room.id])
        _ = try? await URLSession.shared.data(for: req)
    }
}
