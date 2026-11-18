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

    // MARK: Leaderboards and challenges

    /// The leaderboards (made in App Store Connect by tools/game-center.py,
    /// each with a challenge friends can send each other).
    enum Board: String, CaseIterable {
        case endlessFloor = "DD_ENDLESS_BEST_FLOOR"
        case weeklyLadder = "DD_WEEKLY_LADDER"
        case spireFloor = "DD_SPIRE_BEST_FLOOR"

        var title: String {
            switch self {
            case .endlessFloor: return "Endless Descent, deepest floor"
            case .weeklyLadder: return "Weekly Ladder score"
            case .spireFloor: return "The Spire, highest floor"
            }
        }
    }

    /// Posts a score (Game Center keeps the best). Quietly nothing when signed out.
    static func submit(_ score: Int, to board: Board) {
        guard isSignedIn, score > 0 else { return }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [board.rawValue]) { _ in }
    }

    /// Game Center's own page for a leaderboard, with friends' scores and the
    /// Challenge button (iOS 26 and later), read by VoiceOver like any Apple screen.
    static func show(_ board: Board) {
        guard isSignedIn else {
            Feedback.announce("Sign in to Game Center in the Settings app to see leaderboards and challenge friends.")
            return
        }
        let vc = GKGameCenterViewController(leaderboardID: board.rawValue, playerScope: .friendsOnly, timeScope: .allTime)
        vc.gameCenterDelegate = Dismisser.shared
        topViewController()?.present(vc, animated: true)
    }

    private final class Dismisser: NSObject, GKGameCenterControllerDelegate {
        static let shared = Dismisser()
        func gameCenterViewControllerDidFinish(_ vc: GKGameCenterViewController) {
            vc.dismiss(animated: true)
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}
