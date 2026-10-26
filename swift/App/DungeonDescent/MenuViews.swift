import SwiftUI
import DungeonCore

/// The main menu, laid out like the web version's #screen-menu: same
/// order, same text and the same VoiceOver labels. Modes that aren't in the
/// Swift version yet stay in the list and say so when chosen.
struct MainMenuView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @Environment(\.openURL) private var openURL
    @StateObject private var webImport = WebImportFlow()
    @State private var trophies = 0
    @State private var familiar = ""
    @State private var quitting = false
    @State private var toast: String?

    enum Action {
        case go(Router.Screen)
        case url(String)
        case quit
        case notYet
    }

    struct Entry: Identifiable {
        let id: String
        let text: String
        let label: String
        var color: Color? = nil
        var border: Color? = nil
        var beta = false
        var action: Action = .notYet
        var separatorBefore = false
    }

    static let purple = Color(hex: 0xcc88ff), purpleBorder = Color(hex: 0xaa66ff)

    static let entries: [Entry] = [
        Entry(id: "multiplayer", text: "⚔️👥 Multiplayer", label: "PVP Arena, fight another player in real time turn based combat",
              color: Color(hex: 0x88aaff), border: Color(hex: 0x4466ff), beta: true),
        Entry(id: "hideseek", text: "🕯️ Hide and Seek", label: "Hide and Seek, something is chasing you, find the way out",
              color: Color(hex: 0xbb88ee), border: Color(hex: 0x663399), beta: true),
        Entry(id: "leo", text: "🎬 Leo Audio Gaming", label: "Visit Leo Audio Gaming on YouTube, opens in new tab",
              color: Color(hex: 0xff4444), border: Color(hex: 0xff0000),
              action: .url("https://www.youtube.com/@leo09393"), separatorBefore: true),
        Entry(id: "bestiary", text: "📖 Bestiary", label: "Bestiary, view all enemies you have encountered", action: .go(.bestiary)),
        Entry(id: "quests", text: "📜 Quests", label: "Quests and achievements", action: .go(.quests)),
        Entry(id: "coinshop", text: "🪙 Coin Shop", label: "Mystery Coin Shop, spend your Mystery Coins on permanent upgrades", action: .go(.coinshop)),
        Entry(id: "afk", text: "⬇ Endless Descent", label: "Endless Descent, AFK mode"),
        Entry(id: "spire", text: "🗼 The Spire", label: "The Spire, climb 1800 floors to face The Time Eater"),
        Entry(id: "void", text: "🌑 Void Mode", label: "Void Mode, become the Void Commander and survive five waves of heroes"),
        Entry(id: "command", text: "⌨️ Command Center", label: "Command Center — type or speak commands to control the game"),
        Entry(id: "spellbook", text: "📖 Spell Book", label: "Spell Book — view your learned spells", color: purple, border: purpleBorder),
        Entry(id: "arcane", text: "✨ Arcane Shop", label: "Arcane Shop — buy spell scrolls and the spell book", color: purple, border: purpleBorder),
        Entry(id: "graveyard", text: "⚰️ The Graveyard", label: "The Graveyard, memorial for your fallen and deleted characters", action: .go(.graveyard)),
        Entry(id: "obituary", text: "☠️ Obituary", label: "Obituary, see recent deaths from players around the world"),
        Entry(id: "challenges", text: "🔥 Challenges", label: "Challenges — The Gauntlet and Daily Dungeon"),
        Entry(id: "blacksmith", text: "⚒ Blacksmith", label: "Blacksmith — upgrade and buy weapons using your global gold"),
        Entry(id: "mine", text: "⛏ The Mine", label: "The Mine — dig for diamonds, gun parts, and rare loot",
              color: Color(hex: 0xc8a832), border: Color(hex: 0x8b6914)),
        Entry(id: "bossrush", text: "👑 Boss Rush", label: "Boss Rush, fight all nine bosses back to back", action: .go(.bossrush)),
        Entry(id: "tournament", text: "🏆 Tournament", label: "Tournament, compete against other players for the highest score"),
        Entry(id: "chronicles", text: "📚 Chronicles", label: "The Chronicles, lore and history of the dungeons", action: .go(.chronicles)),
        Entry(id: "codex", text: "📖 Codex", label: "The Codex, world lore enemy lore and artifacts unlocked through gameplay", action: .go(.codex)),
        Entry(id: "creator", text: "⚔ Enemy Creator", label: "Community Enemy Creator, build an enemy and set it loose in the dungeon"),
        Entry(id: "chat", text: "💬 Global Chat", label: "Global Chat, talk to other players"),
        Entry(id: "bounty", text: "📋 Bounty Board", label: "The Bounty Board — register for bounties and earn rewards"),
        Entry(id: "siege", text: "🏰 The Siege", label: "The Siege — defend your fortress against waves of enemies"),
        Entry(id: "whatsnew", text: "⭐ What's New", label: "What's New, see the full patch notes for every version", action: .go(.whatsnew)),
        Entry(id: "help", text: "❓ Help", label: "Help, full game manual and guide", action: .go(.help)),
        Entry(id: "records", text: "🏛️ Hall of Records", label: "Hall of Records, view your lifetime stats and claim milestone awards", action: .go(.records)),
        Entry(id: "highscore", text: "🏆 High Score", label: "High score, view your lifetime score and rank", action: .go(.highscore)),
        Entry(id: "events", text: "🎃 Events", label: "Seasonal events, see active and upcoming events"),
        Entry(id: "credits", text: "📜 Credits", label: "Credits, see who made the game", action: .go(.credits)),
        Entry(id: "raid", text: "⚔️ Raid", label: "Raid, survive five waves of enemies for daily rewards", action: .go(.raid)),
        Entry(id: "settings", text: "⚙ Settings", label: "Settings, adjust music and sound", action: .go(.settings), separatorBefore: true),
        Entry(id: "quit", text: "🕯 Quit", label: "Quit Dungeon Descent", action: .quit),
    ]

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        ZStack {
            WebBackground()
            // #menu-logo-bg: the logo fills the page, faint, behind everything.
            Image("MenuLogo")
                .resizable()
                .scaledToFill()
                .opacity(0.18)
                .ignoresSafeArea()
                .accessibilityLabel("Dungeon Descent game logo")
                .accessibilitySortPriority(1)
            ScrollView {
                VStack(spacing: 0) {
                    header
                    Ornament()
                    nav
                    footer
                }
                .padding(.horizontal, 12)
                .padding(.top, 36)
                .padding(.bottom, 80)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(Theme.cinzel(12))
                        .foregroundStyle(Theme.ash)
                        .padding(12)
                        .background(Color(hex: 0x130f0a))
                        .overlay(Rectangle().stroke(Theme.borderDim))
                        .padding(.bottom, 30)
                        .accessibilityHidden(true)
                }
                .transition(.opacity)
            }
            if quitting { quitOverlay }
        }
        .onAppear {
            Sound.track("menu")
            Sound.ambient(nil)
            trophies = game.achievements.trophies
            familiar = game.familiarBadge
            if game.shouldOfferWebImport { webImport.check(game, quietIfEmpty: true) }
        }
        .webImportAlerts(webImport, game: game)
    }

    private var header: some View {
        VStack(spacing: 0) {
            Text("⚔ a dark descent awaits ⚔")
                .font(Theme.cinzel(10.4))
                .tracking(5.7)
                .textCase(.uppercase)
                .foregroundStyle(Theme.goldDim)
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            Text("Dungeon\nDescent")
                .font(Theme.decorative(50, black: true, relativeTo: .largeTitle))
                .tracking(3)
                .lineSpacing(0)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.gold)
                .shadow(color: Theme.gold.opacity(0.35), radius: 15)
                .shadow(color: .black.opacity(0.9), radius: 2, y: 2)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("Dungeon Descent")
                .accessibilityAddTraits(.isHeader)
            Text("by Leo Productions")
                .font(Theme.cinzel(10.4))
                .tracking(2.6)
                .foregroundStyle(Color(hex: 0x666666))
                .padding(.top, 2)
                .padding(.bottom, 10)
            Link(destination: URL(string: "https://discord.gg/3FbYrQysRN")!) {
                Text("💬 Join our Discord")
                    .font(Theme.cinzel(9.6))
                    .tracking(1.9)
                    .foregroundStyle(Color(hex: 0x5865F2))
            }
            .accessibilityLabel("Join the Dungeon Descent Discord server")
            .padding(.bottom, 14)

            Button("🏆 \(trophies)") { router.goTo(.quests) }
                .font(Theme.cinzel(12.8, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Color(hex: 0xffdd44))
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(Color(red: 10 / 255, green: 5 / 255, blue: 0).opacity(0.85))
                .overlay(Rectangle().stroke(Color(hex: 0xcc9944)))
                .shadow(color: Color(hex: 0xcc9944).opacity(0.3), radius: 6)
                .padding(.vertical, 4)
                .accessibilityLabel("Your trophies — press to view")
                .accessibilityValue("\(trophies)")
            Button(familiar) { notYet("Your familiar") }
                .font(Theme.cinzel(12.8, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Color(hex: 0xaaddff))
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(Color(red: 5 / 255, green: 10 / 255, blue: 15 / 255).opacity(0.85))
                .overlay(Rectangle().stroke(Color(hex: 0x4488aa)))
                .shadow(color: Color(hex: 0x4488aa).opacity(0.3), radius: 6)
                .padding(.vertical, 4)
                .accessibilityLabel("Your familiar — press to view its bond level")
                .accessibilityValue(familiar)
            Text("\"Not all who enter are lost — most are.\"")
                .font(Theme.crimson(16, italic: true))
                .foregroundStyle(Theme.ash)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
    }

    private var nav: some View {
        VStack(spacing: 3) {
            Button {
                router.goTo(.charlist)
            } label: {
                Text("⚔ Play ⚔")
            }
            .buttonStyle(MenuButtonStyle(primary: true))
            .accessibilityLabel("Play, choose or create your character")

            ForEach(Self.entries) { e in
                if e.separatorBefore { MenuSeparator() }
                Button {
                    run(e)
                } label: {
                    HStack(spacing: 6) {
                        Text(e.text)
                        if e.beta { Text("BETA").font(Theme.cinzel(9.6)).opacity(0.7) }
                    }
                }
                .buttonStyle(MenuButtonStyle(color: e.color, border: e.border))
                .accessibilityLabel(e.label)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main menu")
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("v\(version) · Release")
                .font(Theme.cinzel(9.3))
                .tracking(2.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textDim)
                .padding(.top, 28)
                .accessibilityLabel("Version \(version.replacingOccurrences(of: ".", with: " point ")), Release")
            Text("💰 \(game.gold)")
                .accessibilityLabel("Your global gold, \(game.gold)")
            Text("💎 \(game.diamonds)")
                .accessibilityLabel("Your diamonds, \(game.diamonds)")
        }
        .font(Theme.crimson())
        .foregroundStyle(Theme.textPrimary)
    }

    private var quitOverlay: some View {
        WebOverlay(danger: true) {
            OverlayTitle(text: "Abandon the Dark?", red: true)
            OverlayText(text: "The dungeon will remember your cowardice.")
            HStack(spacing: 10) {
                Button("Flee") { router.goTo(.quit) }
                    .buttonStyle(WebButtonStyle(kind: .red))
                    .accessibilityLabel("Yes quit the game")
                Button("Stay and Fight") { quitting = false }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("No stay and continue")
            }
        }
    }

    private func run(_ e: Entry) {
        switch e.action {
        case .go(let screen): router.goTo(screen)
        case .url(let s): if let u = URL(string: s) { openURL(u) }
        case .quit: quitting = true
        case .notYet: notYet(e.text.drop { !$0.isLetter }.description)
        }
    }

    /// A mode that isn't in the Swift version yet.
    private func notYet(_ name: String) {
        Sound.sfx("sfx-select")
        let msg = "\(name) isn't in the Swift version yet. Coming soon."
        Feedback.announce(msg)
        withAnimation { toast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { if toast == msg { toast = nil } }
        }
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
