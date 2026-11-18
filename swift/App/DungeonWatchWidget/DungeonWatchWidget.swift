import SwiftUI
import WidgetKit

/// The Apple Watch complications: today's Daily World Boss and the hours
/// until the next one. Worked out from the date alone (the same UTC day and
/// order as WorldBoss in DungeonCore), so they need nothing from the iPhone.
/// Tapping one opens the watch app.
struct BossEntry: TimelineEntry {
    let date: Date
    let boss: String
    let hoursLeft: Int
}

enum DailyBoss {
    /// The same names, in the same order, as WorldBoss.bosses.
    static let names = ["The Bone Colossus", "The Drowned King", "Mother of Spiders", "The Ash Wyrm",
                        "The Hollow Bell", "The Weeping Statue", "The Hunger"]

    static func entry(at date: Date) -> BossEntry {
        let n = Int(date.timeIntervalSince1970 / 86400)
        let into = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400)
        return BossEntry(date: date, boss: names[((n % names.count) + names.count) % names.count],
                         hoursLeft: max(1, Int(((86400 - into) / 3600).rounded(.up))))
    }
}

struct BossProvider: TimelineProvider {
    func placeholder(in context: Context) -> BossEntry { DailyBoss.entry(at: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (BossEntry) -> Void) {
        completion(DailyBoss.entry(at: Date()))
    }

    /// One entry an hour for the next day; the new boss appears at midnight UTC.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BossEntry>) -> Void) {
        let now = Date()
        let hour = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        let entries = [DailyBoss.entry(at: now)] + (1...24).map { DailyBoss.entry(at: hour.addingTimeInterval(Double($0) * 3600)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct BossComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BossEntry

    private var spoken: String { "World Boss: \(entry.boss). \(entry.hoursLeft) hours left." }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text("🐉").font(.system(size: 16))
                    Text("\(entry.hoursLeft)h").font(.system(size: 13, weight: .semibold))
                }
            case .accessoryInline:
                Text("🐉 \(entry.boss) · \(entry.hoursLeft)h")
            case .accessoryCorner:
                Text("🐉").font(.system(size: 20))
                    .widgetLabel("\(entry.boss) · \(entry.hoursLeft)h")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text("🐉 World Boss").font(.system(size: 13, weight: .semibold))
                    Text(entry.boss).font(.system(size: 14))
                    Text("\(entry.hoursLeft) hours left").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .widgetBackgroundIfAvailable()
    }
}

extension View {
    /// watchOS 10 wants a container background; watchOS 9 has none.
    @ViewBuilder
    func widgetBackgroundIfAvailable() -> some View {
        if #available(watchOS 10.0, *) {
            containerBackground(.clear, for: .widget)
        } else {
            self
        }
    }
}

@main
struct DungeonWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyWorldBoss", provider: BossProvider()) { entry in
            BossComplicationView(entry: entry)
        }
        .configurationDisplayName("Daily World Boss")
        .description("Today's World Boss and the hours until the next one.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
