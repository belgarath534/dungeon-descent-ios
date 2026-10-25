import SwiftUI
import DungeonCore

struct MainMenuView: View {
    @EnvironmentObject var game: GameModel
    @StateObject private var webImport = WebImportFlow()
    @State private var questSummary = ""

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

            Section("Daily Quest") {
                Text(questSummary)
                    .accessibilityLabel("Daily quest: \(questSummary)")
            }

            Section {
                NavigationLink {
                    CharacterListView()
                } label: {
                    Label("Play", systemImage: "figure.walk")
                }
                NavigationLink {
                    AchievementsView()
                } label: {
                    Label("Achievements", systemImage: "trophy")
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
        .onAppear {
            Sound.track("menu")
            Sound.ambient(nil)
            questSummary = game.dailyQuests.summary
            if game.shouldOfferWebImport { webImport.check(game, quietIfEmpty: true) }
        }
        .webImportAlerts(webImport, game: game)
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
                    CharacterDetailView(id: ch.created)
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
                    game.deleteCharacter(at: i)
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
        .accessibilityHint("Opens this character.")
    }
}

struct SettingsView: View {
    @EnvironmentObject var game: GameModel
    @StateObject private var webImport = WebImportFlow()
    @AppStorage("swift_haptics") private var haptics = true
    @AppStorage("swift_class_traits") private var classTraits = true
    @AppStorage("swift_music_on") private var musicOn = true
    @AppStorage("swift_sfx_on") private var sfxOn = true
    @AppStorage("swift_ambient_on") private var ambientOn = true
    @AppStorage("swift_music_volume") private var musicVolume = 0.7
    @AppStorage("swift_sfx_volume") private var sfxVolume = 0.8
    @AppStorage("swift_ambient_volume") private var ambientVolume = 0.35

    var body: some View {
        Form {
            Section("Sound") {
                Toggle("Music", isOn: $musicOn)
                if musicOn { VolumeSlider(label: "Music volume", value: $musicVolume) }
                Toggle("Sound effects", isOn: $sfxOn)
                if sfxOn { VolumeSlider(label: "Sound effects volume", value: $sfxVolume) }
                Toggle("Ambience", isOn: $ambientOn)
                if ambientOn { VolumeSlider(label: "Ambience volume", value: $ambientVolume) }
            }
            .onChange(of: musicOn) { _ in Sound.settingsChanged() }
            .onChange(of: ambientOn) { _ in Sound.settingsChanged() }
            .onChange(of: musicVolume) { _ in Sound.settingsChanged() }
            .onChange(of: ambientVolume) { _ in Sound.settingsChanged() }
            .onChange(of: sfxVolume) { _ in Sound.sfx("sfx-select") }

            Section {
                Toggle("Haptics", isOn: $haptics)
                Toggle("Class traits", isOn: $classTraits)
            } footer: {
                Text("Class traits give Paladin, Death Knight and Sentinel their damage reduction.")
            }
            Section {
                Button(webImport.checking ? "Looking for a web version save…" : "Import save from the web version") {
                    webImport.check(game, quietIfEmpty: false)
                }
                .disabled(webImport.checking)
            } header: {
                Text("Web version save")
            } footer: {
                Text("Copies your characters, gold, items and progress from the web version of Dungeon Descent on this iPhone. It replaces what's in the Swift version.")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
                Link("Privacy Policy", destination: URL(string: "https://dungen-descent.org/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://dungen-descent.org/terms")!)
            }
        }
        .navigationTitle("Settings")
        .webImportAlerts(webImport, game: game)
    }
}

/// A volume slider VoiceOver reads as a percentage and adjusts in 10% steps.
struct VolumeSlider: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        Slider(value: $value, in: 0...1, step: 0.05) { Text(label) }
            .accessibilityLabel(label)
            .accessibilityValue("\(Int((value * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min(1, value + 0.1)
                case .decrement: value = max(0, value - 0.1)
                @unknown default: break
                }
            }
    }
}

/// Finding and importing the web version's save, with the questions it asks.
@MainActor
final class WebImportFlow: ObservableObject {
    @Published var checking = false
    @Published var found: [String: String]? = nil
    @Published var nothingFound = false
    private let importer = WebSaveImporter()

    func check(_ game: GameModel, quietIfEmpty: Bool) {
        guard !checking else { return }
        checking = true
        importer.read { [weak self] data in
            guard let self else { return }
            self.checking = false
            if GameModel.summarize(data).characters.isEmpty && data[StoreKey.globalGold] == nil {
                if quietIfEmpty { game.skipWebImport() } else { self.nothingFound = true }
            } else {
                self.found = data
            }
        }
    }

    func summary() -> String {
        guard let data = found else { return "" }
        let s = GameModel.summarize(data)
        let names = s.characters.map { "\($0.name) the \($0.race) \($0.cls)" }
        var text = names.isEmpty ? "No characters" : "\(names.count) character\(names.count == 1 ? "" : "s"): " + names.joined(separator: ", ")
        text += ". \(s.gold) gold, \(s.diamonds) diamonds."
        return text
    }
}

extension View {
    @MainActor
    func webImportAlerts(_ flow: WebImportFlow, game: GameModel) -> some View {
        self
            .alert("Import your web version save?", isPresented: Binding(
                get: { flow.found != nil },
                set: { if !$0 { flow.found = nil } }
            )) {
                Button("Import") {
                    if let data = flow.found {
                        game.importWebSave(data)
                        Feedback.announce("Save imported. \(game.characters.count) characters ready.")
                    }
                    flow.found = nil
                }
                Button("Not now", role: .cancel) {
                    game.skipWebImport()
                    flow.found = nil
                }
            } message: {
                Text("Found on this iPhone: \(flow.summary()) Importing replaces what's in the Swift version. You can do it later from Settings.")
            }
            .alert("No web version save found", isPresented: Binding(
                get: { flow.nothingFound },
                set: { flow.nothingFound = $0 }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("There's no save from the web version of Dungeon Descent on this iPhone.")
            }
    }
}
