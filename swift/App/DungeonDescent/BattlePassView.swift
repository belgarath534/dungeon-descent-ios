import SwiftUI
import DungeonCore

/// The Battle Pass (BattlePass.swift): the season, your tier and XP, this
/// week's quests and every tier's reward. Earned by playing, never bought.
struct BattlePassView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var showAll = false
    private let gold = Color(hex: 0xffdd44)

    var body: some View {
        let season = BattlePass.season()
        let p = BattlePass.load(game.store)
        let week = BattlePass.quests()
        WebScreen {
            Button("← Menu") { router.goTo(.menu) }
                .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to main menu")
            Text("🏆 Battle Pass").font(Theme.decorative(22)).foregroundStyle(gold).accessibilityAddTraits(.isHeader)
            Text("Season \(season.number) · \(season.daysLeft()) days left · earned by playing, never bought" as String)
                .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("TIER \(p.tier) OF \(BattlePass.tiers)" as String).font(Theme.cinzel(12)).tracking(2).foregroundStyle(gold)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color(hex: 0x111111))
                        Rectangle().fill(gold).frame(width: g.size.width * Double(p.xpIntoTier) / Double(BattlePass.xpPerTier))
                    }
                }
                .frame(height: 10)
                Text(p.tier >= BattlePass.tiers ? "Every tier is yours this season." : "\(p.xpIntoTier) / \(BattlePass.xpPerTier) XP to tier \(p.tier + 1)")
                    .font(Theme.cinzel(11)).foregroundStyle(Theme.textSecondary)
                if p.tier < BattlePass.tiers {
                    Text("Next: " + BattlePass.reward(tier: p.tier + 1, season: season.number).map(\.text).joined(separator: " and "))
                        .font(Theme.crimson(13)).foregroundStyle(Color(hex: 0x44cc88))
                }
            }
            .padding(12).overlay(Rectangle().stroke(Color(hex: 0x443300)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BattlePass.status(game.store) + (p.tier < BattlePass.tiers
                ? " Next reward: " + BattlePass.reward(tier: p.tier + 1, season: season.number).map(\.text).joined(separator: " and ") + "." : ""))

            Text("📜 THIS WEEK'S QUESTS").font(Theme.cinzel(11)).tracking(2).foregroundStyle(Theme.goldDim)
                .accessibilityAddTraits(.isHeader).padding(.top, 6)
            Text("+\(BattlePass.questXP) Pass XP each. New quests every Monday." as String)
                .font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
            ForEach(week.quests, id: \.id) { q in
                let done = p.questsDone.contains(q.id)
                let have = min(q.target, p.quest[q.id] ?? 0)
                HStack {
                    Text(done ? "✓" : "•").foregroundStyle(done ? Color(hex: 0x44cc88) : Theme.textDim)
                    Text(q.text).foregroundStyle(done ? Color(hex: 0x44cc88) : Theme.textSecondary)
                    Spacer()
                    Text(done ? "Done" : "\(have) / \(q.target)").foregroundStyle(Theme.textDim)
                }
                .font(Theme.crimson(14))
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(done ? "\(q.text). Done." : "\(q.text). \(have) of \(q.target).")
            }

            Text("HOW TO EARN PASS XP").font(Theme.cinzel(11)).tracking(2).foregroundStyle(Theme.goldDim)
                .accessibilityAddTraits(.isHeader).padding(.top, 6)
            Text("Enemies 5, elites 15, bosses 60 · each new floor 10 · clearing a dungeon 150 · World Boss strike 10 · Weekly Ladder run 100 · Endless Descent floor 2 · Spire floor 5 · daily quest 50.")
                .font(Theme.crimson(13)).foregroundStyle(Theme.textSecondary)

            // 12.1.2: all 50 rewards are their own page, not a list unfolding here.
            Button("🎁 Every tier's reward") { showAll = true }
                .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity).padding(.top, 6)
                .fullScreenCover(isPresented: $showAll) {
                    WebScreen {
                        Button("← Back to the Battle Pass") { showAll = false }
                            .buttonStyle(BackButtonStyle())
                            .accessibilityLabel("Back to the Battle Pass")
                        Text("🎁 Every Tier's Reward").font(Theme.decorative(17)).foregroundStyle(Theme.gold)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(1...BattlePass.tiers, id: \.self) { t in
                            let r = BattlePass.reward(tier: t, season: season.number).map(\.text).joined(separator: " and ")
                            Text("\(t <= p.paid ? "✓" : "○") Tier \(t): \(r)" as String)
                                .font(Theme.crimson(13)).foregroundStyle(t <= p.paid ? Color(hex: 0x44cc88) : Theme.textSecondary)
                                .accessibilityLabel("Tier \(t), \(t <= p.paid ? "earned" : "not yet"): \(r)" as String)
                        }
                    }
                }
        }
        .onAppear {
            let done = p.questsDone.count
            Feedback.announce("Battle Pass. " + BattlePass.status(game.store) + " \(done) of 5 weekly quests done.")
        }
    }
}
