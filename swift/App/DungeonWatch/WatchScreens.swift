import SwiftUI
import WatchKit

/// 12.0 home: every part of the watch app, one tap away.
struct HomeView: View {
    @EnvironmentObject var store: WatchStore

    var body: some View {
        List {
            if let a = store.lastAlert {
                Text(a).font(.footnote).foregroundStyle(.orange)
                    .accessibilityLabel("Latest alert: \(a)")
            }
            NavigationLink { EndlessView() } label: {
                row("🏃", "Endless Descent", endlessLine)
            }
            NavigationLink { BossView() } label: {
                row("🐉", "World Boss", store.boss.map { "\($0.strikesLeft) of \($0.strikesPerDay) strikes left" } ?? "Today's shared boss")
            }
            NavigationLink { PassView() } label: {
                row("🏆", "Battle Pass", store.pass.map { "Tier \($0.tier) of \($0.tiers)" } ?? "Season and weekly quests")
            }
            NavigationLink { DailyView() } label: {
                row("🎁", "Daily Reward", store.daily.map { $0.claimed ? "Claimed · \($0.streak)-day streak" : "Ready to claim!" } ?? "Keep your streak")
            }
            NavigationLink { QuickFightView() } label: {
                row("⚔", "Quick Fight", "A fight on your wrist")
            }
            Toggle(isOn: $store.alertsOn) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Wrist Alerts")
                    Text("Low HP, elites, the hunter, your co-op turn").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityHint("Taps your wrist while you play on your iPhone, with this app open.")
            StatusLine()
        }
        .navigationTitle("Descent")
        .task {
            // Keep everything current while the app is open.
            while !Task.isCancelled {
                store.refresh()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private var endlessLine: String {
        guard let r = store.run else { return "Start a run that plays itself" }
        return r.running ? "\(r.charName) · floor \(r.floor) · HP \(r.hp)/\(r.maxHp)" : "\(r.charName) reached floor \(r.floor)"
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(icon) \(title)").font(.headline)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
    }
}

/// Needs the iPhone app's 12.0 for this screen.
private struct NeedsPhone: View {
    var body: some View {
        Text("Open Dungeon Descent on your iPhone (version 12.0 or newer) to connect.").font(.footnote)
    }
}

// MARK: World Boss

struct BossView: View {
    @EnvironmentObject var store: WatchStore
    @State private var pick = 0

    var body: some View {
        List {
            if let b = store.boss {
                Section {
                    Text(b.name).font(.headline).foregroundStyle(gold).accessibilityAddTraits(.isHeader)
                    if let hp = b.hpLeft {
                        ProgressView(value: Double(hp), total: Double(max(1, b.maxHp))) {
                            Text(hp == 0 ? "Fallen!" : "\(hp) HP left").font(.footnote)
                        }
                        .tint(.red)
                        .accessibilityLabel(hp == 0 ? "The boss has fallen" : "Shared HP")
                        .accessibilityValue(hp == 0 ? "" : "\(hp) of \(b.maxHp)")
                    }
                    Text("Your damage today: \(b.myDamage)").font(.footnote)
                    Text("\(b.strikesLeft) of \(b.strikesPerDay) strikes left · \(b.hoursLeft)h until the next boss").font(.footnote).foregroundStyle(.secondary)
                }
                if store.characters.isEmpty {
                    Text("Create a character on your iPhone first.").font(.footnote)
                } else {
                    Section("Strike with") {
                        Picker("Character", selection: $pick) {
                            ForEach(store.characters) { c in Text("\(c.name), Lv \(c.level)").tag(c.index) }
                        }
                        Button {
                            if let c = store.characters.first(where: { $0.index == pick }) ?? store.characters.first {
                                WKInterfaceDevice.current().play(.click)
                                store.strike(c)
                            }
                        } label: {
                            Label("Strike!", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                        }
                        .tint(.red)
                        .disabled(b.strikesLeft == 0 || store.busy)
                        .accessibilityLabel("Strike the boss. \(b.strikesLeft) strikes left.")
                    }
                }
                StatusLine()
            } else {
                NeedsPhone()
            }
        }
        .navigationTitle("World Boss")
        .onAppear { pick = store.characters.first?.index ?? 0; store.refresh() }
    }
}

// MARK: Battle Pass

struct PassView: View {
    @EnvironmentObject var store: WatchStore

    var body: some View {
        List {
            if let p = store.pass {
                Section {
                    Text("Season \(p.season) · Tier \(p.tier) of \(p.tiers)").font(.headline).foregroundStyle(gold)
                        .accessibilityAddTraits(.isHeader)
                    ProgressView(value: Double(p.xpIntoTier), total: Double(max(1, p.xpPerTier))) {
                        Text(p.tier >= p.tiers ? "Every tier is yours!" : "\(p.xpIntoTier) / \(p.xpPerTier) XP").font(.footnote)
                    }
                    .tint(gold)
                    .accessibilityLabel("Progress to tier \(p.tier + 1)")
                    .accessibilityValue("\(p.xpIntoTier) of \(p.xpPerTier) XP")
                    if !p.next.isEmpty { Text("Next: \(p.next)").font(.footnote).foregroundStyle(.green) }
                    Text("\(p.daysLeft) days left in the season").font(.footnote).foregroundStyle(.secondary)
                }
                Section("This week's quests") {
                    ForEach(Array(p.quests.enumerated()), id: \.offset) { _, q in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(q.done ? "✓" : "•") \(q.text)").font(.footnote)
                            Text(q.done ? "Done" : "\(q.have) / \(q.target)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(q.done ? "\(q.text). Done." : "\(q.text). \(q.have) of \(q.target).")
                    }
                }
            } else {
                NeedsPhone()
            }
        }
        .navigationTitle("Battle Pass")
        .onAppear { store.refresh() }
    }
}

// MARK: Daily reward

struct DailyView: View {
    @EnvironmentObject var store: WatchStore

    var body: some View {
        List {
            if let d = store.daily {
                Text(d.claimed ? "Claimed today" : "Your reward is ready!").font(.headline).foregroundStyle(gold)
                    .accessibilityAddTraits(.isHeader)
                Text("Streak: \(d.streak) day\(d.streak == 1 ? "" : "s")").font(.footnote)
                Text(d.claimed ? "Tomorrow — \(d.next)" : d.next).font(.footnote).foregroundStyle(.secondary)
                if !d.claimed {
                    Button {
                        store.claimDaily()
                    } label: {
                        Label("Claim", systemImage: "gift.fill").frame(maxWidth: .infinity)
                    }
                    .tint(gold)
                    .disabled(store.busy)
                    .accessibilityLabel("Claim your daily reward")
                }
                StatusLine()
            } else {
                NeedsPhone()
            }
        }
        .navigationTitle("Daily")
        .onAppear { store.refresh() }
    }
}
