import SwiftUI
import UIKit

/// #loading-screen: "A Leo Productions Game", the title, the version, a gold
/// bar that fills in stages and a tip that changes every 2.5 seconds, for five
/// seconds at launch. VoiceOver hears the studio, "Loading" and the tips.
/// The game appears behind it only when it fades, so the menu's own music and
/// pop-ups start after it, as in the web version.
struct LoadingScreen: View {
    let done: () -> Void
    @State private var progress = 0.0
    @State private var tip = Int.random(in: 0..<LoadingScreen.tips.count)
    @State private var fading = false

    /// The web version's loading tips.
    static let tips = [
        "Tip: Equip weapons and armor from your inventory between runs.",
        "Tip: Soul Fragments drop from enemies. Collect 25 to build a custom spirit.",
        "Tip: The Wandering Merchant appears every few floors. Always check the sell tab.",
        "Tip: Elite enemies have a 30% chance to drop rare spirits on death.",
        "Tip: Legacy Mode carries your level between runs. Build one legend.",
        "Tip: Ambush Day hits 4 times a year — all battles become multi-enemy.",
        "Tip: The Void Anchor prevents fleeing. Kill it or die trying.",
        "Tip: Claim your Daily Descent reward every day to build your streak.",
        "Tip: The Last Blade starts at Level 10 but degrades each floor.",
        "Tip: Thornmail reflects 20% of damage back at attackers.",
    ]

    /// The screen tour and App Store screenshots go straight to the game.
    static var skipped: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-skipLoading") || args.contains("-startScreen")
    }

    private var version: String {
        "v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }

    var body: some View {
        ZStack {
            Color(hex: 0x080610).ignoresSafeArea()
            VStack(spacing: 0) {
                Text("A Leo Productions Game")
                    .font(Theme.cinzel(9.3)).tracking(3.2).textCase(.uppercase)
                    .foregroundStyle(Color(hex: 0x444444))
                    .padding(.bottom, 28)
                Text("Dungeon\nDescent")
                    .font(Theme.decorative(38)).multilineTextAlignment(.center)
                    .foregroundStyle(Theme.gold).shadow(color: Theme.gold.opacity(0.4), radius: 20)
                    .padding(.bottom, 6)
                Text("Into the dark. Again.")
                    .font(Theme.cinzel(12)).tracking(3.6).textCase(.uppercase)
                    .foregroundStyle(Theme.goldDim)
                    .padding(.bottom, 6)
                Text(verbatim: version)
                    .font(Theme.cinzel(9.3)).tracking(1.9).foregroundStyle(Color(hex: 0x333333))
                    .padding(.bottom, 40)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.gold.opacity(0.1))
                        Capsule().fill(Theme.goldDim).frame(width: g.size.width * progress)
                    }
                }
                .frame(width: 300, height: 3)
                Text(Self.tips[tip])
                    .font(Theme.cinzel(9.9).italic()).tracking(1)
                    .foregroundStyle(Color(hex: 0x444444)).multilineTextAlignment(.center)
                    .frame(minHeight: 20).padding(.top, 14)
                    .id(tip).transition(.opacity)
                Text("Created by Leo Productions · DDDI Certified")
                    .font(Theme.cinzel(8.8)).tracking(1.8).textCase(.uppercase)
                    .foregroundStyle(Color(hex: 0x2a2a2a))
                    .padding(.top, 48)
            }
            .frame(maxWidth: 380)
            .padding(40)
        }
        .opacity(fading ? 0 : 1)
        // One element for VoiceOver; the spoken lines below carry the tips.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Dungeon Descent")
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear(perform: run)
    }

    private func run() {
        func after(_ s: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }
        // The bar fills in stages, like the web version's.
        after(0.2) { withAnimation(.easeOut(duration: 1.8)) { progress = 0.30 } }
        after(1.5) { withAnimation(.easeOut(duration: 1.8)) { progress = 0.65 } }
        after(3.5) { withAnimation(.easeOut(duration: 1.8)) { progress = 0.90 } }
        after(4.5) { withAnimation(.easeOut(duration: 0.5)) { progress = 1 } }
        after(0.3) {
            Feedback.announce("Dungeon Descent. Created by Leo Productions. Loading.")
            Feedback.announce(Self.tips[tip])
        }
        after(2.8) {
            withAnimation { tip = (tip + 1) % Self.tips.count }
            Feedback.announce(Self.tips[tip])
        }
        after(5.0) { withAnimation(.easeOut(duration: 0.8)) { fading = true } }
        after(5.85) {
            done()
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
}
