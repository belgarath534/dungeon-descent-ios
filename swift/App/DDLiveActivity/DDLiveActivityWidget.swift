import ActivityKit
import SwiftUI
import WidgetKit

/// Endless Descent on the Lock Screen and in the Dynamic Island: the floor,
/// HP, points, level, potions and a countdown to the next automatic fight,
/// in the AFK screen's colors.
struct DDLiveActivityWidget: Widget {
    static let violet = Color(red: 0x88 / 255, green: 0x88 / 255, blue: 1)
    static let gold = Color(red: 1, green: 0xdd / 255, blue: 0x44 / 255)
    static let dim = Color(white: 0.4)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DDLiveActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color(white: 0.02))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "dungeondescent://afk"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FLOOR").font(.system(size: 10, design: .serif)).foregroundStyle(Self.dim)
                        Text("\(s.floor)").font(.system(size: 26, weight: .bold, design: .serif)).foregroundStyle(Self.violet)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Floor \(s.floor)")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("HP \(s.hp)/\(s.maxHp)").font(.system(size: 12, design: .serif)).foregroundStyle(hpColor(s))
                        Text("⬇ \(s.points) pts").font(.system(size: 12, design: .serif)).foregroundStyle(Color(red: 0.67, green: 0.67, blue: 1))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("HP \(s.hp) of \(s.maxHp). \(s.points) descent points.")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HPBar(state: s)
                        NextFight(state: s, stale: context.isStale)
                        Text(s.status).font(.system(size: 11, design: .serif)).foregroundStyle(Color(white: 0.6)).lineLimit(2)
                    }
                }
            } compactLeading: {
                Text("⬇\(s.floor)").font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(Self.violet)
                    .accessibilityLabel("Endless Descent floor \(s.floor)")
            } compactTrailing: {
                Text(s.ended ? "End" : "\(percent(s))%").font(.system(size: 13, design: .serif)).foregroundStyle(hpColor(s))
                    .accessibilityLabel(s.ended ? "Run ended" : "HP \(percent(s)) percent")
            } minimal: {
                Text("⬇\(s.floor)").font(.system(size: 12, weight: .semibold, design: .serif)).foregroundStyle(Self.violet)
                    .accessibilityLabel("Endless Descent floor \(s.floor)")
            }
            .widgetURL(URL(string: "dungeondescent://afk"))
        }
    }
}

func percent(_ s: DDLiveActivityAttributes.ContentState) -> Int {
    s.maxHp > 0 ? max(0, Int((Double(s.hp) / Double(s.maxHp) * 100).rounded())) : 0
}

/// The AFK screen's HP colors: green over 50%, orange over 25%, then red.
func hpColor(_ s: DDLiveActivityAttributes.ContentState) -> Color {
    let p = percent(s)
    return p > 50 ? Color(red: 0.27, green: 1, blue: 0.27) : p > 25 ? Color(red: 1, green: 0.67, blue: 0.27) : Color(red: 1, green: 0.27, blue: 0.27)
}

struct HPBar: View {
    let state: DDLiveActivityAttributes.ContentState

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.07))
                RoundedRectangle(cornerRadius: 3).fill(hpColor(state))
                    .frame(width: g.size.width * CGFloat(percent(state)) / 100)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

struct NextFight: View {
    let state: DDLiveActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        Group {
            if state.ended {
                Text("The Descent Ends").foregroundStyle(DDLiveActivityWidget.violet)
            } else if stale || state.nextFight < Date() {
                Text("Open Dungeon Descent to catch up").foregroundStyle(DDLiveActivityWidget.dim)
            } else {
                HStack(spacing: 4) {
                    Text("Next fight in")
                    Text(timerInterval: Date()...state.nextFight, countsDown: true).monospacedDigit()
                }
                .foregroundStyle(DDLiveActivityWidget.dim)
            }
        }
        .font(.system(size: 12, design: .serif))
    }
}

struct LockScreenView: View {
    let context: ActivityViewContext<DDLiveActivityAttributes>

    var body: some View {
        let s = context.state
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ENDLESS DESCENT").font(.system(size: 10, design: .serif)).tracking(3).foregroundStyle(DDLiveActivityWidget.dim)
                    Text("\(context.attributes.name) · \(context.attributes.cls)").font(.system(size: 13, design: .serif)).foregroundStyle(Color(white: 0.67))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(s.floor)").font(.system(size: 30, weight: .bold, design: .serif)).foregroundStyle(DDLiveActivityWidget.violet)
                    Text("FLOOR").font(.system(size: 9, design: .serif)).tracking(2).foregroundStyle(DDLiveActivityWidget.dim)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Endless Descent. \(context.attributes.name), \(context.attributes.cls). Floor \(s.floor).")

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("HP").foregroundStyle(Color(white: 0.67))
                    Spacer()
                    Text("\(s.hp) / \(s.maxHp)").foregroundStyle(Color(white: 0.67))
                }
                .font(.system(size: 11, design: .serif))
                HPBar(state: s)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("HP \(s.hp) of \(s.maxHp).")

            HStack(spacing: 14) {
                Text("⬆ Lv \(s.level)").foregroundStyle(DDLiveActivityWidget.gold)
                Text("⬇ \(s.points) pts").foregroundStyle(Color(red: 0.67, green: 0.67, blue: 1))
                Text("🧪 \(s.potions)").foregroundStyle(Color(red: 0.27, green: 1, blue: 0.53))
                Spacer()
            }
            .font(.system(size: 12, design: .serif))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Level \(s.level). \(s.points) descent points. \(s.potions) potions.")

            NextFight(state: s, stale: context.isStale)
            Text(s.status).font(.system(size: 12, design: .serif)).foregroundStyle(Color(white: 0.6)).lineLimit(2)
        }
        .padding(16)
    }
}
