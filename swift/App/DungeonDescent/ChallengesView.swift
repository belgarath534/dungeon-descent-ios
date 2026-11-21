import SwiftUI
import DungeonCore

/// #screen-challenges: The Gauntlet, the Daily Dungeon and the Weekly Ladder.
struct ChallengesView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var tab = "gauntlet"
    @State private var gauntletChar = 0
    @State private var dailyChar = 0
    @State private var weeklyChar = 0
    @State private var ladder: [CloudAccount.LeaderboardEntry]?
    private let week = Challenges.weekly()
    private let gold = Color(hex: 0xffdd44)
    private let daily = Challenges.daily()

    var body: some View {
        ScreenTabs(items: [.init(id: "gauntlet", title: "The Gauntlet", icon: "flame.fill"),
                           .init(id: "daily", title: "Daily Dungeon", icon: "calendar"),
                           .init(id: "weekly", title: "Weekly Ladder", icon: "chart.bar.fill")],
                   selection: $tab, onBack: { router.goTo(.menu) }, onSelect: announceTab) {
            screen
        }
        .onAppear { Feedback.announce("Challenges. Only the strongest survive. The Gauntlet tab is selected.") }
    }

    private var screen: some View {
        WebScreen {
            VStack(alignment: .leading, spacing: 14) {
                Button("← Menu") { router.goTo(.menu) }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to main menu")
                Text("🔥 Challenges").font(Theme.decorative(22)).foregroundStyle(Color(hex: 0xe0c080)).accessibilityAddTraits(.isHeader)
                Text("Only the strongest survive.").font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
                switch tab {
                case "gauntlet": gauntletPanel
                case "daily": dailyPanel
                default: weeklyPanel
                }
                gameCenterPanel
            }
        }
    }

    /// Game Center: friends' scores and the Challenge button for each leaderboard.
    private var gameCenterPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🎮 CHALLENGE A FRIEND").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
                .accessibilityAddTraits(.isHeader)
            Text("Opens Game Center: see your friends' scores and send them a challenge to beat yours.")
                .font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
            ForEach(GameCenter.Board.allCases, id: \.self) { b in
                Button("🏆 " + b.title) { GameCenter.show(b) }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                    .accessibilityLabel("Game Center leaderboard and challenges: \(b.title)" as String)
            }
        }
        .padding(.top, 10)
    }

    private func announceTab(_ id: String) {
        if id == "daily", let best = Challenges.todaysBest(game.store) {
            Feedback.announce("Daily Dungeon. Already completed today. Best time: \(best).")
        } else {
            Feedback.announce(id == "gauntlet" ? "The Gauntlet. All 6 dungeons, one life."
                              : id == "daily" ? "Daily Dungeon. One special dungeon per day."
                              : "Weekly Ladder. \(week.name). \(week.dungeon), one life. Your best this week: \(Challenges.weeklyBest(game.store)).")
        }
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
                Button("\(c.name) — \(c.cls) (Lv \(c.persistLevel ?? 1))" as String) {
                    selected.wrappedValue = i
                    Sound.sfx("sfx-select")
                    Feedback.announce("\(c.name) selected.")
                }
                .buttonStyle(WebButtonStyle(kind: i == selected.wrappedValue ? .gold : .ghost))
                .accessibilityLabel("\(c.name), \(c.cls), Level \(c.persistLevel ?? 1)." as String)
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
                    Text("⚡ \(m.name) — \(m.desc)" as String).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xaaaaaa))
                }
                Text("Resets at midnight.").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x444444))
            }
            Text(Challenges.todaysBest(game.store).map { "Today completed! Best time: \($0). Come back tomorrow." } ?? "Not yet completed today.")
                .font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xaaaaaa))
            characters($dailyChar, label: "Select a character for the Daily Dungeon")
            Button("📅 Enter the Daily Dungeon") { start(.daily, dailyChar) }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .disabled(game.characters.isEmpty)
                .accessibilityLabel("Begin today's Daily Dungeon, \(daily.dungeon)" as String)
        }
    }

    private var weeklyPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            box {
                Text("This Week's Dungeon — \(week.name)" as String).font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xe0c080))
                Text(week.dungeon).font(Theme.cinzel(13.6)).foregroundStyle(.white)
                ForEach(week.mods, id: \.id) { m in
                    Text("⚡ \(m.name) — \(m.desc)" as String).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xaaaaaa))
                }
                Text("One life. Score: 100 a floor, 5 a kill, 2000 for the boss. Starts over every Monday.")
                    .font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x666666))
            }
            Text("Your best this week: \(Challenges.weeklyBest(game.store))" as String)
                .font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xaaaaaa))
            VStack(alignment: .leading, spacing: 6) {
                Text("🏆 TOP 10 THIS WEEK").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
                    .accessibilityAddTraits(.isHeader)
                if let ladder {
                    if ladder.isEmpty { Text("No scores yet this week. Be the first.").font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textDim) }
                    ForEach(ladder.indices, id: \.self) { i in
                        Text("\(i + 1). \(ladder[i].username) — \(ladder[i].score)" as String)
                            .font(Theme.cinzel(11)).foregroundStyle(i == 0 ? gold : Color(hex: 0xaaaaaa))
                    }
                } else {
                    Text("Loading the ladder...").font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textDim)
                }
                if CloudAccount.shared.user == nil {
                    Text("Sign in (Settings → Account) to put your score on the ladder.")
                        .font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
                }
            }
            characters($weeklyChar, label: "Select a character for the Weekly Ladder")
            Button("📆 Enter the Weekly Ladder") { start(.weekly, weeklyChar) }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .disabled(game.characters.isEmpty)
                .accessibilityLabel("Begin this week's ladder run, \(week.dungeon), one life" as String)
        }
        .task { ladder = await CloudAccount.shared.ladder(week.season) }
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
            : c == .weekly
            ? "Weekly Ladder begins. \(ch.name) enters \(week.dungeon). One life. Active modifiers: \(week.mods.map(\.name).joined(separator: ", "))."
            : "Daily Dungeon begins. \(ch.name) enters \(daily.dungeon). Active modifiers: \(daily.mods.map(\.name).joined(separator: ", ")).", after: 1.5)
    }
}
