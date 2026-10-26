import SwiftUI
import UIKit

/// One screen at a time, like the web version's goTo(id): no page stack and
/// no swipe back, each screen has its own back buttons.
@MainActor
final class Router: ObservableObject {
    enum Screen: Hashable {
        case menu
        case charlist
        case quests
        case settings
        case quit
    }

    @Published private(set) var screen: Screen = .menu

    func goTo(_ s: Screen) {
        screen = s
        // A new page: VoiceOver starts again from its top.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var router: Router

    var body: some View {
        Group {
            switch router.screen {
            case .menu: MainMenuView()
            case .charlist: NativeScreen { CharacterListView() }
            case .quests: NativeScreen { AchievementsView() }
            case .settings: NativeScreen { SettingsView() }
            case .quit: QuitScreen()
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Screens not yet rebuilt in the web style keep their own navigation, with
/// the web version's "← Menu" button to get back.
struct NativeScreen<Content: View>: View {
    @EnvironmentObject var router: Router
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("← Menu") { router.goTo(.menu) }
                            .font(Theme.cinzel(12))
                            .accessibilityLabel("Back to main menu")
                    }
                }
        }
        .tint(Theme.gold)
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
