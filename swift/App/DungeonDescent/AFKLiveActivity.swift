import ActivityKit
import Foundation
import DungeonCore

/// Starts, updates and ends the Endless Descent Live Activity (the web
/// version's _gameStatusNotify did the same with a plain status line).
/// Live Activities need iOS 16.2; on older systems these do nothing.
@MainActor
enum AFKLiveActivity {
    @available(iOS 16.2, *)
    private static var current: Activity<DDLiveActivityAttributes>? {
        Activity<DDLiveActivityAttributes>.activities.first
    }

    @available(iOS 16.2, *)
    private static func state(_ run: AFKRun, status: String) -> DDLiveActivityAttributes.ContentState {
        DDLiveActivityAttributes.ContentState(
            floor: run.floor, hp: run.hp, maxHp: run.maxHp, points: run.points, level: run.level,
            potions: run.potions, nextFight: Date(timeIntervalSince1970: run.lastFightAt + run.fightSeconds),
            status: status, ended: !run.running)
    }

    /// A run is stale once a fight is overdue: the app wasn't running to fight it.
    @available(iOS 16.2, *)
    private static func content(_ run: AFKRun, status: String) -> ActivityContent<DDLiveActivityAttributes.ContentState> {
        ActivityContent(state: state(run, status: status),
                        staleDate: run.running ? Date(timeIntervalSince1970: run.lastFightAt + run.fightSeconds + 20) : nil)
    }

    static func start(_ run: AFKRun) {
        guard #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for old in Activity<DDLiveActivityAttributes>.activities {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        let attrs = DDLiveActivityAttributes(name: run.charName, cls: run.cls,
                                             startedAt: Date(timeIntervalSince1970: run.startedAt))
        _ = try? Activity.request(attributes: attrs, content: content(run, status: run.log.first?.text ?? ""), pushType: nil)
    }

    /// Shows the run as it is now; `alert` lights up the Lock Screen for it.
    static func update(_ run: AFKRun, alert: String? = nil) {
        guard #available(iOS 16.2, *) else { return }
        guard let activity = current else {
            if run.running { start(run) }
            return
        }
        let c = content(run, status: run.log.first?.text ?? "")
        Task {
            if let alert {
                await activity.update(c, alertConfiguration: AlertConfiguration(
                    title: "Endless Descent", body: LocalizedStringResource(stringLiteral: alert), sound: .default))
            } else {
                await activity.update(c)
            }
        }
    }

    /// The run is over: the final floor stays on the Lock Screen for a while.
    static func end(_ run: AFKRun) {
        guard #available(iOS 16.2, *), let activity = current else { return }
        let c = content(run, status: run.log.first?.text ?? "")
        Task { await activity.end(c, dismissalPolicy: .after(Date().addingTimeInterval(30 * 60))) }
    }

    /// Ends a leftover activity when there's no run to show.
    static func endAll() {
        guard #available(iOS 16.2, *) else { return }
        for a in Activity<DDLiveActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
