import SwiftUI
import GoogleSignIn

@main
struct DungeonDescentApp: App {
    @StateObject private var game = GameModel()
    @StateObject private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CloudAccount.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .environmentObject(router)
                .onAppear {
                    GameCenter.signIn()
                    CloudAccount.shared.start(game: game)
                    // An Endless Descent run left going picks up where it is.
                    if AFKModel.isRunning(game.store) { router.goTo(.afk) }
                    // Reminders stay current (the comeback one moves 48 hours out).
                    Task { _ = await GameNotifications.apply(game.store, ask: false) }
                }
                // Tapping the Live Activity opens its run.
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    if url.scheme == "dungeondescent" && url.host == "afk" { router.goTo(.afk) }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                game.saveNow()
                CloudAccount.shared.autoSync()
                ICloudBackup.shared.autoBackup(game: game)
            }
        }
    }
}
