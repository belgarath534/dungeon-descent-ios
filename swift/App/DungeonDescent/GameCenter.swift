import GameKit
import UIKit
import DungeonCore

/// Signs in to Game Center and reports achievements with the same IDs the web
/// version used ("DD_FIRST_BLOOD" …), so progress there carries over.
@MainActor
enum GameCenter {
    private(set) static var isSignedIn = false

    static func signIn() {
        GKLocalPlayer.local.authenticateHandler = { viewController, _ in
            if let vc = viewController {
                topViewController()?.present(vc, animated: true)
                return
            }
            isSignedIn = GKLocalPlayer.local.isAuthenticated
            if isSignedIn { reportAll(pending) ; pending = [] }
        }
    }

    private static var pending: [String] = []

    static func report(_ achievements: [Achievement]) {
        let ids = achievements.compactMap(\.gcId)
        guard !ids.isEmpty else { return }
        guard isSignedIn else { pending += ids; return }
        reportAll(ids)
    }

    /// Re-sends every unlocked achievement, e.g. after importing a web save.
    static func sync(_ unlockedIDs: [String]) {
        let ids = AchievementBook.all.filter { unlockedIDs.contains($0.id) }.compactMap(\.gcId)
        guard isSignedIn else { pending += ids; return }
        reportAll(ids)
    }

    private static func reportAll(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let list = ids.map { id -> GKAchievement in
            let a = GKAchievement(identifier: id)
            a.percentComplete = 100
            a.showsCompletionBanner = true
            return a
        }
        GKAchievement.report(list) { _ in }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}
