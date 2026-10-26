import SwiftUI
import UIKit

/// One screen at a time, like the web version's goTo(id): no page stack and
/// no swipe back, each screen has its own back buttons.
@MainActor
final class Router: ObservableObject {
    enum Screen: Hashable {
        case menu
        case charlist
        case deathlog
        case creation
        /// A character's run, by creation time; resume continues its saved run.
        case dungeon(Double, resume: Bool)
        case quests
        case settings
        case graveyard
        case bestiary
        case records
        case bossrush
        case raid
        case coinshop
        case help
        case credits
        case whatsnew
        case quit
    }

    @Published private(set) var screen: Screen = .menu

    /// Changes every time a run starts, so a new run gets a fresh screen.
    private(set) var runID = 0

    func goTo(_ s: Screen) {
        if case .dungeon = s { runID += 1 }
        screen = s
        // A new page: VoiceOver starts again from its top.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var game: GameModel

    var body: some View {
        Group {
            switch router.screen {
            case .menu: MainMenuView()
            case .charlist: CharacterListView()
            case .deathlog: DeathLogView()
            case .creation:
                NavigationStack { CreateCharacterView() }.tint(Theme.gold)
            case .dungeon(let id, let resume):
                if let i = game.characters.firstIndex(where: { $0.created == id }) {
                    DungeonView(game: game, characterIndex: i, resume: resume)
                        .id(router.runID)
                } else {
                    CharacterListView()
                }
            case .quests: AchievementsView()
            case .settings: WebSettingsView { router.goTo(.menu) }
            case .graveyard: GraveyardView()
            case .bestiary: BestiaryView()
            case .records: HallOfRecordsView()
            case .bossrush: BossRushView()
            case .raid: RaidView()
            case .coinshop: CoinShopView()
            case .help: HelpView()
            case .credits: CreditsView()
            case .whatsnew: WhatsNewView()
            case .quit: QuitScreen()
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// confirmQuit(): the page is replaced with one line.
struct QuitScreen: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("The dungeon claims another soul.")
                .font(Theme.cinzel(12.8))
                .tracking(3.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.goldDim)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}
