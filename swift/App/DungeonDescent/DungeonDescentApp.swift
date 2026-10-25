import SwiftUI

@main
struct DungeonDescentApp: App {
    @StateObject private var game = GameModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MainMenuView()
            }
            .environmentObject(game)
            .preferredColorScheme(.dark)
            .tint(Theme.gold)
        }
    }
}

enum Theme {
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.35)
    static let blood = Color(red: 0.8, green: 0.15, blue: 0.15)
    static let panel = Color(white: 0.11)
}
