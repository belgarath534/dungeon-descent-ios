import SwiftUI

/// The web version's keyboard commands, for the Mac and for iPad or iPhone
/// with a keyboard. Ctrl+Shift+letter opens a screen (outside the dungeon);
/// the dungeon's Alt (Option)+letter combat keys live on its buttons.
struct NavigationShortcuts: ViewModifier {
    @EnvironmentObject var router: Router

    private var inDungeon: Bool { if case .dungeon = router.screen { return true }; return false }

    private static let screens: [(KeyEquivalent, Router.Screen, String)] = [
        ("h", .menu, "Main menu"), ("p", .charlist, "Character list"), ("b", .bestiary, "Bestiary"),
        ("q", .quests, "Quests and achievements"), ("e", .events, "Events"), ("s", .settings, "Settings"),
        ("r", .highscore, "High score"), ("l", .chronicles, "Chronicles"), ("k", .spellbook, "Spell book"),
        ("a", .arcane, "Arcane shop"), ("n", .creation, "New character"),
    ]

    func body(content: Content) -> some View {
        content.background {
            // Invisible buttons that only carry the shortcuts.
            ForEach(Self.screens, id: \.2) { key, screen, name in
                Button(name) {
                    guard !inDungeon else {
                        Feedback.announce("Leave the dungeon from the pause menu first.")
                        return
                    }
                    router.goTo(screen)
                }
                .keyboardShortcut(key, modifiers: [.control, .shift])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func navigationShortcuts() -> some View { modifier(NavigationShortcuts()) }

    /// Alt (Option)+key, the web version's combat keys.
    func combatKey(_ key: KeyEquivalent) -> some View { keyboardShortcut(key, modifiers: .option) }
}

/// Alt+1, 2 and 3 for the first three skills.
struct SkillKey: ViewModifier {
    let index: Int
    func body(content: Content) -> some View {
        if index < 3 {
            content.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .option)
        } else {
            content
        }
    }
}
