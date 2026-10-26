import SwiftUI

@main
struct DungeonDescentApp: App {
    @StateObject private var game = GameModel()
    @StateObject private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .environmentObject(router)
                .onAppear {
                    GameCenter.signIn()
                    // An Endless Descent run left going picks up where it is.
                    if AFKModel.isRunning(game.store) { router.goTo(.afk) }
                }
                // Tapping the Live Activity opens its run.
                .onOpenURL { url in
                    if url.scheme == "dungeondescent" && url.host == "afk" { router.goTo(.afk) }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { game.saveNow() }
        }
    }
}
