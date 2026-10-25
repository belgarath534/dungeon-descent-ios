import SwiftUI
import DungeonCore

struct MainMenuView: View {
    @EnvironmentObject var game: GameModel

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text("Dungeon Descent")
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                        .foregroundStyle(Theme.gold)
                        .accessibilityAddTraits(.isHeader)
                    Text("Swift preview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)

                HStack {
                    Label("\(game.gold) gold", systemImage: "circle.fill")
                    Spacer()
                    Label("\(game.diamonds) diamonds", systemImage: "diamond.fill")
                }
                .font(.headline)
                .accessibilityElement(children: .combine)
            }

            Section {
                NavigationLink {
                    CharacterListView()
                } label: {
                    Label("Play", systemImage: "figure.walk")
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Link(destination: URL(string: "https://dungen-descent.org/support")!) {
                    Label("Support", systemImage: "questionmark.circle")
                }
                .accessibilityHint("Get help, report a bug, or contact us. Opens in Safari.")
            }
        }
        .navigationTitle("Main Menu")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CharacterListView: View {
    @EnvironmentObject var game: GameModel
    @State private var creating = false
    @State private var pendingDelete: Int?

    var body: some View {
        List {
            if game.characters.isEmpty {
                Text("No characters yet. Create one to begin your descent.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(game.characters.enumerated()), id: \.offset) { index, ch in
                NavigationLink {
                    RunView(game: game, characterIndex: index)
                } label: {
                    CharacterRow(ch: ch)
                }
                .accessibilityAction(named: "Delete") { pendingDelete = index }
            }
            .onDelete { offsets in pendingDelete = offsets.first }

            Section {
                Button {
                    creating = true
                } label: {
                    Label("New Character", systemImage: "plus")
                }
                .disabled(game.isRosterFull)
                if game.isRosterFull {
                    Text("All \(GameData.maxCharacters) character slots are used. Delete one to make room.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Characters")
        .sheet(isPresented: $creating) {
            NavigationStack { CreateCharacterView() }
                .environmentObject(game)
        }
        .alert("Delete character?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let i = pendingDelete {
                    let name = game.characters.indices.contains(i) ? game.characters[i].name : ""
                    game.delete(at: i)
                    Feedback.announce("\(name) deleted.")
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
    }
}

struct CharacterRow: View {
    let ch: PlayerCharacter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ch.name).font(.headline)
            Text("\(ch.race) \(ch.cls) · \(ch.prof)")
                .font(.subheadline)
            Text("\(ch.dungeon) · Floor \(max(ch.floor, 1)) · \(ch.difficulty)\(ch.completed ? " · Completed" : "")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ch.name), the \(ch.race) \(ch.cls), \(ch.prof). \(ch.dungeon), floor \(max(ch.floor, 1)), \(ch.difficulty) difficulty.\(ch.completed ? " Completed." : "")")
        .accessibilityHint("Starts a run with this character.")
    }
}

struct SettingsView: View {
    @AppStorage("swift_haptics") private var haptics = true
    @AppStorage("swift_class_traits") private var classTraits = true

    var body: some View {
        Form {
            Section {
                Toggle("Haptics", isOn: $haptics)
                Toggle("Class traits", isOn: $classTraits)
            } footer: {
                Text("Class traits give Paladin, Death Knight and Sentinel their damage reduction.")
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
                Link("Privacy Policy", destination: URL(string: "https://dungen-descent.org/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://dungen-descent.org/terms")!)
            }
        }
        .navigationTitle("Settings")
    }
}
