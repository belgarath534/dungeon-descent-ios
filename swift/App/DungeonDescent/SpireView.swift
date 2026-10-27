import SwiftUI
import DungeonCore

/// #screen-spire, #screen-spire-combat, #screen-spire-death and #screen-spire-victory.
@MainActor
struct SpireView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @StateObject private var holder = Holder()

    /// Makes the model once the game is available.
    @MainActor final class Holder: ObservableObject { @Published var model: SpireModel? }

    var body: some View {
        ZStack {
            WebBackground()
            if let m = holder.model { SpireScreens(model: m) }
        }
        .onAppear { if holder.model == nil { holder.model = SpireModel(game: game) } }
        .onDisappear { holder.model?.stopTimer() }
    }
}

@MainActor
private struct SpireScreens: View {
    @ObservedObject var model: SpireModel
    @EnvironmentObject var router: Router

    var body: some View {
        ZStack {
            switch model.stage {
            case .setup: setup
            case .climbing: climb
            case .dead: death
            case .won: victory
            }
            if let b = model.blacksmith { BlacksmithView(model: b) { model.closeBlacksmith() } }
        }
    }

    private func menu() {
        model.stopTimer()
        Sound.track("menu")
        router.goTo(.menu)
    }

    // MARK: Setup

    private var setup: some View {
        let best = Spire.bestFloor(model.game.store)
        return WebScreen {
            Button("← Main Menu") { menu() }.buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Return to main menu")
            VStack(spacing: 6) {
                Text("🗼").font(.system(size: 44)).accessibilityHidden(true)
                Text("The Spire").font(Theme.decorative(24)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
                Text("1800 floors. One final enemy at the top.").font(Theme.crimson(15, italic: true)).foregroundStyle(Theme.textSecondary)
                Text("Your progress is never lost. Death only sends you back one floor.")
                    .font(Theme.crimson(13)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            VStack(spacing: 6) {
                Text("YOUR HIGHEST FLOOR").font(Theme.cinzel(9.6)).tracking(2.6).foregroundStyle(Theme.goldDim)
                Text("\(best)").font(Theme.decorative(36)).foregroundStyle(Theme.gold)
                Text("Floor \(best) of 1800").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
                bar(Double(best) / Double(Spire.top), Theme.gold)
            }
            .padding(14).background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your highest floor: \(best) of 1800.")
            Text("Choose Your Champion").font(Theme.cinzel(12)).foregroundStyle(Theme.gold).padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
            if model.game.characters.isEmpty {
                Text("Create a character first to enter The Spire.").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0x555555))
            }
            ForEach(Array(model.game.characters.enumerated()), id: \.offset) { i, ch in
                let on = i == model.characterIndex
                Button {
                    model.characterIndex = i
                    Feedback.announce("\(ch.name) selected for The Spire.")
                } label: {
                    Text("\(ch.name) — \(ch.cls) (Lv \(ch.persistLevel ?? 1))").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(WebButtonStyle(kind: on ? .gold : .ghost))
                .accessibilityLabel("\(ch.name), \(ch.cls), Level \(ch.persistLevel ?? 1)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("⚡ Auto Mode").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0x44aa44))
                    Text("The Spire advances automatically. Requires Level 5 character. Blacksmith still accessible anytime.")
                        .font(Theme.crimson(12.5)).foregroundStyle(Theme.textDim)
                }
                .accessibilityHidden(true)
                Spacer()
                let locked = model.characterLevel < 5
                Button(locked ? "🔒 Lv5" : model.autoMode ? "ON" : "OFF") { model.toggleAuto() }
                    .font(Theme.cinzel(11.2))
                    .foregroundStyle(locked ? Color(hex: 0x555555) : model.autoMode ? Color(hex: 0x44ff44) : Color(hex: 0x44aa44))
                    .padding(.vertical, 8).padding(.horizontal, 14)
                    .overlay(Rectangle().stroke(locked ? Color(hex: 0x333333) : model.autoMode ? Color(hex: 0x44ff44) : Color(hex: 0x336633)))
                    .accessibilityLabel(locked ? "Auto Mode locked. Requires Level 5 character. Current level: \(model.characterLevel)."
                                        : model.autoMode ? "Auto mode on, press to disable" : "Auto mode off, press to enable")
            }
            .padding(12).background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim)).padding(.top, 10)
            Button("🗼 Enter The Spire") { model.start() }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity).padding(.top, 10)
                .accessibilityLabel("Enter The Spire")
            if !model.message.isEmpty {
                Text(model.message).font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xcc6666)).frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            Sound.track("spire")
            Feedback.announce("The Spire. Your highest floor: \(best). Choose your champion and enter. 1800 floors stand between you and The Time Eater.")
        }
    }

    // MARK: Climbing

    @ViewBuilder
    private var climb: some View {
        if let r = model.run {
            WebScreen {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🗼 The Spire").font(Theme.cinzel(12)).foregroundStyle(Theme.gold)
                        Text("Floor \(r.floor) of 1800").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("HP: \(r.hp)/\(r.maxHp)").font(Theme.cinzel(11.2)).foregroundStyle(Theme.blood)
                        Text("\(r.gold)g").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xffdd44))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Floor \(r.floor) of 1800. HP \(r.hp) of \(r.maxHp). Gold \(r.gold).")
                bar(Double(r.hp) / Double(max(1, r.maxHp)), Theme.blood).accessibilityHidden(true)
                if let e = r.enemy, !r.cleared {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(e.icon) \(e.name)\(e.isBoss ? " ⚡ BOSS" : "")").font(Theme.cinzel(13)).foregroundStyle(Color(hex: e.isBoss ? 0xffaa44 : 0xe0c080))
                        Text("HP: \(e.hp) / \(e.maxHp)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
                        bar(Double(e.hp) / Double(max(1, e.maxHp)), Color(hex: 0xcc4444))
                    }
                    .padding(14).background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Fighting \(e.name)\(e.isBoss ? ", boss" : ""). Enemy HP \(e.hp) of \(e.maxHp).")
                }
                if model.autoMode {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AUTO ADVANCING...").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Color(hex: 0x44aa44))
                        bar(model.autoProgress, Color(hex: 0x44aa44))
                    }
                    .accessibilityHidden(true)
                }
                if r.cleared {
                    Button("⬆ Next Floor") { model.next() }
                        .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                        .accessibilityLabel("Advance to next floor")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        Button("⚔ Attack") { model.act(.attack) }.buttonStyle(WebButtonStyle(kind: .red))
                            .accessibilityLabel("Attack the enemy")
                        Button("💥 Heavy") { model.act(.heavy) }.buttonStyle(WebButtonStyle(kind: .red))
                            .accessibilityLabel("Heavy strike, more damage but may miss")
                        Button("🛡 Defend") { model.act(.defend) }.buttonStyle(WebButtonStyle(kind: .ghost))
                            .accessibilityLabel("Defend and counterattack")
                        Button("🧪 Potion (\(r.potions))") { model.potion() }.buttonStyle(WebButtonStyle(kind: .ghost))
                            .accessibilityLabel("Use health potion, \(r.potions) left")
                        if let g = Guns.equipped(model.game.store) {
                            GunButton(gun: g) { model.shoot(g) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.log.prefix(40).enumerated()), id: \.offset) { _, l in
                        Text(l).font(Theme.crimson(13)).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12).background(Color.black.opacity(0.3)).overlay(Rectangle().stroke(Theme.borderDim))
                .accessibilityElement(children: .contain).accessibilityLabel("Combat log")
                HStack(spacing: 8) {
                    Button("⚒ Blacksmith") { model.openBlacksmith() }.buttonStyle(WebButtonStyle(kind: .ghost))
                        .accessibilityLabel("Open blacksmith")
                    Button("← Menu") { model.leave(); menu() }.buttonStyle(WebButtonStyle(kind: .ghost))
                        .accessibilityLabel("Return to main menu, progress is saved")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Death and victory

    private var death: some View {
        WebScreen {
            VStack(spacing: 12) {
                Text("💀").font(.system(size: 44)).accessibilityHidden(true)
                Text("You Have Fallen").font(Theme.decorative(22)).foregroundStyle(Theme.bloodBright).accessibilityAddTraits(.isHeader)
                Text("Fell on Floor \(model.run?.floor ?? 1)").font(Theme.cinzel(13)).foregroundStyle(Theme.textSecondary)
                Text(model.deathLine).font(Theme.crimson(15, italic: true)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
                Text("YOUR BEST FLOOR THIS ATTEMPT").font(Theme.cinzel(9.6)).tracking(2.6).foregroundStyle(Theme.goldDim)
                Text("Floor \(Spire.bestFloor(model.game.store))").font(Theme.cinzel(16)).foregroundStyle(Theme.gold)
                Button("🗼 Ascend Again") { model.start() }.buttonStyle(WebButtonStyle(kind: .gold))
                    .accessibilityLabel("Ascend again from your saved floor")
                Button("← Main Menu") { model.leave(); menu() }.buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Return to main menu")
            }
            .frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    private var victory: some View {
        WebScreen {
            VStack(spacing: 12) {
                Text("⏳").font(.system(size: 48)).accessibilityHidden(true)
                Text("The Time Eater Falls").font(Theme.decorative(22)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
                Text("You have climbed all 1800 floors. The thing at the top did not expect you.")
                    .font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                Text("It has consumed centuries of time. It did not consume you.")
                    .font(Theme.crimson(15, italic: true)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
                VStack(spacing: 4) {
                    Text("REWARD").font(Theme.cinzel(9.6)).tracking(2.6).foregroundStyle(Theme.goldDim)
                    Text("+1000 Gold · +25 Mystery Coins").font(Theme.cinzel(14)).foregroundStyle(Theme.gold)
                    Text("25% off at the Blacksmith for 2 hours.").font(Theme.crimson(13)).foregroundStyle(Theme.textDim)
                }
                .padding(14).overlay(Rectangle().stroke(Theme.goldDim))
                .accessibilityElement(children: .combine)
                Button("← Return from the Summit") { model.leave(); menu() }.buttonStyle(WebButtonStyle(kind: .gold))
                    .accessibilityLabel("Return to main menu")
            }
            .frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    private func bar(_ v: Double, _ c: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Color(hex: 0x111111)
                c.frame(width: g.size.width * CGFloat(max(0, min(1, v))))
            }
        }
        .frame(height: 6)
    }
}
