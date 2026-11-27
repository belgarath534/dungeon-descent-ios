import SwiftUI
import DungeonCore

/// 12.3: the Advent Calendar (js/37-advent.js). 25 doors, one a day in
/// December; missed doors stay open until the 31st.
struct AdventView: View {
    @EnvironmentObject var game: GameModel
    @State private var opened: [Int] = []
    @State private var last: String? = nil

    var body: some View {
        WebScreen {
            ScreenHeader(title: "🎄 Advent Calendar")
            Text("A door opens every day from December 1 to 25. Missed one? Open it any time until December 31.")
                .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).padding(.bottom, 8)
            if let last {
                Text(last).font(Theme.cinzel(12)).foregroundStyle(Theme.gold)
                    .multilineTextAlignment(.center).padding(.bottom, 8)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(Advent.days, id: \.day) { door($0) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Doors")
        }
        .onAppear {
            opened = Advent.opened(game.store)
            let ready = Advent.ready(game.store)
            Feedback.announce("Advent Calendar. " + (ready > 0 ? "\(ready) door\(ready == 1 ? "" : "s") ready to open." : "No doors ready right now."))
        }
    }

    private func door(_ p: Advent.Prize) -> some View {
        let isOpen = opened.contains(p.day)
        let can = Advent.canOpen(p.day, store: game.store)
        let label = "Door \(p.day)" + (isOpen ? ", opened: \(Advent.text(p))" : can ? ", ready to open" : ", opens December \(p.day)")
            + (p.day == 25 ? ". The Christmas door." : "")
        return Button {
            switch Advent.open(p.day, store: game.store, wallet: game.wallet) {
            case .opened(let line):
                Sound.sfx(p.day == 25 ? "sfx-ach-special" : "sfx-loot")
                Feedback.success()
                last = line
                Feedback.announce(line)
                opened = Advent.opened(game.store)
                game.objectWillChange.send()
            case .already(let line), .locked(let line):
                Feedback.announce(line)
            }
        } label: {
            VStack(spacing: 2) {
                Text(isOpen ? p.icon : can ? "🎁" : "🔒").font(.system(size: 22)).accessibilityHidden(true)
                Text("\(p.day)").font(Theme.cinzel(12))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(isOpen ? Color(hex: 0x9fdc9f) : can ? Theme.gold : Theme.textDim)
            .background(isOpen ? Color(hex: 0x16301a) : can ? Color(hex: 0x3a1010) : Color(hex: 0x111111))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isOpen ? Color(hex: 0x3a7a40) : can ? Theme.gold : Color(hex: 0x333333), lineWidth: can && !isOpen ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
