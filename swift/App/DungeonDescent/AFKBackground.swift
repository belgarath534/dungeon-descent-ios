import BackgroundTasks
import Foundation

/// Background App Refresh for Endless Descent. iOS pauses the app soon after
/// you leave it, which froze the Live Activity until the app was opened
/// again. With a run going, the app asks iOS to wake it now and then (iOS
/// picks when: every 15 minutes at best, more often for apps you use a lot);
/// each wake fights the fights that came due and updates the Live Activity.
enum AFKBackground {
    static let id = "com.dungeon.descent.afk-refresh"

    /// Asks for the next wake, 15 minutes out at the earliest.
    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: id)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
    }

    /// The wake itself: catch up, save, and ask for the next one while the run lasts.
    @MainActor
    static func refresh() {
        let game = GameModel.shared
        let afk = game.afk
        afk.inForeground = false
        afk.catchUp()
        game.saveNow()
        if afk.run?.running == true { schedule() }
    }
}
