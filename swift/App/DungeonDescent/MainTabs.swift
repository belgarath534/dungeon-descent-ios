import SwiftUI
import DungeonCore

/// THE TAB MENU (12.0): the main menu split into five tabs along the bottom,
/// Apple's own tab bar, which VoiceOver reads as "Modes, tab, 2 of 5". Each
/// tab is a short list of the same buttons as the classic menu, so touch
/// exploration reaches everything without scrolling past the rest.
/// Settings → Gameplay → Classic menu brings back the single list.
enum MainTab: String, CaseIterable {
    case play, modes, multiplayer, more, settings

    var title: String {
        switch self {
        case .play: return "Play"
        case .modes: return "Modes"
        case .multiplayer: return "Multiplayer"
        case .more: return "More"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .play: return "play.circle.fill"
        case .modes: return "map.fill"
        case .multiplayer: return "person.3.fill"
        case .more: return "bag.fill"
        case .settings: return "gearshape.fill"
        }
    }

    /// The menu entries in each tab, in order (MainMenuView.entries' ids).
    var ids: [String] {
        switch self {
        case .play: return ["afk", "challenges", "battlepass", "quests"]
        case .modes: return ["spire", "bossrush", "raid", "siege", "mine", "bounty", "void", "shadowrealm",
                             "hideseek", "creator", "command"]
        case .multiplayer: return ["coop", "worldboss", "multiplayer", "tournament", "chat", "obituary"]
        case .more: return ["blacksmith", "coinshop", "arcane", "spellbook", "bestiary", "codex", "chronicles",
                            "graveyard", "records", "highscore", "events", "whatsnew", "help", "credits", "leo", "quit"]
        case .settings: return []
        }
    }

    /// Read when the tab opens.
    var spoken: String {
        switch self {
        case .play: return "Play."
        case .modes: return "Modes. The Spire, Boss Rush, Raid, the Siege, the Mine and more."
        case .multiplayer: return "Multiplayer. Co-op, the World Boss, PvP, the Tournament, Global Chat and Game Center."
        case .more: return "More. Shops, the Blacksmith, the Bestiary, lore, records, help and what's new."
        case .settings: return "Settings."
        }
    }
}

struct MainTabsView: View {
    @EnvironmentObject var router: Router
    @AppStorage("swift_menu_tab") private var tab = MainTab.play.rawValue
    @AppStorage("swift_tabs_intro_seen") private var introSeen = false

    var body: some View {
        TabView(selection: $tab) {
            ForEach(MainTab.allCases, id: \.self) { t in
                Group {
                    if t == .settings {
                        WebSettingsView { tab = MainTab.play.rawValue }
                    } else {
                        MainMenuView(tab: t)
                    }
                }
                .tabItem { Label(t.title, systemImage: t.icon) }
                .tag(t.rawValue)
            }
        }
        .tint(Theme.gold)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color(hex: 0x0b0906), for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onChange(of: tab) { new in
            Sound.sfx("sfx-select")
            if let t = MainTab(rawValue: new) { Feedback.announce(t.spoken, after: 0.3) }
        }
        .onAppear {
            guard !introSeen else { return }
            introSeen = true
            Feedback.announce("New in 12.0: the menu has tabs at the bottom of the screen: Play, Modes, Multiplayer, More and Settings. Prefer the old menu? Turn on Classic menu in Settings, Gameplay.", after: 2.5)
        }
    }
}
