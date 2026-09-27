import ActivityKit
import Foundation

// Shared between the main app (which starts/updates/ends the activity)
// and the DDLiveActivity widget extension (which renders it) — must be
// compiled into both targets identically.
struct DDLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var statusText: String
        var detailText: String
    }
}
