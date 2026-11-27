#if DEBUG
import Foundation
import FirebaseAuth
import FirebaseFirestore

/// App Store screenshots (the "Chat app screenshots" workflow): the app runs
/// against the local Firebase emulators, filled with sample players and
/// messages by tools/chat-screenshot-seed.mjs, signs in by itself and opens
/// one screen. Only in Debug builds; the App Store build never has it.
///
///   -useEmulator                      the emulators on this Mac (127.0.0.1)
///   -signInEmail E -signInPassword P  sign in as that player
///   -startTab N                       0 Channels … 4 Profile
///   -openRoom channel:general         open a conversation (channel, dm, group)
enum ScreenshotMode {
    static let args = ProcessInfo.processInfo.arguments
    static var on: Bool { args.contains("-useEmulator") }

    static func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var startTab: Int { Int(value("-startTab") ?? "") ?? 0 }

    /// Called right after FirebaseApp.configure(), before anything uses Firebase.
    static func setUp() {
        guard on else { return }
        Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
        let db = Account.db
        let s = db.settings
        s.host = "127.0.0.1:8085"
        s.isSSLEnabled = false
        s.cacheSettings = MemoryCacheSettings()
        db.settings = s
        if let email = value("-signInEmail"), let password = value("-signInPassword"), Auth.auth().currentUser?.email != email {
            Task { try? await Auth.auth().signIn(withEmail: email, password: password) }
        }
    }

    /// The conversation to open once the lists have loaded.
    @MainActor static func openRoom() {
        guard on, let spec = value("-openRoom") else { return }
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        Router.shared.open = (parts[0], parts[1])
    }
}
#endif
