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
                .onAppear { GameCenter.signIn() }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { game.saveNow() }
        }
    }
}
