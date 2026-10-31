import SwiftUI

@main
struct DungeonWatchApp: App {
    @StateObject private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack { HomeView() }
                .environmentObject(store)
        }
    }
}

private let gold = Color(red: 0.79, green: 0.64, blue: 0.15)

/// The run going now, the one that just ended, or the character list.
struct HomeView: View {
    @EnvironmentObject var store: WatchStore
    /// The ended run's summary was closed.
    @State private var dismissedEnd: Double = 0

    var body: some View {
        Group {
            if let r = store.run, r.running {
                RunView(run: r)
            } else if let r = store.run, !r.running, r.startedAt != dismissedEnd {
                SummaryView(run: r) { dismissedEnd = r.startedAt }
            } else {
                CharacterListView()
            }
        }
        .navigationTitle("Descent")
        .task {
            // Keep the run current while the app is open.
            while !Task.isCancelled {
                store.refresh()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }
}

struct StatusLine: View {
    @EnvironmentObject var store: WatchStore
    var body: some View {
        if let m = store.message {
            Text(m).font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Pick a character

struct CharacterListView: View {
    @EnvironmentObject var store: WatchStore

    var body: some View {
        List {
            Section {
                Text("Endless Descent").font(.headline).foregroundStyle(gold)
                    .accessibilityAddTraits(.isHeader)
                if let s = store.snapshot {
                    Text("\(s.totalPoints) points · best floor \(s.bestFloor)").font(.footnote)
                }
                StatusLine()
            }
            if store.characters.isEmpty {
                Text(store.snapshot == nil
                     ? "Open Dungeon Descent on your iPhone to connect."
                     : "No characters yet. Create one on your iPhone.")
                    .font(.footnote)
            } else {
                Section("Choose a character") {
                    ForEach(store.characters) { c in
                        NavigationLink {
                            StartView(character: c)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.headline)
                                Text("Level \(c.level) \(c.cls)").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("\(c.name), level \(c.level) \(c.cls)")
                        .accessibilityHint("Opens the start screen for this character.")
                    }
                }
            }
            Button("Refresh") { store.refresh() }.disabled(store.busy)
        }
    }
}

struct StartView: View {
    @EnvironmentObject var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    let character: WatchLink.Character

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(character.name).font(.title3).foregroundStyle(gold).accessibilityAddTraits(.isHeader)
                Text("Level \(character.level) \(character.cls)").font(.footnote)
                Text("Your character fights on their own, one fight every 15 seconds, and goes deeper until they fall or you end the run.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    store.start(character)
                    dismiss()
                } label: {
                    Label("Start Run", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .tint(gold)
                .disabled(store.busy)
                .accessibilityLabel("Start Endless Descent with \(character.name)")
                StatusLine()
            }
        }
        .navigationTitle("Start")
    }
}

// MARK: A run going

struct RunView: View {
    @EnvironmentObject var store: WatchStore
    let run: WatchLink.Run
    @State private var confirmEnd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(run.charName)").font(.headline).foregroundStyle(gold).accessibilityAddTraits(.isHeader)
                HStack {
                    Text("Floor \(run.floor)").font(.title3.bold())
                    Spacer()
                    Text("Lv \(run.level)").font(.footnote)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Floor \(run.floor), level \(run.level)")

                ProgressView(value: Double(max(0, run.hp)), total: Double(max(1, run.maxHp))) {
                    Text("HP \(run.hp) / \(run.maxHp)").font(.footnote)
                }
                .tint(run.hp * 3 < run.maxHp ? .red : .green)
                .accessibilityLabel("Health")
                .accessibilityValue("\(run.hp) of \(run.maxHp)")

                Text("\(run.points) points · \(run.enemiesDefeated) defeated").font(.footnote)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int(run.nextFightAt - ctx.date.timeIntervalSince1970))
                    Text(left > 0 ? "Next fight in \(left)s" : "Fighting…").font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)

                Button {
                    store.potion()
                } label: {
                    Label("Potion (\(run.potions))", systemImage: "cross.vial.fill").frame(maxWidth: .infinity)
                }
                .disabled(run.potions <= 0 || store.busy)
                .accessibilityLabel("Use a potion. \(run.potions) left.")

                Button(role: .destructive) { confirmEnd = true } label: {
                    Label("End Run", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .disabled(store.busy)

                StatusLine()

                if !run.log.isEmpty {
                    Text("Latest").font(.footnote.bold()).padding(.top, 4).accessibilityAddTraits(.isHeader)
                    ForEach(Array(run.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .confirmationDialog("End this run?", isPresented: $confirmEnd) {
            Button("End Run", role: .destructive) { store.end() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Your points and levels are saved.")
        }
    }
}

// MARK: A run that ended

struct SummaryView: View {
    @EnvironmentObject var store: WatchStore
    let run: WatchLink.Run
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(run.hp <= 0 ? "\(run.charName) fell" : "Run ended")
                    .font(.headline).foregroundStyle(gold).accessibilityAddTraits(.isHeader)
                Text("Floor \(run.floor) reached").font(.title3.bold())
                Text("Level \(run.level) · \(run.points) points").font(.footnote)
                Text("\(run.enemiesDefeated) defeated · \(run.bossesDefeated) bosses").font(.footnote)
                StatusLine()
                Button("New Run", action: close).tint(gold).padding(.top, 4)
            }
        }
    }
}
