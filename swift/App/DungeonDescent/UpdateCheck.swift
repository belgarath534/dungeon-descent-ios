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
    /// When the App Store's version came out.
    @Published private(set) var releasedAt: Date?

    /// A day after a release, an old version is locked until it's updated
    /// (the day gives the App Store time to reach everyone, and automatic
    /// updates time to run). Offline, nothing is locked.
    static let graceHours = 24.0
    var required: Bool {
        guard outdated, let r = releasedAt else { return false }
        return Date().timeIntervalSince(r) > Self.graceHours * 3600
    }
    private var lastChecked = Date.distantPast

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

    /// When the game opens (and comes back after a while).
    /// iPhone and iPad only: the Mac and Apple Vision Pro versions often come
    /// out later (their own reviews), so the iPhone's version would lock
    /// them out with nothing to update to.
    static var applies: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        return !ProcessInfo.processInfo.isiOSAppOnMac
        #else
        return false
        #endif
    }

    func check(force: Bool = false) {
        guard Self.applies else { return }
        // When the game opens, and again when it's come back after six hours.
        guard force || Date().timeIntervalSince(lastChecked) > 6 * 3600, let id = Bundle.main.bundleIdentifier,
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(id)&t=\(Int(Date().timeIntervalSince1970))") else { return }
        lastChecked = Date()
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let v = (json["results"] as? [[String: Any]])?.first?["version"] as? String else { return }
            storeVersion = v
            if let d = (json["results"] as? [[String: Any]])?.first?["currentVersionReleaseDate"] as? String {
                releasedAt = ISO8601DateFormatter().date(from: d)
            }
            if force { Feedback.announce(required ? "Still out of date. Please update in the App Store." : "Thanks! You can keep playing.") }
            if outdated && !required && !force {
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

/// 12.1 Update Required: over everything, nothing behind it can be used.
struct UpdateRequired: ViewModifier {
    @ObservedObject private var update = UpdateCheck.shared
    @AccessibilityFocusState private var focus: Bool

    func body(content: Content) -> some View {
        ZStack {
            content
                .accessibilityHidden(update.required)
                .allowsHitTesting(!update.required)
            if update.required {
                ZStack {
                    Color.black.opacity(0.96).ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 18) {
                            Text("⬆ Update Required").font(Theme.decorative(24)).foregroundStyle(Theme.gold)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityFocused($focus)
                            Text("A new version of Dungeon Descent is required to keep playing. You have \(UpdateCheck.current); the new version is \(update.storeVersion ?? ""). It fixes bugs and keeps everyone able to play together. Your characters and progress are kept." as String)
                                .font(Theme.crimson(17)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                            Button("Update in the App Store") { update.openStore() }
                                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                            Button("I Updated — Check Again") { update.check(force: true) }
                                .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                        }
                        .padding(28)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)
                    }
                }
                .onAppear {
                    focus = true
                    Feedback.announce("Update required. A new version of Dungeon Descent is needed to keep playing.", after: 0.6)
                }
            }
        }
    }
}
