import SwiftUI
import DungeonCore

/// "Quests & Achievements", the web version's #screen-quests: the main and
/// daily quest, every achievement, and the Daily Challenge tab.
@MainActor
struct AchievementsView: View {
    @EnvironmentObject var game: GameModel
    @State private var tab = "quests"
    @State private var visible = 30
    /// Bumped when you register or cancel, so the Challenge tab redraws.
    @State private var dcVersion = 0

    var body: some View {
        WebScreen {
            ScreenHeader(title: "Quests & Achievements")
                .padding(.bottom, 14)
            tabs
            switch tab {
            case "quests": quests
            case "achievements": achievements
            default: challenge
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
            if id == "challenge" { announceChallenge() }
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
            // Read the whole card: a label here replaced all of its text, so
            // VoiceOver only said "Main quest" or "Daily quest".
            .accessibilityElement(children: .combine)
    }

    private func badge(_ t: String, _ c: Color, _ b: Color) -> some View {
        Text(t).font(Theme.cinzel(9.6)).tracking(0.8).foregroundStyle(c)
            .padding(.vertical, 2).padding(.horizontal, 7).overlay(Rectangle().stroke(b))
    }

    // MARK: Challenge tab (renderDCPanel)

    private var challenge: some View {
        let _ = dcVersion
        let dc = DailyChallenge.today()
        let done = DailyChallenge.isCompleted(game.store)
        let reg = DailyChallenge.isRegistered(game.store)
        let status = done ? "✦ Completed" : reg ? "✓ Registered" : "Not Registered"
        let statusColor = done ? Theme.gold : reg ? Color(hex: 0x7aaa7a) : Theme.textDim
        let statusBorder = done ? Theme.goldDim : reg ? Color(hex: 0x3a6a3a) : Theme.borderDim
        let past = Array(DailyChallenge.history(game.store).suffix(5).reversed())
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today's Challenge").font(Theme.cinzel(10.4)).tracking(2.6).textCase(.uppercase).foregroundStyle(Theme.goldDim)
                Spacer()
                Text(status).font(Theme.cinzel(10.4)).tracking(1.5).foregroundStyle(statusColor)
                    .padding(.vertical, 3).padding(.horizontal, 10).overlay(Rectangle().stroke(statusBorder))
                    .accessibilityLabel("Status: \(status)")
            }
            .padding(.bottom, 12)
            Text(dc.name).font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            Text(dc.desc).font(Theme.crimson(14.4, italic: true)).foregroundStyle(Theme.textSecondary).padding(.bottom, 12)
            Text(dc.warning).font(Theme.cinzel(10.9)).foregroundStyle(Theme.bloodBright)
                .padding(.vertical, 8).padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.blood.opacity(0.06)).overlay(Rectangle().stroke(Theme.blood))
                .padding(.bottom, 16)
            Text("🪙 Reward: 1 Mystery Coin for completing a dungeon today")
                .font(Theme.cinzel(11.5)).tracking(1.2).foregroundStyle(Theme.goldDim).padding(.bottom, 4)
            if done {
                Text("✦ Challenge complete! Mystery Coin earned. Come back tomorrow.")
                    .font(Theme.cinzel(12.5)).foregroundStyle(Color(hex: 0x7aaa7a)).padding(.top, 12)
            } else if reg {
                Text("You are registered. Enter a dungeon and complete it to earn your coin.")
                    .font(Theme.cinzel(12.5).italic()).foregroundStyle(Theme.textSecondary).padding(.top, 12)
                Button("Cancel Registration") {
                    DailyChallenge.decline(game.store)
                    dcVersion += 1
                    Feedback.announce("Daily Challenge declined for today. You can still register from the Quests screen.")
                }
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Cancel registration")
                .padding(.top, 10)
            } else {
                Button("⚡ Register for Challenge") {
                    DailyChallenge.register(game.store)
                    dcVersion += 1
                    Sound.sfx("sfx-unlock")
                    Feedback.announce("Registered for today's Daily Challenge: \(dc.name). The modifier will apply when you enter a dungeon today. Complete the dungeon to earn 1 Mystery Coin.")
                }
                .buttonStyle(WebButtonStyle(kind: .gold))
                .accessibilityLabel("Register for today's Daily Challenge")
                .padding(.top, 12)
            }
            if !past.isEmpty {
                Text("Recent Challenges").font(Theme.cinzel(10.4)).tracking(2).textCase(.uppercase)
                    .foregroundStyle(Theme.goldDim).padding(.top, 20).padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(past.enumerated()), id: \.offset) { _, h in
                    HStack {
                        Text(h.name).font(Theme.cinzel(11.5)).foregroundStyle(Theme.ashLight)
                        Spacer()
                        Text(h.completed ? "✦ Coin Earned" : "Not Completed").font(Theme.cinzel(10.9))
                            .foregroundStyle(h.completed ? Color(hex: 0x7aaa7a) : Theme.textDim)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.vertical, 20).padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel)
        .overlay(Rectangle().stroke(Theme.borderDim))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.gold).frame(width: 3) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's Daily Challenge")
    }

    private func announceChallenge() {
        let dc = DailyChallenge.today()
        let text = DailyChallenge.isCompleted(game.store) ? "Daily Challenge complete. Coin earned."
            : DailyChallenge.isRegistered(game.store) ? "Registered for \(dc.name). Enter a dungeon to complete it."
            : "Today's Daily Challenge: \(dc.name). \(dc.desc) Reward: 1 Mystery Coin. Press Register to opt in."
        Feedback.announce(text, after: 0.3)
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
