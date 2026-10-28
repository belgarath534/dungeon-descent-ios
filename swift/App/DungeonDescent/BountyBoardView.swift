import SwiftUI
import DungeonCore

/// #screen-bounty: today's three bounties, one active at a time.
struct BountyBoardView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var today: [Bounties.Bounty] = []
    @State private var active: Bounties.Bounty?
    @State private var progress = 0
    @State private var refreshes = Bounties.refreshesPerDay
    @State private var dice = SystemDice()

    var body: some View {
        WebScreen {
            VStack(alignment: .leading, spacing: 12) {
                Button("← Menu") { router.goTo(.menu) }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to main menu")
                Text("The Bounty Board").font(Theme.decorative(22)).foregroundStyle(Color(hex: 0xe0c080)).accessibilityAddTraits(.isHeader)
                Text("\(refreshes) refreshes remaining today").font(Theme.cinzel(10.4)).tracking(1.5)
                    .foregroundStyle(Color(hex: 0x555555)).frame(maxWidth: .infinity)
                if let a = active {
                    Text("📋 Active: \(a.title) — \(progress) / \(a.count) \(a.progressLabel)")
                        .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x44ff88))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0x0a1a0a)).overlay(Rectangle().stroke(Color(hex: 0x44aa44)))
                }
                if today.isEmpty {
                    Text("No bounties available. Refresh to generate new ones.").font(Theme.cinzel(11))
                        .foregroundStyle(Color(hex: 0x555555)).frame(maxWidth: .infinity).padding(20)
                }
                ForEach(today) { b in card(b) }
                Button("🔄 Refresh Bounties") { refresh() }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                    .disabled(refreshes <= 0).opacity(refreshes <= 0 ? 0.4 : 1)
                    .accessibilityLabel("Refresh bounties. \(refreshes) refreshes remaining today.")
                Text("Completing a bounty rewards gold and trophies. Only one active bounty at a time.")
                    .font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x333333)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Divider().background(Color(hex: 0x1a1a1a))
                Button("🌲 Enter The Hunting Grounds") { router.goTo(.hunting) }
                .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                .accessibilityLabel("Enter the Hunting Grounds — send your character on an AFK forest hunt")
            }
        }
        .onAppear {
            load()
            Feedback.announce("Bounty Board. \(today.count) bounties available. " + (active.map { "Active bounty: \($0.title)." } ?? "No active bounty.") + " \(refreshes) refreshes remaining.")
        }
    }

    private func card(_ b: Bounties.Bounty) -> some View {
        let isActive = active?.id == b.id
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(b.icon) \(b.title)" + (isActive ? "  ● ACTIVE" : "")).font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xe0c080))
                Text(b.desc).font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary)
                Text("📍 \(b.dungeon)").font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x888888))
                Text("Reward: \(b.gold)g + \(b.trophies) 🏆").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xffdd44))
                if isActive {
                    Text("Progress: \(progress) / \(b.count) \(b.progressLabel)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x44ff88))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(b.title). \(b.desc) \(b.dungeon). Reward: \(b.gold) gold and \(b.trophies) \(b.trophies == 1 ? "trophy" : "trophies")."
                                + (isActive ? " Active. Progress \(progress) of \(b.count) \(b.progressLabel)." : ""))
            if isActive {
                Button("Abandon Bounty") { abandon() }
                    .buttonStyle(WebButtonStyle(kind: .red)).accessibilityLabel("Abandon \(b.title)")
            } else if active == nil {
                Button("📋 Register") { register(b) }
                    .buttonStyle(WebButtonStyle(kind: .gold)).accessibilityLabel("Register for \(b.title)")
            }
        }
        .padding(12)
        .background(isActive ? Color(hex: 0x0a1a0a) : Color(hex: 0x0a0800))
        .overlay(Rectangle().stroke(isActive ? Color(hex: 0x44aa44) : Color(hex: 0x2a2010)))
    }

    private func load() {
        var d = dice
        today = Bounties.today(game.store, dice: &d)
        dice = d
        active = Bounties.active(game.store)
        progress = Bounties.progress(game.store)
        refreshes = Bounties.refreshesLeft(game.store)
    }

    private func register(_ b: Bounties.Bounty) {
        guard Bounties.register(b.id, store: game.store) != nil else { return }
        Sound.sfx("sfx-select")
        load()
        Feedback.announce("Bounty registered. \(b.title). \(b.desc) Good luck.")
    }

    private func abandon() {
        Bounties.abandon(game.store)
        Sound.sfx("sfx-select")
        load()
        Feedback.announce("Bounty abandoned. You can register for a new one.")
    }

    private func refresh() {
        var d = dice
        let ok = Bounties.refresh(game.store, dice: &d)
        dice = d
        guard ok else { Feedback.announce("No refreshes remaining today. Come back tomorrow."); return }
        Sound.sfx("sfx-select")
        load()
        Feedback.announce("Bounties refreshed. \(refreshes) refreshes remaining today. " + today.map(\.title).joined(separator: ", ") + ".")
    }
}
