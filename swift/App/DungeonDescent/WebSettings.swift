import SwiftUI
import UIKit
import DungeonCore

/// The web version's #settings-screen: a list of categories, each opening
/// its own panel. Audio, Accessibility, Gameplay and General work; the rest
/// say they're coming.
@MainActor
struct WebSettingsView: View {
    @EnvironmentObject var game: GameModel
    @StateObject private var webImport = WebImportFlow()
    let close: () -> Void
    @State private var panel: String?

    @AppStorage("swift_haptics") private var haptics = true
    @AppStorage("swift_class_traits") private var classTraits = true
    @AppStorage("swift_music_on") private var musicOn = true
    @AppStorage("swift_sfx_on") private var sfxOn = true
    @AppStorage("swift_ambient_on") private var ambientOn = true
    @AppStorage("swift_music_volume") private var musicVolume = 0.7
    @AppStorage("swift_sfx_volume") private var sfxVolume = 0.8
    @AppStorage("swift_ambient_volume") private var ambientVolume = 0.35
    @AppStorage("swift_verbose_rooms") private var verboseRooms = true
    @AppStorage("swift_combat_announcements") private var combatAnnouncements = true

    struct Category {
        let id: String
        let icon: String
        let name: String
        let desc: String
        let label: String
        var tag: String? = nil
    }

    static let categories: [Category] = [
        Category(id: "audio", icon: "🔊", name: "Audio", desc: "Music, sound effects, ambient sounds", label: "Audio settings"),
        Category(id: "accessibility", icon: "♿", name: "Accessibility", desc: "Screen reader, motion, announcements", label: "Accessibility settings"),
        Category(id: "language", icon: "🌍", name: "Language", desc: "Game language and translation", label: "Language settings"),
        Category(id: "gameplay", icon: "🎮", name: "Gameplay", desc: "Run modifiers, menu items, game features",
                 label: "Gameplay settings — run modifiers and menu customization"),
        Category(id: "account", icon: "☁", name: "Account", desc: "Cloud saves · Alpha", label: "Account settings, alpha feature", tag: "ALPHA"),
        Category(id: "general", icon: "⚙️", name: "General", desc: "Game info, save data, export and import",
                 label: "General settings, game info, save data, export and import"),
        Category(id: "dev", icon: "🔧", name: "Developer Tools", desc: "Testing and debug options", label: "Developer Tools, password protected"),
        Category(id: "chat", icon: "💬", name: "Chat", desc: "Global chat, username, notifications", label: "Chat settings — global chat username and preferences"),
        Category(id: "notifications", icon: "🔔", name: "Notifications", desc: "Choose what the game notifies you about",
                 label: "Notification settings — choose what the game notifies you about"),
        Category(id: "beta", icon: "🧪", name: "Beta Features", desc: "Experimental features — test before they go live",
                 label: "Beta Features — experimental features you can test", tag: "BETA"),
    ]

    static let panelNames = ["audio": "Audio", "language": "Language", "accessibility": "Accessibility", "gameplay": "Gameplay",
                             "account": "Account", "dev": "Developer Tools", "general": "General"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            WebBackground().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let p = panel { panelView(p) } else { main }
                }
                .padding(.horizontal, 20).padding(.top, 40).padding(.bottom, 60)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .accessibilityAddTraits(.isModal)
        .webImportAlerts(webImport, game: game)
    }

    private func back(_ label: String, action: @escaping () -> Void) -> some View {
        Button("← Back", action: action)
            .buttonStyle(BackButtonStyle())
            .padding(.bottom, 20)
            .accessibilityLabel(label)
    }

    // MARK: Categories

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            back("Close settings and return") { close() }
            Text("⚙ Settings").font(Theme.decorative(19.2)).foregroundStyle(Theme.gold).padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            Text("Choose a category to customize your experience.").font(Theme.crimson(13.1, italic: true))
                .foregroundStyle(Theme.textSecondary).padding(.bottom, 24)
            VStack(spacing: 10) {
                ForEach(Self.categories, id: \.id) { c in
                    Button { open(c.id) } label: {
                        HStack(spacing: 16) {
                            Text(c.icon).font(.system(size: 24)).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(c.name).font(Theme.cinzel(14)).foregroundStyle(Theme.ashLight)
                                    if let t = c.tag { Text(t).font(Theme.cinzel(8.8)).foregroundStyle(Theme.goldDim) }
                                }
                                Text(c.desc).font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("›").font(Theme.cinzel(12)).foregroundStyle(Theme.textDim).accessibilityHidden(true)
                        }
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, 16).padding(.horizontal, 20)
                        .background(Theme.bgPanel)
                        .overlay(Rectangle().stroke(Theme.borderDim))
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.borderGlow).frame(width: 3) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.label)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func open(_ id: String) {
        guard ["audio", "accessibility", "gameplay", "general", "account"].contains(id) else {
            Sound.sfx("sfx-select")
            let name = Self.categories.first { $0.id == id }?.name ?? id
            Feedback.announce("\(name) settings aren't in the Swift version yet. Coming soon.")
            return
        }
        panel = id
        Feedback.announce("\(Self.panelNames[id] ?? id) settings opened.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { UIAccessibility.post(notification: .screenChanged, argument: nil) }
    }

    // MARK: Panels

    @ViewBuilder
    private func panelView(_ id: String) -> some View {
        back("Back to settings") {
            panel = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { UIAccessibility.post(notification: .screenChanged, argument: nil) }
        }
        switch id {
        case "audio": audio
        case "accessibility": accessibility
        case "gameplay": gameplay
        case "account": AccountPanel()
        default: general
        }
    }

    private func title(_ t: String) -> some View {
        Text(t).font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).padding(.bottom, 20)
            .accessibilityAddTraits(.isHeader)
    }

    private var audio: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("🔊 Audio")
            volumeRow("Music", on: $musicOn, volume: $musicVolume, toggleLabel: "Music toggle", volumeLabel: "Music volume")
            Text("📱 On iPhone, use your device volume buttons to control audio levels.")
                .font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x666666)).padding(.bottom, 14)
            divider
            volumeRow("Sound Effects", on: $sfxOn, volume: $sfxVolume, toggleLabel: "Sound effects toggle", volumeLabel: "Sound effects volume")
            divider
            volumeRow("Ambient Sound", on: $ambientOn, volume: $ambientVolume, toggleLabel: "Ambient sound toggle", volumeLabel: "Ambient volume")
            divider
            toggleRow("Vibration", isOn: $haptics, label: "Vibration toggle")
            divider
            HStack {
                Text("Shake to Attack").font(Theme.cinzel(11.2)).tracking(3.4).textCase(.uppercase).foregroundStyle(Theme.goldDim)
                Spacer()
                Button("Off") { notYet("Shake to Attack") }.buttonStyle(ToggleButtonStyle(on: false))
                    .accessibilityLabel("Shake to attack toggle")
            }
            .padding(.bottom, 18)
            VStack(alignment: .leading, spacing: 8) {
                Text("🎵 CUSTOM TRACK").font(Theme.cinzel(11.2)).tracking(2).foregroundStyle(Color(hex: 0xaa88dd))
                Text("Play your own music instead of the game soundtrack. Use a file for testing or a URL to save it permanently.")
                    .font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
                Button("📁 Choose Audio File") { notYet("Custom tracks") }.buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Choose audio file from your device")
            }
            .padding(14).background(Color(hex: 0x0a0814)).overlay(Rectangle().stroke(Color(hex: 0x332255)))
        }
        .onChange(of: musicOn) { _ in Sound.settingsChanged() }
        .onChange(of: ambientOn) { _ in Sound.settingsChanged() }
        .onChange(of: musicVolume) { _ in Sound.settingsChanged() }
        .onChange(of: ambientVolume) { _ in Sound.settingsChanged() }
        .onChange(of: sfxVolume) { _ in Sound.sfx("sfx-select") }
    }

    private var divider: some View {
        Rectangle().fill(Theme.borderDim).frame(height: 1).padding(.vertical, 14).accessibilityHidden(true)
    }

    private func volumeRow(_ name: String, on: Binding<Bool>, volume: Binding<Double>, toggleLabel: String, volumeLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(Theme.cinzel(11.2)).tracking(3.4).textCase(.uppercase).foregroundStyle(Theme.goldDim)
                    .accessibilityHidden(true)
                Spacer()
                Button(on.wrappedValue ? "On" : "Off") {
                    on.wrappedValue.toggle()
                    Feedback.announce("\(name) \(on.wrappedValue ? "on" : "off").")
                }
                .buttonStyle(ToggleButtonStyle(on: on.wrappedValue))
                .accessibilityLabel("\(toggleLabel) currently \(on.wrappedValue ? "on" : "off")")
            }
            HStack(spacing: 12) {
                Text("VOL").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim).accessibilityHidden(true)
                VolumeSlider(label: volumeLabel, value: volume)
                    .tint(Theme.gold)
                Text("\(Int((volume.wrappedValue * 100).rounded()))").font(Theme.cinzel(11.2)).foregroundStyle(Theme.ash)
                    .frame(width: 30, alignment: .trailing).accessibilityHidden(true)
            }
        }
        .padding(.bottom, 4)
    }

    private func toggleRow(_ name: String, isOn: Binding<Bool>, label: String) -> some View {
        HStack {
            Text(name).font(Theme.cinzel(11.2)).tracking(3.4).textCase(.uppercase).foregroundStyle(Theme.goldDim)
                .accessibilityHidden(true)
            Spacer()
            Button(isOn.wrappedValue ? "On" : "Off") {
                isOn.wrappedValue.toggle()
                Feedback.announce("\(name) \(isOn.wrappedValue ? "on" : "off").")
            }
            .buttonStyle(ToggleButtonStyle(on: isOn.wrappedValue))
            .accessibilityLabel("\(label) currently \(isOn.wrappedValue ? "on" : "off")")
        }
    }

    private func option(_ name: String, _ desc: String, isOn: Binding<Bool>, label: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Theme.cinzel(12)).foregroundStyle(Theme.ashLight)
                Text(desc).font(Theme.crimson(11.5, italic: true)).foregroundStyle(Theme.textDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            Button(isOn.wrappedValue ? "On" : "Off") {
                isOn.wrappedValue.toggle()
                Feedback.announce("\(name) \(isOn.wrappedValue ? "on" : "off").")
            }
            .buttonStyle(ToggleButtonStyle(on: isOn.wrappedValue))
            .accessibilityLabel("\(label) currently \(isOn.wrappedValue ? "on" : "off")")
            .accessibilityHint(desc)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderDim).frame(height: 1) }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("♿ Accessibility")
            option("Verbose Room Descriptions", "Auto-announce full room text when entering.", isOn: $verboseRooms,
                   label: "Verbose descriptions")
            option("Combat Announcements", "Announce every hit and miss in combat.", isOn: $combatAnnouncements,
                   label: "Combat announcements")
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repair Dungeon Unlocks").font(Theme.cinzel(12)).foregroundStyle(Theme.ashLight)
                    Text("If dungeons are not unlocking after completion, press this to repair.")
                        .font(Theme.crimson(11.5, italic: true)).foregroundStyle(Theme.textDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
                Button("Repair") {
                    _ = game.unlockedDungeons()
                    Sound.sfx("sfx-confirm")
                    Feedback.announce("Dungeon unlocks repaired. If you completed a dungeon your next dungeon should now be available.")
                }
                .buttonStyle(ToggleButtonStyle(on: true))
                .accessibilityLabel("Repair dungeon unlocks now")
            }
            .padding(.vertical, 10)
        }
    }

    private var gameplay: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("🎮 Gameplay")
            option("⚔️ Class Traits", "Unique passive abilities per class. Toggle off for a classic experience.",
                   isOn: $classTraits, label: "Class traits")
            Button {
                notYet("Run modifiers")
            } label: {
                HStack {
                    Text("🎲 Run Modifiers").font(Theme.cinzel(12)).foregroundStyle(Theme.ashLight)
                    Spacer()
                    Text("Coming soon").font(Theme.cinzel(10)).foregroundStyle(Theme.textDim)
                }
                .padding(.vertical, 12)
            }
            .accessibilityLabel("Run modifiers. Coming soon.")
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("⚙️ General")
            VStack(alignment: .leading, spacing: 4) {
                Text("Game Version").font(Theme.cinzel(11.2)).tracking(2).foregroundStyle(Theme.goldDim)
                Text("Dungeon Descent v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")")
                    .font(Theme.cinzel(12)).foregroundStyle(Theme.ashLight)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 8) {
                Text("Web Version Save").font(Theme.cinzel(11.2)).tracking(2).foregroundStyle(Theme.goldDim)
                Text("Copies your characters, gold, items and progress from the web version of Dungeon Descent on this iPhone. It replaces what's in the Swift version.")
                    .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
                Button(webImport.checking ? "Looking for a web version save…" : "📥 Import Web Save") {
                    webImport.check(game, quietIfEmpty: false)
                }
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .disabled(webImport.checking)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Export Save Code").font(Theme.cinzel(11.2)).tracking(2).foregroundStyle(Theme.goldDim)
                Text("Generate a code containing all your save data. Copy it to back up or transfer to another device.")
                    .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
                Button("📋 Copy Code") { notYet("Save codes") }.buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Export save code")
            }
            HStack(spacing: 16) {
                Link("Privacy Policy", destination: URL(string: "https://dungen-descent.org/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://dungen-descent.org/terms")!)
            }
            .font(Theme.cinzel(11)).tint(Theme.gold)
        }
    }

    private func notYet(_ what: String) {
        Sound.sfx("sfx-select")
        Feedback.announce("\(what) isn't in the Swift version yet. Coming soon.")
    }
}

/// .toggle-btn and .toggle-btn.on
struct ToggleButtonStyle: ButtonStyle {
    let on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.cinzel(10.4)).textCase(.uppercase)
            .foregroundStyle(on ? Theme.gold : Theme.ash)
            .padding(.vertical, 4).padding(.horizontal, 12)
            .frame(minWidth: 52, minHeight: 36)
            .overlay(Rectangle().stroke(on ? Theme.goldDim : Theme.borderDim))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
