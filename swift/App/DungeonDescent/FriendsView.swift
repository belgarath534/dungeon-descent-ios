import SwiftUI
import DungeonCore

/// 12.1: Friends and Rankings, with their own tab bar. Each friend is one
/// button that opens their page; co-op invites are sent from a co-op room.
struct FriendsView: View {
    @EnvironmentObject var router: Router
    @ObservedObject private var friends = Friends.shared
    @State private var tab = "friends"
    @State private var open: Friends.Friend?
    @State private var scores: [(GameCenter.Board, Int?)] = []
    @State private var confirmReport = false
    @State private var board: GameCenter.Board = .endlessFloor
    @State private var friendsOnly = true
    @State private var ranking: (me: Friends.Row?, rows: [Friends.Row])?
    @State private var rankingLoading = false
    private let teal = Color(hex: 0x66ddcc)

    var body: some View {
        ScreenTabs(items: [.init(id: "friends", title: "Friends", icon: "person.2.fill"),
                           .init(id: "rankings", title: "Rankings", icon: "trophy.fill")],
                   selection: $tab, onBack: { router.goTo(.menu) }, onSelect: { id in
                       open = nil
                       if id == "rankings" { loadRanking() }
                       Feedback.announce(id == "rankings" ? "Rankings." : "Friends.")
                   }) {
            WebScreen {
                VStack(alignment: .leading, spacing: 12) {
                    Button("← Menu") { router.goTo(.menu) }
                        .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to main menu")
                    if tab == "rankings" { rankings } else if let f = open { page(f) } else { list }
                }
            }
        }
        // Who's online and what they're doing, every 30 seconds while this is open.
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in friends.refreshOnline() }
        .onAppear {
            friends.load()
            Feedback.announce("Friends. Your Game Center friends who play Dungeon Descent.")
        }
    }

    private func header(_ s: String) -> some View {
        Text(s).font(Theme.cinzel(11)).tracking(2).foregroundStyle(Theme.goldDim).accessibilityAddTraits(.isHeader).padding(.top, 6)
    }

    private func note(_ s: String) -> some View {
        Text(s).font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
    }

    // MARK: The list

    @ViewBuilder private var list: some View {
        Text("👥 Friends").font(Theme.decorative(22)).foregroundStyle(teal).accessibilityAddTraits(.isHeader)
        switch friends.access {
        case .signedOut:
            note("Sign in to Game Center in the Settings app to see your friends. Friends are your Game Center friends who also play Dungeon Descent.")
        case .denied:
            note("Dungeon Descent isn't allowed to see your Game Center friends. Turn it on in the Settings app: Game Center, Friends List, then Dungeon Descent.")
        case .asking, .ok:
            if friends.loading && friends.friends.isEmpty {
                note("Loading your friends…")
            } else if friends.friends.isEmpty {
                note("None of your Game Center friends play Dungeon Descent yet. Add friends in the Game Center app, or share the game with them.")
            } else {
                let on = friends.online.count
                note(on == 0 ? "No friends online right now." : on == 1 ? "1 friend online." : "\(on) friends online.")
                ForEach(friends.friends) { f in
                    Button("\(f.online ? "🟢" : "⚪️") \(f.name), \(friends.seenText(f))" as String) {
                        openPage(f)
                    }
                    .buttonStyle(WebButtonStyle(kind: f.online ? .gold : .ghost)).frame(maxWidth: .infinity)
                    .accessibilityLabel("\(f.name), \(friends.seenText(f))" as String)
                    .accessibilityAddTraits(.isHeader)
                }
                Button("🔄 Refresh") { friends.load(); Feedback.announce("Refreshed.") }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
            }
            note("To play together, host a room in Co-op Dungeon and press Invite next to a friend who's online.")
            if friends.blockedCount > 0 {
                Button("Unblock Everyone (\(friends.blockedCount))" as String) { friends.unblockAll() }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
            }
        }
    }

    private func openPage(_ f: Friends.Friend) {
        open = f
        scores = []
        Feedback.announce("\(f.name), \(friends.seenText(f)).")
        Task { scores = await friends.scores(of: f) }
    }

    // MARK: A friend's page

    @ViewBuilder private func page(_ f: Friends.Friend) -> some View {
        Button("← All Friends") { open = nil }
            .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to all friends")
        Text(f.name).font(Theme.decorative(22)).foregroundStyle(teal).accessibilityAddTraits(.isHeader)
        note("Status: \(friends.seenText(f))." as String)
        header("BEST SCORES")
        if scores.isEmpty {
            note("Loading…")
        } else {
            ForEach(scores.indices, id: \.self) { i in
                Text("\(scores[i].0.title): \(scores[i].1.map(String.init) ?? "no score yet")" as String)
                    .font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary)
            }
        }
        header("PLAY TOGETHER")
        Button("🤝 Open Co-op Dungeon") { router.goTo(.coop) }
            .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
            .accessibilityHint("Host a room there, then invite them.")
        header("SAFETY")
        Button("🚫 Block") { friends.block(f); open = nil }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
            .accessibilityLabel("Block \(f.name)" as String)
            .accessibilityHint("Hides them from your list and stops their invites.")
        Button("⚠️ Report") { confirmReport = true }
            .buttonStyle(WebButtonStyle(kind: .red)).frame(maxWidth: .infinity)
            .accessibilityLabel("Report \(f.name)" as String)
            .alert("Report \(f.name)?" as String, isPresented: $confirmReport) {
                Button("Report and Block", role: .destructive) { friends.report(f); open = nil }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The developer reviews reports within 24 hours. They're also blocked for you.")
            }
    }

    // MARK: Rankings

    @ViewBuilder private var rankings: some View {
        Text("🏆 Rankings").font(Theme.decorative(22)).foregroundStyle(teal).accessibilityAddTraits(.isHeader)
        header("LEADERBOARD")
        ForEach(GameCenter.Board.allCases, id: \.self) { b in
            Button(b.title) { board = b; loadRanking() }
                .buttonStyle(WebButtonStyle(kind: b == board ? .gold : .ghost)).frame(maxWidth: .infinity)
                .accessibilityAddTraits(b == board ? .isSelected : [])
        }
        HStack {
            Button("👥 Friends") { friendsOnly = true; loadRanking() }
                .buttonStyle(WebButtonStyle(kind: friendsOnly ? .gold : .ghost))
                .accessibilityAddTraits(friendsOnly ? .isSelected : [])
            Button("🌍 World Top 10") { friendsOnly = false; loadRanking() }
                .buttonStyle(WebButtonStyle(kind: friendsOnly ? .ghost : .gold))
                .accessibilityAddTraits(friendsOnly ? [] : .isSelected)
        }
        header(board.title.uppercased())
        if friends.access == .signedOut {
            note("Sign in to Game Center in the Settings app to see the rankings.")
        } else if rankingLoading {
            note("Loading…")
        } else if let r = ranking {
            if r.rows.isEmpty { note("No scores yet. Be the first.") }
            ForEach(r.rows) { row in
                Text("\(row.rank). \(row.name)\(row.me ? " (you)" : ""): \(row.score)" as String)
                    .font(Theme.crimson(15)).foregroundStyle(row.me ? Theme.gold : Theme.textSecondary)
            }
            if let me = r.me, !r.rows.contains(where: \.me) {
                Text("You: number \(me.rank), \(me.score)" as String).font(Theme.crimson(15)).foregroundStyle(Theme.gold)
            } else if r.me == nil {
                note("You don't have a score here yet.")
            }
        } else {
            note("Couldn't load the rankings. Check your connection.")
        }
        Button("Open in Game Center") { GameCenter.show(board) }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
            .accessibilityHint("Apple's leaderboard page, with challenges.")
    }

    private func loadRanking() {
        rankingLoading = true
        let b = board, fo = friendsOnly
        Task {
            let r = await friends.ranking(b, friendsOnly: fo)
            guard b == board, fo == friendsOnly else { return }
            ranking = r
            rankingLoading = false
            if let r {
                let top = r.rows.prefix(3).map { "\($0.rank), \($0.name), \($0.score)" }.joined(separator: ". ")
                Feedback.announce("\(b.title), \(fo ? "friends" : "world top 10"). " + (r.rows.isEmpty ? "No scores yet." : top + ".")
                                  + (r.me.map { " You're number \($0.rank)." } ?? ""))
            }
        }
    }
}

/// An invite from a friend, over any screen.
struct FriendInviteAlert: ViewModifier {
    @ObservedObject private var friends = Friends.shared
    @EnvironmentObject var router: Router

    func body(content: Content) -> some View {
        content.alert("Co-op invite", isPresented: Binding(get: { friends.invite != nil }, set: { if !$0 { friends.invite = nil } })) {
            Button("Join") {
                friends.pendingJoin = friends.invite?.code
                friends.answered()
                router.goTo(.coop)
            }
            Button("Not Now", role: .cancel) { friends.answered() }
        } message: {
            Text(friends.invite.map { "\($0.from) invites you to their co-op room, \($0.code.map(String.init).joined(separator: " "))." } ?? "")
        }
    }
}
