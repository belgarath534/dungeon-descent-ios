import SwiftUI
import DungeonCore

/// 12.1: tells players on an old version that a newer one is out (players
/// kept reporting bugs that were already fixed). It asks the App Store's
/// own listing for the newest version, so nothing has to change per release.
/// It can't force an update (Apple doesn't allow that); it asks each time
/// the game opens until they update.
@MainActor
final class UpdateCheck: ObservableObject {
    static let shared = UpdateCheck()
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6821362160")!

    @Published private(set) var storeVersion: String?
    @Published var prompting = false
    private var checked = false

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// "12.0.2" < "12.1": number by number.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    var outdated: Bool { storeVersion.map { Self.isNewer($0, than: Self.current) } ?? false }

    /// Once each time the game opens.
    func check() {
        guard !checked, let id = Bundle.main.bundleIdentifier,
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(id)&t=\(Int(Date().timeIntervalSince1970))") else { return }
        checked = true
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let v = (json["results"] as? [[String: Any]])?.first?["version"] as? String else { return }
            storeVersion = v
            if outdated {
                // After the loading screen and any start-up pop-up.
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                prompting = true
            }
        }
    }

    func openStore() { UIApplication.shared.open(Self.appStoreURL) }
}

/// The pop-up over any screen.
struct UpdatePrompt: ViewModifier {
    @ObservedObject private var update = UpdateCheck.shared

    func body(content: Content) -> some View {
        content.background(
            Color.clear.alert("Update available", isPresented: $update.prompting) {
                Button("Update Now") { update.openStore() }
                Button("Later", role: .cancel) {}
            } message: {
                Text("Dungeon Descent \(update.storeVersion ?? "") is out, with bug fixes and new features. You have \(UpdateCheck.current). Updating keeps your characters and progress." as String)
            }
        )
    }
}
