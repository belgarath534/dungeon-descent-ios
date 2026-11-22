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

// MARK: 12.0: the Battle Pass season

/// The season and its days left, and the days until Monday's new quests,
/// from the date alone (the same 56-day seasons from 23 November 2026 UTC as
/// BattlePass in DungeonCore).
struct PassEntry: TimelineEntry {
    let date: Date
    let season: Int
    let daysLeft: Int
    let questDays: Int
    /// Your tier, from the watch app (nil before it has heard from the phone).
    var tier: Int? = ComplicationData.load()?.passTier
}

enum PassSeason {
    static let first: TimeInterval = 1_795_392_000
    static let span: TimeInterval = 56 * 86400

    static func entry(at date: Date) -> PassEntry {
        let t = date.timeIntervalSince1970
        let n = max(0, Int(((t - first) / span).rounded(.down)))
        let end = first + Double(n + 1) * span
        // 1 January 1970 was a Thursday: Monday is day 4 of that week.
        let day = Int((t / 86400).rounded(.down))
        let weekday = ((day + 3) % 7 + 7) % 7   // 0 = Monday
        return PassEntry(date: date, season: n + 1, daysLeft: max(0, Int(((end - t) / 86400).rounded(.up))),
                         questDays: 7 - weekday)
    }
}

struct PassProvider: TimelineProvider {
    func placeholder(in context: Context) -> PassEntry { PassSeason.entry(at: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (PassEntry) -> Void) { completion(PassSeason.entry(at: Date())) }
    /// One entry a day at midnight UTC for the next week.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PassEntry>) -> Void) {
        let now = Date()
        let midnight = (now.timeIntervalSince1970 / 86400).rounded(.down) * 86400
        let entries = [PassSeason.entry(at: now)] + (1...7).map { PassSeason.entry(at: Date(timeIntervalSince1970: midnight + Double($0) * 86400)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct PassComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PassEntry

    private var spoken: String {
        (entry.tier.map { "Battle Pass tier \($0). " } ?? "")
            + "Season \(entry.season): \(entry.daysLeft) days left. New quests in \(entry.questDays) day\(entry.questDays == 1 ? "" : "s")."
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text("🏆").font(.system(size: 16))
                    Text(entry.tier.map { "T\($0)" } ?? "\(entry.daysLeft)d").font(.system(size: 13, weight: .semibold))
                }
            case .accessoryInline:
                Text("🏆 " + (entry.tier.map { "Tier \($0) · " } ?? "") + "\(entry.daysLeft)d left")
            case .accessoryCorner:
                Text("🏆").font(.system(size: 20))
                    .widgetLabel("Season \(entry.season) · \(entry.daysLeft)d")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text("🏆 Battle Pass" + (entry.tier.map { " · Tier \($0)" } ?? "")).font(.system(size: 13, weight: .semibold))
                    Text("Season \(entry.season) · \(entry.daysLeft) days left").font(.system(size: 14))
                    Text("New quests in \(entry.questDays)d").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .widgetBackgroundIfAvailable()
    }
}

struct PassSeasonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BattlePassSeason", provider: PassProvider()) { entry in
            PassComplicationView(entry: entry)
        }
        .configurationDisplayName("Battle Pass Season")
        .description("Days left in the Battle Pass season, and until Monday's new quests.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

// MARK: 12.0: your Endless Descent run and daily streak (App Group)

struct DataEntry: TimelineEntry {
    let date: Date
    let data: ComplicationData?
}

struct DataProvider: TimelineProvider {
    func placeholder(in context: Context) -> DataEntry {
        var d = ComplicationData()
        d.charName = "Seraphine"; d.running = true; d.floor = 27; d.hp = 640; d.maxHp = 1000; d.bestFloor = 41; d.streak = 6
        return DataEntry(date: Date(), data: d)
    }
    func getSnapshot(in context: Context, completion: @escaping (DataEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : DataEntry(date: Date(), data: ComplicationData.load()))
    }
    /// The watch app redraws these when something changes; midnight, for the
    /// daily reward, and every half hour as a fallback.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DataEntry>) -> Void) {
        let now = Date()
        let data = ComplicationData.load()
        var entries = [DataEntry(date: now, data: data)]
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) {
            entries.append(DataEntry(date: midnight, data: data))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800))))
    }
}

struct EndlessComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DataEntry

    private var running: Bool { entry.data?.running == true }
    private var floor: Int { running ? entry.data?.floor ?? 0 : entry.data?.bestFloor ?? 0 }
    private var spoken: String {
        guard let d = entry.data else { return "Endless Descent. Open the watch app to connect." }
        return running ? "Endless Descent: \(d.charName ?? "your character") on floor \(d.floor), \(d.hp) of \(d.maxHp) HP."
                       : "Endless Descent: no run going. Best floor \(d.bestFloor)."
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                if running, let d = entry.data, d.maxHp > 0 {
                    Gauge(value: Double(max(0, d.hp)), in: 0...Double(d.maxHp)) {
                        Text("⬇")
                    } currentValueLabel: {
                        Text("\(d.floor)")
                    }
                    .gaugeStyle(.accessoryCircular)
                } else {
                    VStack(spacing: 0) {
                        Text("⬇").font(.system(size: 16))
                        Text("\(floor)").font(.system(size: 13, weight: .semibold))
                    }
                }
            case .accessoryInline:
                Text(running ? "⬇ Floor \(floor) · \(entry.data?.hp ?? 0) HP" : "⬇ Best floor \(floor)")
            case .accessoryCorner:
                Text("⬇").font(.system(size: 20))
                    .widgetLabel(running ? "Floor \(floor)" : "Best \(floor)")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text("⬇ Endless Descent").font(.system(size: 13, weight: .semibold))
                    if running, let d = entry.data {
                        Text("\(d.charName ?? "") · floor \(d.floor)").font(.system(size: 14))
                        Text("HP \(d.hp) / \(d.maxHp)").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Text("No run going").font(.system(size: 14))
                        Text("Best floor \(floor)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .widgetBackgroundIfAvailable()
    }
}

struct StreakComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DataEntry

    private var ready: Bool { entry.data?.dailyReady(entry.date) ?? true }
    private var streak: Int { entry.data?.streak ?? 0 }
    private var spoken: String {
        "Daily reward: \(ready ? "ready to claim" : "claimed"). \(streak)-day streak."
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text(ready ? "🎁" : "🔥").font(.system(size: 16))
                    Text("\(streak)").font(.system(size: 13, weight: .semibold))
                }
            case .accessoryInline:
                Text(ready ? "🎁 Reward ready · \(streak)-day streak" : "🔥 \(streak)-day streak")
            case .accessoryCorner:
                Text(ready ? "🎁" : "🔥").font(.system(size: 20))
                    .widgetLabel(ready ? "Claim! · \(streak)" : "Streak \(streak)")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text("🔥 \(streak)-day streak").font(.system(size: 13, weight: .semibold))
                    Text(ready ? "Your reward is ready!" : "Claimed today").font(.system(size: 14))
                    Text(ready ? "Claim it to keep the streak" : "Come back tomorrow").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .widgetBackgroundIfAvailable()
    }
}

struct EndlessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EndlessDescent", provider: DataProvider()) { entry in
            EndlessComplicationView(entry: entry)
        }
        .configurationDisplayName("Endless Descent")
        .description("Your Endless Descent floor and HP, or your best floor.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyStreak", provider: DataProvider()) { entry in
            StreakComplicationView(entry: entry)
        }
        .configurationDisplayName("Daily Streak")
        .description("Your daily reward streak, and whether today's reward is waiting.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct DungeonWatchWidgets: WidgetBundle {
    var body: some Widget {
        DungeonWatchWidget()
        PassSeasonWidget()
        EndlessWidget()
        StreakWidget()
    }
}

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
