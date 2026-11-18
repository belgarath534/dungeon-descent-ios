import SwiftUI
import DungeonCore

/// #ov-offline-progress: "WELCOME BACK" after an hour or more away, with the
/// gold and Soul Fragments your character earned resting (OfflineRest).
struct OfflineRestOverlay: View {
    let reward: OfflineRest.Reward
    let close: () -> Void

    var body: some View {
        WebOverlay {
            Text("WELCOME BACK").font(Theme.cinzel(10.4)).tracking(3.2).foregroundStyle(Theme.goldDim)
            Text("\(reward.name) rested for \(reward.hoursText).")
                .font(Theme.cinzel(13)).foregroundStyle(Theme.gold)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 6) {
                Text("💰 +\(reward.gold) gold earned")
                Text("☠ ~\(reward.kills) enemies defeated")
                if reward.fragments > 0 { Text("✨ +\(reward.fragments) soul fragments") }
            }
            .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x888888))
            Button("Continue →", action: close)
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .accessibilityLabel("Continue")
        }
        .onAppear {
            Sound.sfx("sfx-unlock")
            Feedback.announce("Welcome back. \(reward.name) rested for \(reward.hoursText). You earned \(reward.gold) gold and \(reward.kills) kills while away."
                              + (reward.fragments > 0 ? " Plus \(reward.fragments) soul fragment\(reward.fragments == 1 ? "" : "s")." : ""))
        }
    }
}
