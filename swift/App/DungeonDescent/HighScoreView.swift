import SwiftUI
import DungeonCore

/// The web version's #screen-highscore: your score, the global top 20 (with
/// upload and the weekly #1 reward) and the developer's inbox.
@MainActor
struct HighScoreView: View {
    @EnvironmentObject var game: GameModel
    @State private var tab = "score"
    @ObservedObject private var cloud = CloudAccount.shared
    @State private var uploadLabel = "☁ Upload to Leaderboard"
    @State private var uploadColor: UInt32 = 0xffdd44
    @State private var board: [CloudAccount.LeaderboardEntry]?
    @State private var boardState = ""
    @State private var messages: [CloudAccount.InboxMessage]?
    @State private var inboxState = ""

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
                Button(uploadLabel) { Task { await upload() } }
                .font(Theme.cinzel(12)).foregroundStyle(Color(hex: uploadColor))
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
            case "leaderboard":
                Text("GLOBAL TOP 20")
                    .font(Theme.cinzel(9.6)).tracking(2.9).foregroundStyle(Color(hex: 0x666666))
                    .frame(maxWidth: .infinity).padding(.bottom, 12)
                leaderboardList
            default:
                Text("MESSAGES FROM THE DEVELOPER")
                    .font(Theme.cinzel(9.6)).tracking(2.9).foregroundStyle(Color(hex: 0x666666))
                    .frame(maxWidth: .infinity).padding(.bottom, 12)
                inboxList
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
            Feedback.announce(id == "score" ? "Your score" : id == "leaderboard" ? "Global leaderboard" : "Inbox")
            if id == "leaderboard" { Task { await loadBoard() } }
            if id == "inbox" { Task { await loadInbox() } }
        } label: {
            Text(text).font(Theme.cinzel(10.4)).tracking(1).foregroundStyle(on ? Color(hex: 0xffdd44) : Color(hex: 0x666666))
                .frame(maxWidth: .infinity).padding(10)
                .overlay(alignment: .bottom) { Rectangle().fill(on ? Color(hex: 0xffdd44) : .clear).frame(height: 2) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: Leaderboard (renderLeaderboardTab)

    private func note(_ text: String, color: UInt32 = 0x555555) -> some View {
        Text(text).font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: color))
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(16)
    }

    @ViewBuilder
    private var leaderboardList: some View {
        if let list = board, !list.isEmpty {
            let me = cloud.user?.uid
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                    let mine = s.id == me
                    let medal = i == 0 ? "🥇" : i == 1 ? "🥈" : i == 2 ? "🥉" : "#\(i + 1)"
                    HStack {
                        Text("\(medal) \(s.username)\(mine ? " 👈" : "")")
                            .foregroundStyle(Color(hex: i < 3 ? [0xffdd44, 0xaaaaaa, 0xcc8844][i] : 0x666666))
                        Spacer()
                        Text("\(s.score.formatted()) pts").foregroundStyle(Color(hex: 0xffdd44))
                    }
                    .font(Theme.cinzel(12))
                    .padding(.vertical, 8).padding(.horizontal, 4)
                    .background(mine ? Color(hex: 0x0a1a0a) : .clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x1a1a1a)).frame(height: 1) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(i + 1): \(s.username) — \(s.score) points\(mine ? ", this is you" : "")")
                }
                if let me, !list.contains(where: { $0.id == me }) {
                    note("You are not on the leaderboard yet. Upload your score!")
                }
            }
        } else {
            note(boardState)
        }
    }

    private func loadBoard() async {
        board = nil
        boardState = "Loading leaderboard..."
        Feedback.announce("Loading global leaderboard.")
        guard let list = await cloud.leaderboard() else {
            boardState = "Could not load the leaderboard. Check your connection."
            Feedback.announce(boardState)
            return
        }
        board = list
        if list.isEmpty {
            boardState = "No scores yet. Be the first to upload!"
            Feedback.announce("No scores on the leaderboard yet. Be the first to upload.")
        } else if let me = cloud.user?.uid, let rank = list.firstIndex(where: { $0.id == me }) {
            Feedback.announce("Leaderboard loaded. You are ranked \(rank + 1) with \(list[rank].score.formatted()) points.")
        } else {
            Feedback.announce("Leaderboard loaded. \(list.count) players. Upload your score to appear here.")
        }
    }

    private func upload() async {
        guard cloud.signedIn else {
            uploadLabel = "Sign in required"
            uploadColor = 0xff4444
            Feedback.announce("You need to sign in to upload your score. Go to Settings then Account.")
            return
        }
        Sound.sfx("sfx-select")
        uploadLabel = "⏳ Uploading..."
        uploadColor = 0xffaa44
        let ok = await cloud.uploadScore()
        uploadLabel = ok ? "✓ Uploaded!" : "✗ Upload failed"
        uploadColor = ok ? 0x44ff88 : 0xff4444
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            uploadLabel = "☁ Upload to Leaderboard"
            uploadColor = 0xffdd44
        }
    }

    // MARK: Inbox (loadInbox)

    @ViewBuilder
    private var inboxList: some View {
        if !cloud.signedIn {
            note("Sign in to view your inbox.")
        } else if let list = messages, !list.isEmpty {
            VStack(spacing: 8) {
                ForEach(list) { m in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("✉ \(m.from)").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xffdd44))
                        if !m.message.isEmpty {
                            Text(m.message).font(Theme.crimson(13.5, italic: true)).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if m.coins > 0 {
                            if m.claimed {
                                Text("✓ \(m.coins) Mystery Coins claimed").font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x44ff88))
                            } else {
                                Button("🪙 Claim \(m.coins) Mystery Coins") {
                                    Task {
                                        if await cloud.claim(m) {
                                            Sound.sfx("sfx-unlock")
                                            await loadInbox(quiet: true)
                                        }
                                    }
                                }
                                .buttonStyle(WebButtonStyle(kind: .gold))
                                .accessibilityLabel("Claim \(m.coins) Mystery Coins from \(m.from)")
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgPanel)
                    .overlay(Rectangle().stroke(Theme.borderDim))
                    .overlay(alignment: .leading) { Rectangle().fill(m.claimed ? Theme.borderDim : Theme.gold).frame(width: 2) }
                    .accessibilityElement(children: .combine)
                }
            }
        } else {
            note(inboxState)
        }
    }

    private func loadInbox(quiet: Bool = false) async {
        guard cloud.signedIn else { return }
        if !quiet { messages = nil; inboxState = "Loading inbox..." }
        guard let list = await cloud.inbox() else {
            inboxState = "Failed to load inbox."
            Feedback.announce(inboxState)
            return
        }
        messages = list
        if list.isEmpty {
            inboxState = "Your inbox is empty."
            if !quiet { Feedback.announce("Inbox is empty.") }
        } else if !quiet {
            let unclaimed = list.filter { !$0.claimed && $0.coins > 0 }.count
            Feedback.announce("Inbox. \(list.count) message\(list.count == 1 ? "" : "s")\(unclaimed > 0 ? ", \(unclaimed) with coins to claim" : "").")
        }
    }
}
