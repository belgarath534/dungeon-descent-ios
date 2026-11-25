import SwiftUI
import UIKit
import DungeonCore

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
        case codex
        case highscore
        case chronicles
        case afk
        case obituary
        case chat
        case tournament
        case multiplayer
        case hideseek
        case help
        case credits
        case events
        case blacksmith
        case spire
        case arcane
        case mine
        case voidmode
        case voidreaper
        case worldBoss
        case battlePass
        case coop
        case siege
        case challenges
        case bounty
        case hunting
        case spellbook
        case seasonalshop
        case whatsnew
        case quit
        /// The secret Shadow Realm, open once the Shadow World is cleared.
        case shadowRealm
        case commandCenter
        case enemyCreator
        /// 12.1: Friends and Rankings.
        case friends
        /// 12.1: dungeons built by players.
        case communityDungeons
        /// 12.2: Guilds.
        case guilds
    }

    @Published private(set) var screen: Screen = .menu

    /// Changes every time a run starts, so a new run gets a fresh screen.
    private(set) var runID = 0

    /// 12.1: where you've been, for Back (a player asked for an easy way
    /// back after opening the wrong screen).
    private var history: [Screen] = []

    func goTo(_ s: Screen) {
        if case .dungeon = s { runID += 1 }
        remember(screen, next: s)
        show(s)
    }

    private func remember(_ old: Screen, next: Screen) {
        guard old != next, old != .quit else { return }
        // Back into a run always resumes it (never starts a new one).
        if case .dungeon(let id, _) = old { history.append(.dungeon(id, resume: true)) } else { history.append(old) }
        if history.count > 20 { history.removeFirst() }
    }

    /// The screen before this one (the main menu when there isn't one).
    func back() {
        guard screen != .menu else {
            Feedback.announce("You're on the main menu.")
            return
        }
        var target: Screen = .menu
        while let last = history.popLast() {
            if last != screen { target = last; break }
        }
        if case .dungeon = target { runID += 1 }
        Sound.sfx("sfx-select")
        show(target)
    }

    private func show(_ s: Screen) {
        screen = s
        Self.playMusic(for: s)
        Friends.shared.doing(screen: s)
        // A new page: VoiceOver starts again from its top.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
}

extension Router {
    /// goTo's "music per screen": each screen with its own track starts it.
    /// Screens not listed keep whatever is playing (modes start their own).
    static func playMusic(for s: Screen) {
        switch s {
        case .menu, .charlist, .creation: Sound.track("menu")
        case .bestiary: Sound.track("bestiary")
        case .help: Sound.track("help")
        case .chat: Sound.track("home")
        case .codex: Sound.track("codex")
        case .chronicles: Sound.track("chronicles")
        case .spire: Sound.track("spire")
        case .graveyard: Sound.track("graveyard")
        // 12.1: the tavern songs, shuffled.
        case .coop, .friends, .bounty, .guilds: Sound.track("tavern")
        // The death log is silent, like the run summary.
        case .deathlog: Sound.stopMusic()
        default: break
        }
    }
}

struct RootView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var game: GameModel
    /// The loading screen first; the game appears when it fades.
    @State private var loading = !LoadingScreen.skipped
    @State private var rested: OfflineRest.Reward?
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject private var cloud = CloudAccount.shared

    var body: some View {
        if loading {
            LoadingScreen {
                loading = false
                checkRest(after: 1.5)
                // 12.1: the welcome tutorial, the first time (no characters yet).
                if !LoadingScreen.skipped { Tutorial.shared.showIfNew(game) }
            }.preferredColorScheme(.dark)
        } else {
            content
                .overlay { if let r = rested { OfflineRestOverlay(reward: r) { rested = nil } } }
                // Cloud sync: both this device and another one have newer progress.
                .alert("Choose a save", isPresented: $cloud.choosingSave) {
                    Button("Use the cloud save") { Task { await cloud.keepCloudSave() } }
                    Button("Keep this device's save") { Task { await cloud.keepDeviceSave() } }
                } message: {
                    Text("You played on this device and on another one since they last matched. The cloud save replaces what's on this device. Keeping this device's save uploads it over the cloud one.")
                }
                .onChange(of: scenePhase) { phase in
                    // Away time counts from when you leave the app, not only between launches.
                    if phase == .background { OfflineRest.seen(game.store) }
                    if phase == .active { checkRest(after: 1.0) }
                }
        }
    }

    /// checkOfflineProgress, shortly after the game appears or you come back.
    private func checkRest(after delay: Double) {
        guard !LoadingScreen.skipped else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Not while iOS has the app running in the background (Background App Refresh).
            guard rested == nil, UIApplication.shared.applicationState != .background else { return }
            if let r = OfflineRest.check(game.store, wallet: game.wallet, character: game.characters.first) { rested = r }
        }
    }

    private var content: some View {
        // 12.1 Back: VoiceOver's two-finger scrub (the Z) or a swipe in from
        // the left edge returns to the previous screen. Pop-ups that handle
        // the scrub themselves close first.
        Group {
            switch router.screen {
            // The tab menu, or the single list with Settings → Classic menu.
            case .menu:
                if UserDefaults.standard.bool(forKey: "swift_classic_menu") { MainMenuView() } else { MainTabsView() }
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
            case .codex: CodexView()
            case .highscore: HighScoreView()
            case .chronicles: ChroniclesView()
            case .afk: AFKView(model: game.afk)
            case .obituary: ObituaryView()
            case .chat: GlobalChatView(store: game.store)
            case .tournament: TournamentView()
            case .multiplayer: PvPView()
            case .hideseek: HideSeekView()
            case .help: HelpView()
            case .credits: CreditsView()
            case .events: EventsView()
            case .blacksmith: MenuBlacksmithScreen()
            case .spire: SpireView()
            case .arcane: MenuSpellsScreen(showingBook: false)
            case .mine: MineView()
            case .voidmode: VoidModeView()
            case .shadowRealm: ShadowRealmView()
            case .commandCenter: CommandCenterView()
            case .enemyCreator: EnemyCreatorView()
            case .voidreaper: VoidReaperView()
            case .worldBoss: WorldBossView()
            case .battlePass: BattlePassView()
            case .coop: CoopView()
            case .friends: FriendsView()
            case .communityDungeons: CommunityDungeonsView()
            case .guilds: GuildsView()
            case .siege: SiegeView()
            case .challenges: ChallengesView()
            case .bounty: BountyBoardView()
            case .hunting: HuntingGroundsView()
            case .spellbook: MenuSpellsScreen(showingBook: true)
            case .seasonalshop: SeasonalShopView()
            case .whatsnew: WhatsNewView()
            case .quit: QuitScreen()
            }
        }
        .navigationShortcuts()
        .accessibilityAction(.escape) { router.back() }
        .overlay(alignment: .leading) {
            Color.clear.frame(width: 12).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 30).onEnded { g in
                    if g.translation.width > 80 && abs(g.translation.height) < 60 { router.back() }
                })
                .accessibilityHidden(true)
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
