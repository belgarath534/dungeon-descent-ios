import SwiftUI

/// 12.1: a screen's own tab bar at the bottom. When a screen with sections
/// opens (Quests & Achievements, Challenges, the Chronicles), the bottom bar
/// changes from the main menu's tabs to that screen's, so players find the
/// sections in the same place every time and hear "Achievements, tab, 2 of 4".
/// The last tab, Back, returns to the menu.
struct ScreenTabs<Content: View>: View {
    struct Item {
        let id: String
        let title: String
        let icon: String
    }

    let items: [Item]
    @Binding var selection: String
    var backTitle = "Back"
    let onBack: () -> Void
    /// Called when another section is chosen (to read what's in it).
    var onSelect: (String) -> Void = { _ in }
    @ViewBuilder let content: () -> Content

    private static var backTag: String { "__back" }
    @State private var last = ""

    var body: some View {
        TabView(selection: $selection) {
            ForEach(items, id: \.id) { t in
                content()
                    .tabItem { Label(LocalizedStringKey(t.title), systemImage: t.icon) }
                    .tag(t.id)
            }
            Color.clear
                .tabItem { Label(LocalizedStringKey(backTitle), systemImage: "chevron.backward.circle.fill") }
                .tag(Self.backTag)
        }
        .tint(Theme.gold)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color(hex: 0x0b0906), for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onAppear { last = selection }
        .onChange(of: selection) { new in
            if new == Self.backTag {
                selection = last
                Sound.sfx("sfx-select")
                onBack()
                return
            }
            guard new != last else { return }
            last = new
            Sound.sfx("sfx-select")
            onSelect(new)
        }
    }
}
