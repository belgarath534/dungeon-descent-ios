import Foundation
import Capacitor
import ActivityKit

// The iOS half of the Live Activity idea (Android's counterpart is the
// GameStatusNotification plugin in the dungeon-descent-android repo) —
// a lock-screen/Dynamic-Island status while Hunter Mode or Endless
// Descent is running, even backgrounded. Requires iOS 16.2+; silently
// no-ops (resolves without doing anything) on older versions rather
// than erroring, since this is a nice-to-have, not core functionality.
@objc(LiveActivityPlugin)
public class LiveActivityPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "LiveActivityPlugin"
    public let jsName = "LiveActivity"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "update", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "end", returnType: CAPPluginReturnPromise)
    ]

    private var currentActivity: Any?

    @objc func start(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else { call.resolve(); return }
        let statusText = call.getString("title") ?? "Dungeon Descent"
        let detailText = call.getString("text") ?? ""
        let attributes = DDLiveActivityAttributes()
        let state = DDLiveActivityAttributes.ContentState(statusText: statusText, detailText: detailText)
        do {
            let activity = try Activity<DDLiveActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
            currentActivity = activity
            call.resolve()
        } catch {
            call.reject("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    @objc func update(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else { call.resolve(); return }
        let statusText = call.getString("title") ?? "Dungeon Descent"
        let detailText = call.getString("text") ?? ""
        let state = DDLiveActivityAttributes.ContentState(statusText: statusText, detailText: detailText)
        guard let activity = currentActivity as? Activity<DDLiveActivityAttributes> else {
            call.resolve()
            return
        }
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            call.resolve()
        }
    }

    @objc func end(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else { call.resolve(); return }
        guard let activity = currentActivity as? Activity<DDLiveActivityAttributes> else {
            call.resolve()
            return
        }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            currentActivity = nil
            call.resolve()
        }
    }
}
