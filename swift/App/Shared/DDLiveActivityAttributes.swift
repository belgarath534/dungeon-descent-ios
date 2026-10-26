import ActivityKit
import Foundation

/// The Endless Descent Live Activity's data, compiled into both the app
/// (which starts and updates it) and the DDLiveActivity widget extension
/// (which draws it on the Lock Screen and in the Dynamic Island).
@available(iOS 16.1, *)
struct DDLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var floor: Int
        var hp: Int
        var maxHp: Int
        var points: Int
        var level: Int
        var potions: Int
        /// When the next automatic fight happens.
        var nextFight: Date
        /// The latest thing that happened, as the combat log says it.
        var status: String
        var ended: Bool
    }

    var name: String
    var cls: String
    var startedAt: Date
}
