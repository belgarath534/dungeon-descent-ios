import SwiftUI
import DungeonCore

@MainActor
struct RunView: View {
    @StateObject private var model: RunModel
    @Environment(\.dismiss) private var dismiss

    init(game: GameModel, characterIndex: Int) {
        _model = StateObject(wrappedValue: RunModel(game: game, characterIndex: characterIndex))
    }

    var body: some View {
        let run = model.run
        List {
            Section {
                StatusRow(run: run)
            }

            if let e = run.enemy {
                Section("Enemy") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(e.icon) \(e.name)\(e.isBoss ? " (Boss)" : "")").font(.headline)
                        ProgressView(value: Double(e.hp), total: Double(max(e.maxHp, 1)))
                            .tint(Theme.blood)
                        Text("\(e.hp) of \(e.maxHp) HP").font(.subheadline)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(e.name)\(e.isBoss ? ", boss" : ""). \(e.hp) of \(e.maxHp) HP.")
                }
            }

            Section("Actions") { actions }

            if run.levelPoints > 0 {
                Section("Level points: \(run.levelPoints)") {
                    ForEach(Progression.Stat.allCases, id: \.self) { stat in
                        Button {
                            model.spend(stat)
                        } label: {
                            OptionRow(title: stat.label, detail: stat.summary)
                        }
                        .accessibilityHint("Spends 1 level point.")
                    }
                }
            }

            Section("Log") {
                ForEach(model.log.prefix(40)) { line in
                    Text(line.text).font(.callout)
                }
            }
        }
        .navigationTitle(run.dungeon)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var actions: some View {
        switch model.phase {
        case .exploring:
            Button(model.bossRoomNext ? "Face the boss" : "Explore the next room") { model.enterRoom() }
        case .fighting:
            Button("Attack") { model.act(.attack) }
                .accessibilityHint("10% chance of a critical hit.")
            Button("Heavy strike") { model.act(.heavy) }
                .accessibilityHint("70% more damage, but misses 30% of the time.")
            Button("Defend") { model.act(.defend) }
                .accessibilityHint("Half damage, and blocks 4 more on the counter-attack.")
        case .floorCleared:
            Button("Descend to floor \(model.run.floor + 1)") { model.descend() }
        case .victory:
            Text("Victory! You have conquered \(model.run.dungeon).").font(.headline)
            Button("Return to characters") { dismiss() }
        case .defeat:
            Text("Defeated. All lives lost.").font(.headline)
            Button("Return to characters") { dismiss() }
        }
    }
}

struct StatusRow: View {
    let run: Run

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(run.name) · Level \(run.level)").font(.headline)
            ProgressView(value: Double(run.hp), total: Double(max(run.maxHp, 1)))
                .tint(.green)
            HStack {
                Text("HP \(run.hp)/\(run.maxHp)")
                Spacer()
                Text("Lives \(run.lives)")
                Spacer()
                Text("Floor \(run.floor)")
                Spacer()
                Text("\(run.gold)g")
            }
            .font(.subheadline)
            Text("XP \(run.xp)/\(Progression.xpNeeded(atLevel: run.level))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(run.name), level \(run.level). \(run.hp) of \(run.maxHp) HP. \(run.lives) \(run.lives == 1 ? "life" : "lives"). Floor \(run.floor), room \(run.roomsOnFloor) of \(run.floorRoomsNeeded). \(run.gold) gold. \(run.xp) of \(Progression.xpNeeded(atLevel: run.level)) XP.")
    }
}
