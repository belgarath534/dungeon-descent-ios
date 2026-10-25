import SwiftUI
import DungeonCore

/// Character creation, in the web version's order: class, race, profession,
/// name, dungeon, difficulty. Spirits, corruption, hunter mode, guide and
/// backstory steps come later.
@MainActor
struct CreateCharacterView: View {
    @EnvironmentObject var game: GameModel
    @Environment(\.dismiss) private var dismiss

    @State private var cls = GameData.classes[0].id
    @State private var race = GameData.races[0].id
    @State private var prof = GameData.professions[0].id
    @State private var name = ""
    @State private var dungeon = GameData.dungeons[0]
    @State private var difficulty = GameData.Difficulty.wanderer
    @State private var dungeons: [String] = [GameData.dungeons[0]]
    @State private var hardcore = false

    private var nameOK: Bool { PlayerCharacter.isValidName(name) }

    var body: some View {
        Form {
            Section("Class") {
                Picker("Class", selection: $cls) {
                    ForEach(GameData.classes, id: \.id) { c in
                        OptionRow(title: c.id,
                                  detail: [c.tagline, "\(c.maxHp) HP · \(c.atk.lowerBound)–\(c.atk.upperBound) attack · \(c.def) defense"]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                            .tag(c.id)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("Race") {
                Picker("Race", selection: $race) {
                    ForEach(GameData.races, id: \.id) { r in
                        OptionRow(title: r.id, detail: r.desc).tag(r.id)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("Profession") {
                Picker("Profession", selection: $prof) {
                    ForEach(GameData.professions, id: \.id) { p in
                        OptionRow(title: p.id, detail: p.desc).tag(p.id)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section {
                TextField("Character name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            } header: {
                Text("Name")
            } footer: {
                Text("Name must be between 2 and 24 characters.")
            }

            Section("Dungeon") {
                Picker("Dungeon", selection: $dungeon) {
                    ForEach(dungeons, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.navigationLink)
                let locked = GameData.dungeons.count - dungeons.count
                if locked > 0 {
                    Text("\(locked) more \(locked == 1 ? "dungeon unlocks" : "dungeons unlock") as you complete the ones before.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Difficulty") {
                Picker("Difficulty", selection: $difficulty) {
                    ForEach(GameData.Difficulty.allCases, id: \.self) { d in
                        OptionRow(title: d.rawValue, detail: d.summary).tag(d)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section {
                Toggle("Hardcore Mode", isOn: $hardcore)
            } footer: {
                Text("One death and this character is gone forever, no matter how many lives the difficulty gives.")
            }

            Section {
                Button("Create \(nameOK ? name.trimmingCharacters(in: .whitespaces) : "Character")") {
                    create()
                }
                .disabled(!nameOK)
            } footer: {
                Text("\(race) \(cls), \(prof). \(dungeon), \(difficulty.rawValue): \(difficulty.summary).")
            }
        }
        .navigationTitle("New Character")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear { dungeons = game.unlockedDungeons() }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let ch = PlayerCharacter(name: trimmed, cls: cls, race: race, prof: prof,
                                 dungeon: dungeon, difficulty: difficulty, hardcoreMode: hardcore)
        if game.create(ch) {
            Feedback.announce("\(trimmed) created. Returning to character list.")
            dismiss()
        }
    }
}

struct OptionRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if !detail.isEmpty {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
