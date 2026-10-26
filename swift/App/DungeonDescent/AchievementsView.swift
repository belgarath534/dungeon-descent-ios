import SwiftUI
import DungeonCore

/// "Quests & Achievements", the web version's #screen-quests: the main and
/// daily quest, every achievement, and the Daily Challenge tab.
@MainActor
struct AchievementsView: View {
    @EnvironmentObject var game: GameModel
    @State private var tab = "quests"
    @State private var visible = 30

    var body: some View {
        WebScreen {
            ScreenHeader(title: "Quests & Achievements")
                .padding(.bottom, 14)
            tabs
            switch tab {
            case "quests": quests
            case "achievements": achievements
            default:
                Text("The Daily Challenge isn't in the Swift version yet. Coming soon.")
                    .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            tabButton("quests", "📜 Quests", "Quests tab")
            tabButton("achievements", "🏆 Achievements", "Achievements tab")
            tabButton("challenge", "⚡ Challenge", "Daily Challenge tab")
        }
        .overlay(Rectangle().stroke(Theme.borderDim))
        .padding(.bottom, 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quest sections")
    }

    private func tabButton(_ id: String, _ text: String, _ label: String) -> some View {
        let on = tab == id
        return Button {
            tab = id
            if id == "achievements" { announceAchievements() }
        } label: {
            Text(text).font(Theme.cinzel(11.5)).tracking(1.7).textCase(.uppercase)
                .foregroundStyle(on ? Theme.gold : Theme.textDim)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Color(hex: 0x1e1a10) : Color(hex: 0x12100d))
                .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.gold).frame(height: 2) } }
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Quests tab

    private var quests: some View {
        let dq = game.dailyQuests
        let q = dq.quest
        let done = dq.isComplete
        return VStack(spacing: 10) {
            card(border: Theme.borderGlow, label: "Main quest") {
                HStack(spacing: 8) {
                    Text("⚔ Main Quest").font(Theme.cinzel(14)).foregroundStyle(Theme.ashLight)
                    badge("MAIN", Theme.bloodBright, Theme.blood)
                }
                Text("Descend to floor 10 and defeat the dungeon boss. Applies to each dungeon run.")
                    .font(Theme.crimson(12.8, italic: true)).foregroundStyle(Theme.textSecondary)
                Text("Reward: Dungeon cleared + next dungeon unlocked.").font(Theme.cinzel(10.4)).tracking(1).foregroundStyle(Theme.ash)
            }
            card(border: done ? Color(hex: 0x4a8a4a) : Theme.goldDim, label: "Daily quest") {
                HStack(spacing: 8) {
                    Text("☀ Daily Quest").font(Theme.cinzel(14)).foregroundStyle(Theme.ashLight)
                    if done { badge("COMPLETE", Color(hex: 0x7aaa7a), Color(hex: 0x3a6a3a)) } else { badge("DAILY", Theme.gold, Theme.goldDim) }
                }
                Text(q.desc).font(Theme.crimson(12.8, italic: true)).foregroundStyle(Theme.textSecondary)
                Text("Progress: \(dq.progress) / \(q.target)\(done ? " — Done!" : "")").font(Theme.cinzel(11.2)).foregroundStyle(Theme.goldDim)
                Bar(value: Double(dq.progress) / Double(max(q.target, 1)), colors: [Theme.goldDim, Theme.goldDim],
                    track: Theme.gold.opacity(0.1), height: 4)
                Text("Reward: \(q.reward)").font(Theme.cinzel(10.4)).tracking(1).foregroundStyle(Theme.ash)
            }
        }
    }

    private func card<Content: View>(border: Color, label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(.vertical, 16).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgPanel)
            .overlay(Rectangle().stroke(Theme.borderDim))
            .overlay(alignment: .leading) { Rectangle().fill(border).frame(width: 3) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
    }

    private func badge(_ t: String, _ c: Color, _ b: Color) -> some View {
        Text(t).font(Theme.cinzel(9.6)).tracking(0.8).foregroundStyle(c)
            .padding(.vertical, 2).padding(.horizontal, 7).overlay(Rectangle().stroke(b))
    }

    // MARK: Achievements tab

    private var achievements: some View {
        let unlocked = Set(game.achievements.unlockedIDs)
        let all = AchievementBook.all
        let count = all.filter { unlocked.contains($0.id) }.count
        let pct = all.isEmpty ? 0 : Int((Double(count) / Double(all.count) * 100).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ACHIEVEMENTS — \(count) / \(all.count) UNLOCKED").font(Theme.cinzel(11.5)).foregroundStyle(Theme.goldDim)
                Bar(value: Double(pct) / 100, colors: [Theme.goldDim, Theme.goldDim], track: Theme.gold.opacity(0.1), height: 4)
                Text("\(pct)% complete").font(Theme.crimson(11.2, italic: true)).foregroundStyle(Theme.textDim)
            }
            .padding(.vertical, 12).padding(.horizontal, 16)
            .background(Theme.gold.opacity(0.06)).overlay(Rectangle().stroke(Theme.borderDim))
            .overlay(alignment: .leading) { Rectangle().fill(Theme.goldDim).frame(width: 3) }
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(all.prefix(visible)) { a in achCard(a, earned: unlocked.contains(a.id)) }
            }
            if all.count > visible {
                let left = all.count - visible
                Button("Load More (\(left) remaining)") {
                    visible += 30
                }
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Load \(min(30, left)) more achievements. \(left) remaining.")
            }
        }
    }

    private func achCard(_ a: Achievement, earned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(earned ? a.icon : "🔒").font(.system(size: 26)).padding(.bottom, 3)
            (Text(a.name) + Text(earned ? " ✓" : "").font(Theme.cinzel(9.6)).foregroundColor(Color(hex: 0x7aaa7a)))
                .font(Theme.cinzel(12.5)).foregroundStyle(earned ? Theme.ashLight : Theme.textDim)
            Text(a.desc).font(Theme.crimson(11.5, italic: true)).foregroundStyle(earned ? Theme.textSecondary : Theme.textDim)
            if !earned {
                Text("🔓 \(a.hint)").font(Theme.crimson(10, italic: true)).foregroundStyle(Color(hex: 0x888888)).padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel)
        .overlay(Rectangle().stroke(Theme.borderDim))
        .overlay(alignment: .leading) { if earned { Rectangle().fill(Theme.gold).frame(width: 3) } }
        .opacity(earned ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.name). \(a.desc)\(earned ? " Unlocked." : " Locked. To unlock: \(a.hint)")")
    }

    private func announceAchievements() {
        let unlocked = Set(game.achievements.unlockedIDs)
        let all = AchievementBook.all
        let count = all.filter { unlocked.contains($0.id) }.count
        let pct = all.isEmpty ? 0 : Int((Double(count) / Double(all.count) * 100).rounded())
        Feedback.announce("Achievements. \(count) of \(all.count) unlocked. \(pct) percent complete.\(all.count > visible ? " Showing first \(visible)." : "")")
    }
}
