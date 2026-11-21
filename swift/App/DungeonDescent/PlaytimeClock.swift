import Foundation
import DungeonCore

/// Counts time with the game open (savePlaytime): saved every 30 seconds and
/// when you leave the app; time in the background doesn't count.
@MainActor
final class PlaytimeClock {
    static let shared = PlaytimeClock()
    private var since: Date?
    private var timer: Timer?
    private weak var game: GameModel?

    func start(_ game: GameModel) {
        self.game = game
        since = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in PlaytimeClock.shared.save() }
        }
    }

    func stop() {
        save()
        since = nil
        timer?.invalidate()
        timer = nil
    }

    private func save() {
        guard let since, let game else { return }
        Playtime.add(Date().timeIntervalSince(since), store: game.store)
        self.since = Date()
    }

    /// Total so far, including this session.
    var totalMs: Double {
        guard let game else { return 0 }
        return Playtime.stored(game.store) + (since.map { Date().timeIntervalSince($0) * 1000 } ?? 0)
    }
}
