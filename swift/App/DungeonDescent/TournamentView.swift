import SwiftUI
import DungeonCore

/// The web version's #screen-tournament, #screen-tournament-combat and
/// #screen-tournament-result.
@MainActor
struct TournamentView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var picked = 0
    @State private var fight: Tournament?
    @State private var log: [(text: String, good: Bool)] = []
    @State private var dice = SystemDice()
    @State private var board: [CloudAccount.LeaderboardEntry] = []
    @State private var finished = false

    private let season = Tournament.season()
    static let yellow = Color(hex: 0xffdd44)

    var body: some View {
        ZStack {
            WebBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let f = fight {
                        if finished { result(f) } else { combat(f) }
                    } else {
                        setup
                    }
                }
                .padding(16)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
        }
        .task { await openSetup() }
        .onDisappear { Sound.track("menu") }
    }

    // MARK: Setup

    private func openSetup() async {
        if season.active {
            Feedback.announce("Tournament active. \(season.name). \(season.hoursLeft) hours remaining.")
            board = await CloudAccount.shared.tournamentLeaderboard(season)
            if let top = board.first {
                Feedback.announce("Leaderboard loaded. Top score: \(top.score) points by \(top.username)")
            }
        } else {
            Feedback.announce("Tournament not active. Next tournament in \(season.daysUntil) days.")
        }
    }

    private var setup: some View {
        let best = Tournament.best(season, store: game.store)
        return VStack(alignment: .leading, spacing: 12) {
            Button("← Menu") { router.goTo(.menu) }
                .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x888888))
                .accessibilityLabel("Back to menu")
            Text("🏆 Tournament").font(Theme.decorative(19.2)).foregroundStyle(Self.yellow)
                .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
            Group {
                if season.active {
                    VStack(spacing: 2) {
                        Text("🏆 \(season.name) Tournament — ACTIVE").foregroundStyle(Self.yellow)
                        Text("\(season.hoursLeft) hours remaining").font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x888888))
                    }
                } else {
                    Text("Next tournament in \(season.daysUntil) days").foregroundStyle(Color(hex: 0x888888))
                }
            }
            .font(Theme.cinzel(12.8)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            VStack(spacing: 4) {
                Text(season.boss.icon).font(.system(size: 32)).accessibilityHidden(true)
                Text(season.boss.name).font(Theme.cinzel(14)).foregroundStyle(Self.yellow)
                Text(season.boss.desc).font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x888888)).multilineTextAlignment(.center)
                Text("HP: \(season.boss.hp)").font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xaaaaaa))
            }
            .padding(16).frame(maxWidth: .infinity)
            .background(Color(hex: 0x0a0a0a)).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x333333)))
            .accessibilityElement(children: .combine)

            Text("CHOOSE YOUR CHAMPION").font(Theme.cinzel(11.2)).tracking(2.2).foregroundStyle(Theme.goldDim)
            ForEach(Array(game.characters.enumerated()), id: \.element.created) { i, ch in
                Button {
                    picked = i
                    Sound.sfx("sfx-select")
                    Feedback.announce("\(ch.name) selected.")
                } label: {
                    Text("\(ch.name) — \(ch.cls) (Lv \(ch.persistLevel ?? 1))")
                        .font(Theme.cinzel(12)).foregroundStyle(picked == i ? Theme.gold : Theme.ashLight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .background(picked == i ? Color(hex: 0x1a1400) : Theme.bgPanel)
                        .overlay(Rectangle().stroke(picked == i ? Theme.gold : Theme.borderDim))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ch.name), \(ch.cls), Level \(ch.persistLevel ?? 1)")
                .accessibilityAddTraits(picked == i ? [.isButton, .isSelected] : .isButton)
            }
            Button(action: start) {
                Text("🏆 Enter Tournament").font(Theme.cinzel(12.8)).foregroundStyle(Self.yellow)
                    .frame(maxWidth: .infinity).padding(14)
                    .background(Color(hex: 0x1a1400)).overlay(Rectangle().stroke(Self.yellow))
            }
            .buttonStyle(.plain)
            .disabled(!season.active || game.characters.isEmpty)
            .opacity(season.active ? 1 : 0.4)
            .accessibilityLabel("Enter the tournament")

            if !board.isEmpty {
                Text("TOP SCORES THIS SEASON").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Color(hex: 0x888888))
                    .padding(.top, 8)
                ForEach(Array(board.enumerated()), id: \.element.id) { i, s in
                    HStack {
                        Text("\(i == 0 ? "🥇" : i == 1 ? "🥈" : i == 2 ? "🥉" : "#\(i + 1)") \(s.username)")
                            .foregroundStyle(Color(hex: i < 3 ? [0xffdd44, 0xaaaaaa, 0xcc8844][i] : 0x666666))
                        Spacer()
                        Text("\(s.score) pts").foregroundStyle(Self.yellow)
                    }
                    .font(Theme.cinzel(11.2)).padding(.vertical, 4)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x1a1a1a)).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            } else if best > 0 {
                Text("Your best this season: \(best) pts").font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x888888))
            }
        }
    }

    /// startTournament
    private func start() {
        guard season.active else { Feedback.announce("The tournament is not currently active."); return }
        guard game.characters.indices.contains(picked) else { Feedback.announce("Please select a character first."); return }
        let f = Tournament(character: game.characters[picked], boss: season.boss)
        fight = f
        finished = false
        log = []
        Sound.track("boss")
        Feedback.announce("Tournament fight begins! Face \(f.boss.name). HP: \(f.boss.hp). Deal as much damage as possible. Your damage score is what counts.")
    }

    // MARK: Combat

    private func bar(_ fraction: Double, _ colors: [UInt32], height: CGFloat) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Color(hex: 0x111111)
                LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * CGFloat(max(0, min(1, fraction))))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x333333)))
        .accessibilityHidden(true)
    }

    private func combat(_ f: Tournament) -> some View {
        VStack(spacing: 8) {
            Text(f.phase == 1 ? "PHASE 1" : f.phase == 2 ? "PHASE 2" : "FINAL PHASE")
                .font(Theme.cinzel(9.6)).tracking(3).foregroundStyle(Self.yellow)
            Text("\(f.boss.icon) \(f.boss.name)").font(Theme.decorative(16)).foregroundStyle(Self.yellow)
                .accessibilityAddTraits(.isHeader)
            Text("\(f.bossHp) / \(f.boss.hp) HP").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0x888888))
            bar(Double(f.bossHp) / Double(f.boss.hp), [0x885500, 0xffdd44], height: 10)
            Text("Damage: \(f.damageDealt)").font(Theme.cinzel(12.8)).foregroundStyle(Self.yellow)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, l in
                        Text(l.text).foregroundStyle(Color(hex: l.good ? 0xa0e0ff : 0xff8888))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(Theme.crimson(12))
                .padding(8)
            }
            .frame(minHeight: 80, maxHeight: 140)
            .background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x1a1a1a)))
            .accessibilityLabel("Tournament log")
            Text("\(f.hp) / \(f.maxHp) HP").font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xaaaaaa))
                .frame(maxWidth: .infinity, alignment: .trailing)
            bar(Double(f.hp) / Double(f.maxHp), [0x228822, 0x44ff44], height: 8)
            HStack(spacing: 8) {
                actionButton("⚔ Attack", "Attack", .attack)
                actionButton("💥 Heavy", "Heavy strike", .heavy)
                actionButton("🛡 Defend", "Defend", .defend)
            }
            .padding(.top, 4)
        }
        .accessibilityElement(children: .contain)
    }

    private func actionButton(_ title: String, _ label: String, _ a: Tournament.Action) -> some View {
        Button { act(a) } label: { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(MenuButtonStyle())
            .accessibilityLabel(label)
    }

    /// tnAttack
    private func act(_ a: Tournament.Action) {
        guard var f = fight, !f.done else { return }
        var d = dice
        let t = f.act(a, dice: &d)
        dice = d
        log.insert(contentsOf: t.log.reversed(), at: 0)
        Sound.sfx(a == .heavy ? "sfx-heavy-hit" : a == .defend ? "sfx-select" : "sfx-attack")
        fight = f
        Feedback.announce(t.spoken.joined(separator: " "))
        if f.done { end(f) }
    }

    /// tnVictory / tnDeath: the best score this season is kept and uploaded.
    private func end(_ f: Tournament) {
        finished = true
        Sound.track("menu")
        if Tournament.record(f.score, season: season, store: game.store) {
            Task { await CloudAccount.shared.uploadTournament(score: f.score, season: season) }
        }
        if f.won {
            game.addMysteryCoins(5)
            game.achievements.increment("tournamentWins")
            game.achievements.check()
            Feedback.announce("Victory! Total score: \(f.score) points. Damage: \(f.damageDealt). Speed bonus: \(f.speedBonus). Survival bonus: \(f.survivalBonus). Score uploaded to leaderboard.")
        } else {
            Feedback.announce("Defeated. Your damage score of \(f.score) points has been recorded. Try again to improve your score.")
        }
    }

    // MARK: Result

    private func result(_ f: Tournament) -> some View {
        VStack(spacing: 8) {
            Text("🏆").font(.system(size: 32)).accessibilityHidden(true)
            Text(f.won ? "👑 Boss Defeated!" : "💀 Defeated").font(Theme.decorative(17.6)).foregroundStyle(Self.yellow)
                .accessibilityAddTraits(.isHeader)
            Text("\(f.score) pts").font(Theme.cinzel(24)).foregroundStyle(Self.yellow)
            Group {
                if f.won {
                    Text("Damage: \(f.damageDealt) pts\nSpeed bonus: \(f.speedBonus) pts\nSurvival bonus: \(f.survivalBonus) pts")
                } else {
                    Text("Damage dealt: \(f.damageDealt) pts\nNo speed or survival bonus.")
                }
            }
            .font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0x888888)).multilineTextAlignment(.center).lineSpacing(6)
            Text("Your best this season: \(Tournament.best(season, store: game.store)) pts")
                .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x666666)).padding(.bottom, 16)
            Button {
                fight = nil
                finished = false
                Task { await openSetup() }
            } label: { Text("Try Again").frame(maxWidth: .infinity) }
                .buttonStyle(MenuButtonStyle(primary: true))
                .accessibilityLabel("Try again")
            Button { router.goTo(.menu) } label: { Text("← Menu").frame(maxWidth: .infinity) }
                .buttonStyle(MenuButtonStyle())
                .accessibilityLabel("Return to menu")
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
    }
}
