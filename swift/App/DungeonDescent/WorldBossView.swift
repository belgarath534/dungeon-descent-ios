import SwiftUI
import DungeonCore

/// The Daily World Boss (WorldBoss.swift): today's boss, its shared HP (every
/// player's damage today, added up from the online ladder), your 10 strikes
/// and the reward when it falls.
struct WorldBossView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var day = WorldBoss.day()
    @State private var charIndex = 0
    /// Everyone's damage today; nil while loading or offline.
    @State private var shared: Int?
    @State private var loaded = false
    @State private var top: [CloudAccount.LeaderboardEntry] = []
    @State private var log: [String] = []
    @State private var dice = SystemDice()
    private let red = Color(hex: 0xff8866)

    private var signedIn: Bool { CloudAccount.shared.user != nil }
    private var mine: Int { WorldBoss.myDamage(day, store: game.store) }
    private var left: Int { WorldBoss.strikesLeft(day, store: game.store) }
    /// Signed out, your damage isn't online yet, so it's added here.
    private var total: Int? { shared.map { $0 + (signedIn ? 0 : mine) } }

    var body: some View {
        WebScreen {
            Button("← Menu") { Sound.track("menu"); router.goTo(.menu) }
                .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to main menu")
            Text("🐉 Daily World Boss").font(Theme.decorative(22)).foregroundStyle(red).accessibilityAddTraits(.isHeader)
            Text(day.boss.name).font(Theme.cinzel(15)).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
            Text(day.boss.intro).font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
            bossInfo
            if let total, WorldBoss.remaining(totalDamage: total) == 0 {
                Text("It has fallen. Everyone who struck it collects \(WorldBoss.goldReward) gold and \(WorldBoss.fragmentReward) Soul Fragments. A new boss comes at midnight UTC." as String)
                    .font(Theme.crimson(14)).foregroundStyle(Color(hex: 0x44cc88))
            } else if left > 0 {
                Text("Choose your champion").font(Theme.cinzel(12)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
                ForEach(Array(game.characters.enumerated()), id: \.offset) { i, ch in
                    Button("\(ch.name) — \(ch.cls) (Lv \(ch.persistLevel ?? 1))" as String) {
                        charIndex = i
                        Feedback.announce("\(ch.name) selected.")
                    }
                    .buttonStyle(WebButtonStyle(kind: i == charIndex ? .gold : .ghost))
                    .accessibilityAddTraits(i == charIndex ? .isSelected : [])
                }
                Button("⚔ Strike (\(left) left today)" as String) { strike() }
                    .buttonStyle(WebButtonStyle(kind: .red)).disabled(game.characters.isEmpty)
                    .accessibilityLabel("Strike \(day.boss.name). \(left) strikes left today." as String)
            } else {
                Text("You've used all \(WorldBoss.strikesPerDay) strikes today. Come back tomorrow for a new boss." as String)
                    .font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary)
            }
            if !signedIn {
                Text("Sign in (Settings → Account) so your damage counts for everyone. Signed out, it only counts on this device.")
                    .font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
            }
            if !log.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(log.prefix(10).enumerated()), id: \.offset) { _, l in
                        Text(l).font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x999999))
                    }
                }
                .accessibilityElement(children: .combine).accessibilityLabel("Strike log")
            }
            if !top.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("🏆 TODAY'S TOP DAMAGE").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(top.indices, id: \.self) { i in
                        Text("\(i + 1). \(top[i].username) — \(top[i].score.formatted())" as String)
                            .font(Theme.cinzel(11)).foregroundStyle(i == 0 ? Theme.gold : Color(hex: 0xaaaaaa))
                    }
                }
            }
        }
        .onAppear { Sound.track("boss") }
        .task { await load(announce: true) }
    }

    private var bossInfo: some View {
        let t = total ?? 0
        let hp = WorldBoss.remaining(totalDamage: t)
        return VStack(alignment: .leading, spacing: 4) {
            Text("WORLD BOSS — ALL PLAYERS").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Color(hex: 0x555555))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(hex: 0x111111))
                    Rectangle().fill(Color(hex: 0xcc4422)).frame(width: g.size.width * Double(hp) / Double(WorldBoss.hp))
                }
            }
            .frame(height: 12)
            Text(loaded ? (total == nil ? "HP can't be reached right now" : "\(hp.formatted()) / \(WorldBoss.hp.formatted()) HP") : "Loading...")
                .font(Theme.cinzel(12)).foregroundStyle(red)
            Text("Your damage today: \(mine.formatted()) · \(left) of \(WorldBoss.strikesPerDay) strikes left · \(WorldBoss.hoursLeft())h until the next boss" as String)
                .font(Theme.crimson(12)).foregroundStyle(Color(hex: 0x888888))
            Text("Kill reward: \(WorldBoss.goldReward) gold + \(WorldBoss.fragmentReward) Soul Fragments for everyone who struck" as String)
                .font(Theme.crimson(12)).foregroundStyle(Color(hex: 0x44cc88))
        }
        .padding(12).overlay(Rectangle().stroke(Color(hex: 0x4a1a1a)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WorldBoss.status(day, totalDamage: loaded ? total : 0)
                            + " Your damage today: \(mine). \(left) strikes left.")
    }

    /// The shared HP, today's top 10, and any reward owed (today's or yesterday's).
    private func load(announce: Bool) async {
        day = WorldBoss.day()
        shared = await CloudAccount.shared.worldBossDamage(day.season)
        top = await CloudAccount.shared.ladder(day.season)
        loaded = true
        if announce {
            Feedback.announce(day.boss.intro + " " + WorldBoss.status(day, totalDamage: total) + " You have \(left) strikes left today.")
        }
        collect(day, total: total)
        let y = WorldBoss.yesterday()
        if WorldBoss.myDamage(y, store: game.store) > 0, let yt = await CloudAccount.shared.worldBossDamage(y.season) {
            collect(y, total: yt)
        }
    }

    private func collect(_ d: WorldBoss.Day, total: Int?) {
        guard let total, let r = WorldBoss.claim(d, totalDamage: total, store: game.store, wallet: game.wallet) else { return }
        game.refresh()
        Sound.sfx("sfx-victory")
        Feedback.announce("\(d.boss.name) has fallen! You earn \(r.gold) gold and \(r.fragments) Soul Fragments.", after: 1)
    }

    private func strike() {
        guard game.characters.indices.contains(charIndex) else { Feedback.announce("Please select a character."); return }
        let ch = game.characters[charIndex]
        guard let s = WorldBoss.strike(day, level: ch.persistLevel ?? 1, store: game.store, dice: &dice) else {
            Feedback.announce("No strikes left today.")
            return
        }
        Sound.sfx(s.crit ? "sfx-heavy-hit" : "sfx-attack")
        game.pass(.worldBossStrike)
        let line = (s.crit ? "💥 Critical! " : "⚔ ") + "\(ch.name) deals \(s.damage) damage. \(s.taunt)"
        log.insert(line, at: 0)
        if signedIn { shared = (shared ?? 0) + s.damage }
        let hp = total.map { WorldBoss.remaining(totalDamage: $0) }
        Feedback.announce(line + (hp.map { " \($0.formatted()) HP left." } ?? "") + " \(left) strikes left.", latest: true)
        Task {
            if signedIn {
                await CloudAccount.shared.uploadLadder(score: s.myTotal, season: day.season, name: ch.name)
            }
            await load(announce: false)
        }
    }
}
