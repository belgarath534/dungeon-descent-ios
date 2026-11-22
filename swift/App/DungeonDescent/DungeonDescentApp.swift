import SwiftUI
import DungeonCore
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct DungeonDescentApp: App {
    @StateObject private var game = GameModel.shared
    @StateObject private var router = Router()
    /// The game's language; changing it redraws every screen.
    @State private var locale = Language.locale
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CloudAccount.configure()
        WatchBridge.shared.activate()
        KeyboardDone.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modifier(FriendInviteAlert())
                .environmentObject(game)
                .environmentObject(router)
                .environment(\.locale, locale)
                .onReceive(Language.changed) { locale = Language.locale }
                .onAppear {
                    GameCenter.signIn()
                    PlaytimeClock.shared.start(game)
                    CloudAccount.shared.start(game: game)
                    // An Endless Descent run left going picks up where it is.
                    if AFKModel.isRunning(game.store) { router.goTo(.afk) }
                    // App Store screenshots from the simulator: -startScreen <name>
                    // opens that screen (simctl can't tap through the menu).
                    let args = ProcessInfo.processInfo.arguments
                    // The screen tour (large text): a character to play with.
                    if args.contains("-tourCharacter"), game.characters.isEmpty {
                        game.create(PlayerCharacter(name: "Tourist", cls: "Warrior", race: "Human", prof: "Thief",
                                                    dungeon: "Crypt of Malachar", difficulty: .wanderer))
                    }
                    if let i = args.firstIndex(of: "-startScreen"), i + 1 < args.count {
                        let screens: [String: Router.Screen] = ["charlist": .charlist, "afk": .afk, "events": .events,
                                                                "help": .help, "whatsnew": .whatsnew, "bestiary": .bestiary,
                                                                "friends": .friends, "coop": .coop, "spire": .spire,
                                                                "quests": .quests, "challenges": .challenges, "settings": .settings,
                                                                "battlepass": .battlePass, "blacksmith": .blacksmith, "chronicles": .chronicles,
                                                                "records": .records, "worldboss": .worldBoss, "mine": .mine, "chat": .chat]
                        if args[i + 1] == "dungeon", let ch = game.characters.first {
                            router.goTo(.dungeon(ch.created, resume: false))
                        } else if let s = screens[args[i + 1]] {
                            router.goTo(s)
                        }
                    }
                    // Reminders stay current (the comeback one moves 48 hours out).
                    Task { _ = await GameNotifications.apply(game.store, ask: false) }
                }
                // Tapping the Live Activity opens its run.
                // Siri / Shortcuts: "Start Endless Descent".
                .onReceive(NotificationCenter.default.publisher(for: .openEndlessDescent)) { _ in router.goTo(.afk) }
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    #endif
                    if url.scheme == "dungeondescent" && url.host == "afk" { router.goTo(.afk) }
                }
        }
        // Endless Descent keeps going while the app is paused (AFKBackground).
        .backgroundTask(.appRefresh(AFKBackground.id)) {
            await MainActor.run { AFKBackground.refresh() }
        }
        .onChange(of: scenePhase) { phase in
            game.afk.inForeground = phase == .active
            if phase == .background {
                if AFKModel.isRunning(game.store) {
                    AFKBackground.schedule()
                    LiveActivityPush.planAndSend()
                } else { AFKBackground.cancel() }
            }
            if phase == .active && AFKModel.isRunning(game.store) { LiveActivityPush.cancel() }
            if phase == .background { AudioEngine.shared.enterBackground(); PlaytimeClock.shared.stop() }
            if phase == .active { AudioEngine.shared.enterForeground(); PlaytimeClock.shared.start(game) }
            // Back in the app: a newer save from another device, if nothing changed here.
            if phase == .active { Task { await CloudAccount.shared.checkCloud(launch: false) } }
            if phase != .active {
                game.saveNow()
                if phase == .background { CloudAccount.shared.syncOnLeave() } else { CloudAccount.shared.autoSync() }
                ICloudBackup.shared.autoBackup(game: game)
            }
        }
    }
}
