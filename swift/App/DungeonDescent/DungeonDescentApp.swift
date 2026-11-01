import SwiftUI
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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .environmentObject(router)
                .environment(\.locale, locale)
                .onReceive(Language.changed) { locale = Language.locale }
                .onAppear {
                    GameCenter.signIn()
                    CloudAccount.shared.start(game: game)
                    // An Endless Descent run left going picks up where it is.
                    if AFKModel.isRunning(game.store) { router.goTo(.afk) }
                    // App Store screenshots from the simulator: -startScreen <name>
                    // opens that screen (simctl can't tap through the menu).
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "-startScreen"), i + 1 < args.count {
                        let screens: [String: Router.Screen] = ["charlist": .charlist, "afk": .afk, "events": .events,
                                                                "help": .help, "whatsnew": .whatsnew, "bestiary": .bestiary]
                        if let s = screens[args[i + 1]] { router.goTo(s) }
                    }
                    // Reminders stay current (the comeback one moves 48 hours out).
                    Task { _ = await GameNotifications.apply(game.store, ask: false) }
                }
                // Tapping the Live Activity opens its run.
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
            if phase == .background { AudioEngine.shared.enterBackground() }
            if phase == .active { AudioEngine.shared.enterForeground() }
            if phase != .active {
                game.saveNow()
                CloudAccount.shared.autoSync()
                ICloudBackup.shared.autoBackup(game: game)
            }
        }
    }
}
