import SwiftUI
import DungeonCore

/// #screen-challenges: The Gauntlet and the Daily Dungeon.
struct ChallengesView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var tab = "gauntlet"
    @State private var gauntletChar = 0
    @State private var dailyChar = 0
    private let gold = Color(hex: 0xffdd44)
    private let daily = Challenges.daily()

    var body: some View {
        WebScreen {
            VStack(alignment: .leading, spacing: 14) {
                Button("← Menu") { router.goTo(.menu) }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to main menu")
                Text("🔥 Challenges").font(Theme.decorative(22)).foregroundStyle(Color(hex: 0xe0c080)).accessibilityAddTraits(.isHeader)
                Text("Only the strongest survive.").font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 0) {
                    tabButton("gauntlet", "⚔ THE GAUNTLET", "The Gauntlet tab — all 6 dungeons back to back")
                    tabButton("daily", "📅 DAILY DUNGEON", "Daily Dungeon tab — one dungeon per day with special modifiers")
                }
                if tab == "gauntlet" { gauntletPanel } else { dailyPanel }
            }
        }
        .onAppear { Feedback.announce("Challenges. Only the strongest survive. The Gauntlet tab is selected.") }
    }

    private func tabButton(_ id: String, _ text: String, _ label: String) -> some View {
        Button {
            tab = id
            Sound.sfx("sfx-select")
            if id == "daily", let best = Challenges.todaysBest(game.store) {
                Feedback.announce("Daily Dungeon. Already completed today. Best time: \(best).")
            } else {
                Feedback.announce(id == "gauntlet" ? "The Gauntlet. All 6 dungeons, one life." : "Daily Dungeon. One special dungeon per day.")
            }
        } label: {
            Text(text).font(Theme.cinzel(10.4)).tracking(1.5)
                .foregroundStyle(tab == id ? gold : Color(hex: 0x666666))
                .frame(maxWidth: .infinity).padding(10)
                .overlay(alignment: .bottom) { Rectangle().fill(tab == id ? gold : .clear).frame(height: 2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(tab == id ? [.isSelected, .isButton] : .isButton)
    }

    private func box<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x2a2010)))
            .accessibilityElement(children: .combine)
    }

    private func characters(_ selected: Binding<Int>, label: String) -> some View {
        VStack(spacing: 8) {
            if game.characters.isEmpty {
                Text("No characters. Create one first.").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x555555))
            }
            ForEach(Array(game.characters.enumerated()), id: \.offset) { i, c in
                Button("\(c.name) — \(c.cls) (Lv \(c.persistLevel ?? 1))") {
                    selected.wrappedValue = i
                    Sound.sfx("sfx-select")
                    Feedback.announce("\(c.name) selected.")
                }
                .buttonStyle(WebButtonStyle(kind: i == selected.wrappedValue ? .gold : .ghost))
                .accessibilityLabel("\(c.name), \(c.cls), Level \(c.persistLevel ?? 1).")
                .accessibilityAddTraits(i == selected.wrappedValue ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var gauntletPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            box {
                Text("All 6 Dungeons. One Life.").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xe0c080))
                Text("Enter the Gauntlet and face all six dungeons back to back without rest. No healing between dungeons. No second chances. Clear all 60 floors or fall trying.")
                    .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x666666)).lineSpacing(4)
                Text("Reward: The Gauntlet Champion title and exclusive achievement.")
                    .font(Theme.crimson(10, italic: true)).foregroundStyle(Color(hex: 0x444444))
            }
            characters($gauntletChar, label: "Select a character for the Gauntlet")
            Button("⚔ Enter the Gauntlet") { start(.gauntlet, gauntletChar) }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .disabled(game.characters.isEmpty)
                .accessibilityLabel("Begin the Gauntlet — all 6 dungeons, one life")
        }
    }

    private var dailyPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            box {
                Text("Today's Dungeon").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xe0c080))
                Text(daily.dungeon).font(Theme.cinzel(13.6)).foregroundStyle(.white)
                ForEach(daily.mods, id: \.id) { m in
                    Text("⚡ \(m.name) — \(m.desc)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xaaaaaa))
                }
                Text("Resets at midnight.").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x444444))
            }
            Text(Challenges.todaysBest(game.store).map { "Today completed! Best time: \($0). Come back tomorrow." } ?? "Not yet completed today.")
                .font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xaaaaaa))
            characters($dailyChar, label: "Select a character for the Daily Dungeon")
            Button("📅 Enter the Daily Dungeon") { start(.daily, dailyChar) }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .disabled(game.characters.isEmpty)
                .accessibilityLabel("Begin today's Daily Dungeon, \(daily.dungeon)")
        }
    }

    private func start(_ c: RunModel.Challenge, _ index: Int) {
        guard game.characters.indices.contains(index) else { Feedback.announce("Please select a character."); return }
        let ch = game.characters[index]
        // A run in progress would be resumed instead; the Challenge replaces it (as on the web).
        game.clearRun(for: index)
        RunModel.pendingChallenge = c
        Sound.sfx("sfx-select")
        router.goTo(.dungeon(ch.created, resume: false))
        Feedback.announce(c == .gauntlet
            ? "The Gauntlet begins. \(ch.name) enters \(Challenges.gauntlet[0]). Survive all 6 dungeons. One life."
            : "Daily Dungeon begins. \(ch.name) enters \(daily.dungeon). Active modifiers: \(daily.mods.map(\.name).joined(separator: ", ")).", after: 1.5)
    }
}
