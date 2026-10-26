import SwiftUI
import DungeonCore

/// The web version's #screen-obituary: the newest deaths from players
/// worldwide, or this device's Graveyard when the list can't load.
@MainActor
struct ObituaryView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var deaths: [CloudAccount.Obituary]?
    @State private var loading = true

    var body: some View {
        ZStack {
            WebBackground()
            ScrollView {
                VStack(spacing: 0) {
                    Button("← Menu") { router.goTo(.menu) }
                        .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x888888))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 16)
                        .accessibilityLabel("Back to menu")
                    Text("☠️ Obituary").font(Theme.decorative(17.6)).foregroundStyle(Color(hex: 0xe0c080))
                        .padding(.bottom, 4).accessibilityAddTraits(.isHeader)
                    Text("The fallen. Your deaths and those of players worldwide.")
                        .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x666666))
                        .multilineTextAlignment(.center).padding(.bottom, 20)
                    if loading {
                        note("Loading deaths...")
                    } else if let list = deaths, !list.isEmpty {
                        VStack(spacing: 8) { ForEach(list) { row($0) } }
                    } else {
                        note("The dungeon has claimed no one yet.")
                    }
                    Button("↻ Refresh") { Task { await load() } }
                        .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x888888))
                        .frame(maxWidth: .infinity).padding(10)
                        .background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                        .padding(.top, 16)
                        .accessibilityLabel("Refresh obituary")
                }
                .padding(.horizontal, 16).padding(.vertical, 24)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
        }
        .task { await load() }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x555555))
            .frame(maxWidth: .infinity).padding(20)
    }

    private func row(_ d: CloudAccount.Obituary) -> some View {
        let time = d.isLocal ? "Local" : Self.ago(d.timestamp)
        return VStack(alignment: .leading, spacing: 2) {
            Text("☠ \(d.name)").font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0xcc4444))
            Text("Floor \(d.floor) · \(d.dungeon)").font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x888888))
            Text("Slain by \(d.killedBy) · \(time)").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x111111)).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(d.name) fell on Floor \(d.floor) of \(d.dungeon), slain by \(d.killedBy). \(time)")
    }

    /// _formatObituaryTime
    static func ago(_ ts: Double) -> String {
        guard ts > 0 else { return "" }
        let mins = Int((Date().timeIntervalSince1970 * 1000 - ts) / 60000)
        if mins < 1 { return "Just now" }
        if mins < 60 { return "\(mins)m ago" }
        let hrs = mins / 60
        return hrs < 24 ? "\(hrs)h ago" : "\(hrs / 24)d ago"
    }

    private func load() async {
        loading = true
        var list = await CloudAccount.shared.obituary()
        if list?.isEmpty ?? true { list = graveyard }
        deaths = list
        loading = false
        Feedback.announce((list ?? []).isEmpty ? "The obituary is empty. No one has fallen yet."
                          : "\((list ?? []).count) deaths recorded. Swipe through to read each entry.")
    }

    /// getGraveyardAsObituary
    private var graveyard: [CloudAccount.Obituary] {
        guard let raw = game.store.getItem("dd_graveyard"), let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([JSONValue].self, from: data) else { return [] }
        return list.enumerated().compactMap { i, v in
            guard case .object(let o) = v else { return nil }
            func s(_ k: String) -> String? { if case .string(let x)? = o[k], !x.isEmpty { return x }; return nil }
            var floor = 1
            if case .number(let n)? = o["topFloor"] { floor = max(1, Int(n)) }
            return CloudAccount.Obituary(id: "local-\(i)", name: s("name") ?? "Unknown", dungeon: s("dungeon") ?? "Unknown dungeon",
                                         killedBy: s("killedBy") ?? "unknown causes", floor: floor, timestamp: 0, isLocal: true)
        }
    }
}
