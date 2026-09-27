import ActivityKit
import WidgetKit
import SwiftUI

struct DDLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DDLiveActivityAttributes.self) { context in
            // Lock screen / banner presentation
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.statusText)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(context.state.detailText)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.black)
            .activitySystemActionForegroundColor(Color.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.statusText)
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.detailText)
                        .font(.caption)
                }
            } compactLeading: {
                Text("DD")
            } compactTrailing: {
                Text(context.state.detailText)
                    .font(.caption2)
            } minimal: {
                Text("DD")
            }
        }
    }
}
