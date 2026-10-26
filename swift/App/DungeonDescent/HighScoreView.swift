import SwiftUI
import DungeonCore

/// The web version's #screen-highscore. The score tab is all here; the
/// global leaderboard and the developer inbox need the online service, which
/// isn't in the Swift version yet.
@MainActor
struct HighScoreView: View {
    @EnvironmentObject var game: GameModel
    @State private var tab = "score"

    var body: some View {
        let s = HighScore.load(game.store)
        let rank = HighScore.rank(for: s.total)
        let shown = HighScore.categories.filter { (s.breakdown[$0.key] ?? 0) != 0 }
        WebScreen {
            ScreenHeader(title: "🏆 High Score")
            HStack(spacing: 0) {
                tabButton("score", "MY SCORE")
                tabButton("leaderboard", "LEADERBOARD")
                tabButton("inbox", "INBOX")
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x1a1a1a)).frame(height: 1) }
            .padding(.bottom, 4)

            switch tab {
            case "score":
                Text(s.total.formatted())
                    .font(Theme.decorative(40)).foregroundStyle(Theme.gold)
                    .frame(maxWidth: .infinity).padding(.top, 20)
                Text("RANK: \(rank.label)")
                    .font(Theme.cinzel(11.5)).tracking(3.5).foregroundStyle(Color(hex: rank.color))
                    .frame(maxWidth: .infinity).padding(.bottom, 12)
                Text("💰 Global Gold: \(game.wallet.gold.formatted())g  |  🏆 Trophies: \(game.achievements.trophies)")
                    .font(Theme.cinzel(11.2)).tracking(1.1).foregroundStyle(Color(hex: 0x888888))
                    .frame(maxWidth: .infinity)
                Text("Every kill, every achievement, every dungeon cleared earns points. This is your legacy.")
                    .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.bottom, 8)
                Button("☁ Upload to Leaderboard") {
                    Sound.sfx("sfx-select")
                    Feedback.announce("The online leaderboard isn't in the Swift version yet. Coming soon.")
                }
                .font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xffdd44))
                .frame(maxWidth: .infinity).padding(12)
                .background(Color(hex: 0x1a1400)).overlay(Rectangle().stroke(Color(hex: 0xffdd44)))
                .padding(.bottom, 8)
                .accessibilityLabel("Upload score to global leaderboard")
                if shown.isEmpty {
                    Text("Play the game to earn score points. Every action counts.")
                        .font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(20)
                } else {
                    VStack(spacing: 8) {
                        ForEach(shown, id: \.key) { cat in
                            let pts = s.breakdown[cat.key] ?? 0
                            HStack {
                                Text("\(cat.icon) \(cat.label)").font(Theme.cinzel(12.5)).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text("\(pts.formatted()) pts").font(Theme.cinzel(14.4)).foregroundStyle(Theme.gold)
                            }
                            .padding(.vertical, 14).padding(.horizontal, 18)
                            .background(Theme.bgPanel)
                            .overlay(Rectangle().stroke(Theme.borderDim))
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.goldDim).frame(width: 2) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(cat.label): \(pts.formatted()) points")
                        }
                    }
                }
            default:
                Text(tab == "leaderboard" ? "GLOBAL TOP 20" : "MESSAGES FROM THE DEVELOPER")
                    .font(Theme.cinzel(9.6)).tracking(2.9).foregroundStyle(Color(hex: 0x666666))
                    .frame(maxWidth: .infinity).padding(.bottom, 12)
                Text("\(tab == "leaderboard" ? "The global leaderboard" : "The inbox") isn't in the Swift version yet. Coming soon.")
                    .font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(20)
            }
        }
        .onAppear {
            Feedback.announce("High Score. Total: \(s.total.formatted()) points. Rank: \(rank.label). \(shown.count) score categories active.")
        }
    }

    private func tabButton(_ id: String, _ text: String) -> some View {
        let on = tab == id
        return Button {
            Sound.sfx("sfx-select")
            tab = id
        } label: {
            Text(text).font(Theme.cinzel(10.4)).tracking(1).foregroundStyle(on ? Color(hex: 0xffdd44) : Color(hex: 0x666666))
                .frame(maxWidth: .infinity).padding(10)
                .overlay(alignment: .bottom) { Rectangle().fill(on ? Color(hex: 0xffdd44) : .clear).frame(height: 2) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
