import SwiftUI
import DungeonCore

/// Every achievement, unlocked ones first, with how to earn the rest.
@MainActor
struct AchievementsView: View {
    @EnvironmentObject var game: GameModel

    var body: some View {
        let book = game.achievements
        let unlocked = Set(book.unlockedIDs)
        let all = AchievementBook.all
        let done = all.filter { unlocked.contains($0.id) }
        let todo = all.filter { !unlocked.contains($0.id) }
        List {
            Section {
                Text("\(done.count) of \(all.count) unlocked · \(book.trophies) trophies")
                    .font(.headline)
            }
            if !done.isEmpty {
                Section("Unlocked") {
                    ForEach(done) { a in
                        row(a, earned: true)
                    }
                }
            }
            Section("Locked") {
                ForEach(todo) { a in
                    row(a, earned: false)
                }
            }
        }
        .navigationTitle("Achievements")
    }

    private func row(_ a: Achievement, earned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(a.icon) \(a.name)").font(.headline)
                .foregroundStyle(earned ? Theme.gold : .primary)
            Text(earned ? a.desc : a.hint).font(.footnote).foregroundStyle(.secondary)
            Text("\(a.gold) gold · \(a.trophies) troph\(a.trophies == 1 ? "y" : "ies")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.name). \(earned ? "Unlocked. \(a.desc)" : "Locked. \(a.hint)") Reward: \(a.gold) gold, \(a.trophies) troph\(a.trophies == 1 ? "y" : "ies").")
    }
}
