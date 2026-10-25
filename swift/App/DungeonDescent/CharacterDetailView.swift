import SwiftUI
import DungeonCore

/// One character: continue a saved run or start a new one, and see past deaths.
@MainActor
struct CharacterDetailView: View {
    @EnvironmentObject var game: GameModel
    /// The character's creation time, which identifies it even if others are deleted.
    let id: Double
    private var index: Int { game.characters.firstIndex { $0.created == id } ?? -1 }
    @State private var confirmingNewRun = false
    @State private var running: Bool? = nil   // nil: not playing; true: resumed; false: new run

    var body: some View {
        if game.characters.indices.contains(index) {
            content(game.characters[index])
        } else {
            Text("This character no longer exists.")
        }
    }

    @ViewBuilder
    private func content(_ ch: PlayerCharacter) -> some View {
        let saved = game.savedRun(for: index)
        List {
            Section {
                CharacterRow(ch: ch)
                let info = GameData.classInfo(ch.cls)
                Text("\(info.maxHp) HP · attack \(info.atk.lowerBound)–\(info.atk.upperBound) · defense \(info.def) · \(ch.difficultyLevel.summary)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let s = saved {
                    Button("Continue run: floor \(s.floor), \(s.hp) of \(s.maxHp) HP") { running = true }
                    Button("Start a new run", role: .destructive) { confirmingNewRun = true }
                } else {
                    Button(ch.floor > 1 ? "Descend from floor \(ch.floor)" : "Descend into \(ch.dungeon)") { running = false }
                }
            }

            let deaths = deathLog(ch)
            if !deaths.isEmpty {
                Section("Death log") {
                    ForEach(Array(deaths.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.callout)
                    }
                }
            }
        }
        .navigationTitle(ch.name)
        .navigationDestination(isPresented: Binding(get: { running != nil }, set: { if !$0 { running = nil } })) {
            RunView(game: game, characterIndex: index, resume: running ?? false)
        }
        .alert("Abandon your saved run?", isPresented: $confirmingNewRun) {
            Button("Start new run", role: .destructive) {
                game.clearRun(for: index)
                running = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current run will be lost.")
        }
    }

    private func deathLog(_ ch: PlayerCharacter) -> [String] {
        guard case .array(let entries)? = ch.extra["deathLog"] else { return [] }
        return entries.prefix(10).compactMap { e in
            guard case .object(let o) = e else { return nil }
            var floor = ""
            if case .number(let f)? = o["floor"] { floor = "Floor \(Int(f))" }
            var by = ""
            if case .string(let k)? = o["killedBy"] { by = " — \(k)" }
            var date = ""
            if case .string(let d)? = o["date"] { date = " (\(d))" }
            return floor + by + date
        }
    }
}
