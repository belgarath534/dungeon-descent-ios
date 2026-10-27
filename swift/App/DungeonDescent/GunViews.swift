import SwiftUI
import DungeonCore

/// The equipped gun's charge and reload, shared by every mode (_gunState).
/// It ticks once a second while reloading and says when the gun is ready.
@MainActor
final class GunBelt: ObservableObject {
    static let shared = GunBelt()

    @Published private(set) var state = GunState()
    @Published private(set) var reloadLeft = 0
    private var timer: Timer?

    func gun(_ store: GameStore) -> Gun? { Guns.equipped(store) }

    /// The gun button: charge (free), fire, or "still reloading".
    func pull(_ g: Gun) -> GunState.Step {
        var s = state
        let step = s.pull(g)
        state = s
        switch step {
        case .charged:
            Sound.sfx("sfx-gun-charge")
        case .fire:
            Sound.sfx("sfx-gun-shot")
            if state.reloadUntil > 0 { startReload() }
        case .reloading: break
        }
        return step
    }

    /// A kill drops the charge.
    func killed() {
        state.reset()
        reloadLeft = 0
        timer?.invalidate()
        timer = nil
    }

    private func startReload() {
        reloadLeft = state.reloading()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        reloadLeft = state.reloading()
        guard reloadLeft == 0 else { return }
        timer?.invalidate()
        timer = nil
        Sound.sfx("sfx-unlock")
        Feedback.announce("Gun ready. You can charge again.")
    }

    /// The button's text and VoiceOver label.
    func label(_ g: Gun) -> (text: String, spoken: String) {
        if reloadLeft > 0 { return ("🔫 Reloading... \(reloadLeft)s", "Gun reloading. \(reloadLeft) seconds remaining.") }
        if state.charged && state.shotsLeft > 0 {
            return ("🔫 Shoot" + (state.shotsLeft > 1 ? " (\(state.shotsLeft) shots left)" : ""), "Shoot \(g.name). \(state.shotsLeft) shot\(state.shotsLeft == 1 ? "" : "s") remaining.")
        }
        return ("🔫 Charge Gun", "Charge \(g.name) before shooting.")
    }
}

/// The gun button in a fight. `fire` is called for a shot.
struct GunButton: View {
    @ObservedObject var belt = GunBelt.shared
    let gun: Gun
    let fire: () -> Void

    var body: some View {
        let l = belt.label(gun)
        Button(l.text) {
            switch belt.pull(gun) {
            case .charged:
                Feedback.announce("\(gun.name) charged. Ready to fire — \(gun.shots) shot\(gun.shots == 1 ? "" : "s") available.")
            case .fire:
                fire()
            case .reloading(let s):
                Feedback.announce("Gun reloading. \(s) seconds remaining.")
            }
        }
        .buttonStyle(DungeonButtonStyle(kind: .skill))
        .accessibilityLabel(l.spoken)
    }
}

/// The Gun Workshop (Home: craft from parts) and the Blacksmith's gun shop
/// (buy with diamonds); both list your guns to equip.
struct GunWorkshop: View {
    enum Mode { case craft, buy }
    let mode: Mode
    let store: GameStore
    let wallet: Wallet
    @State private var tick = 0

    var body: some View {
        let parts = Guns.partCounts(store)
        let owned = Guns.owned(store)
        let equipped = Guns.equipped(store)
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .craft ? "🔫 Gun Workshop" : "🔫 Gun Shop").font(Theme.cinzel(12)).foregroundStyle(Theme.gold)
                .accessibilityAddTraits(.isHeader)
            Text("💎 Diamonds: \(wallet.diamonds)").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x88ddff))
            if mode == .craft {
                if Guns.parts.allSatisfy({ parts[$0.id, default: 0] == 0 }) {
                    Text("No parts yet. Defeat enemies in dungeons (8% drop chance) or dig in the Mine to find gun parts.")
                        .font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
                } else {
                    Text(Guns.parts.map { "\($0.icon) \($0.name): \(parts[$0.id, default: 0])" }.joined(separator: "   "))
                        .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xffaa00))
                }
            }
            Text("YOUR GUNS").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.textDim).padding(.top, 4)
            if owned.isEmpty {
                Text("No guns yet. Craft them at Home or buy them from the Blacksmith.").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
            }
            ForEach(owned, id: \.self) { id in
                if let g = Guns.gun(id) {
                    let on = equipped?.id == id
                    HStack {
                        Text("\(g.icon) \(g.name)\(on ? " ✓" : "")").font(Theme.cinzel(11)).foregroundStyle(on ? Color(hex: 0xff6622) : Color(hex: 0xffaa00))
                        Spacer()
                        Button(on ? "Unequip" : "Equip") {
                            Guns.equip(on ? nil : id, store: store)
                            Sound.sfx("sfx-confirm")
                            Feedback.announce(on ? "\(g.name) unequipped." : "\(g.name) equipped. A gun button will appear in combat.")
                            tick += 1
                        }
                        .buttonStyle(WebButtonStyle(kind: .ghost))
                        .accessibilityLabel(on ? "Unequip \(g.name)" : "Equip \(g.name). \(g.damage.lowerBound) to \(g.damage.upperBound) damage, \(g.shots) shot\(g.shots == 1 ? "" : "s"), \(g.cooldown) second reload")
                    }
                    .padding(8).overlay(Rectangle().stroke(on ? Color(hex: 0xff6622) : Color(hex: 0x333333)))
                }
            }
            Text(mode == .craft ? "CRAFT" : "BUY MORE GUNS").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.textDim).padding(.top, 6)
            ForEach(Guns.all.filter { !owned.contains($0.id) }, id: \.id) { g in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(g.icon) \(g.name)").font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0xffaa00))
                    Text(g.desc).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x888888))
                    Text("⚔ Damage: \(g.damage.lowerBound)-\(g.damage.upperBound)  |  🔫 Shots: \(g.shots)  |  ⏱ Reload: \(g.cooldown)s")
                        .font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0xaaaaaa))
                    if mode == .craft {
                        let need = g.partCounts.sorted { $0.key < $1.key }
                        Text(need.map { "\(Guns.part($0.key)?.icon ?? "🔩") \(Guns.part($0.key)?.name ?? $0.key) \(parts[$0.key, default: 0])/\($0.value)" }.joined(separator: " · "))
                            .font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x666666))
                        let can = Guns.canCraft(g, store: store)
                        Button(can ? "⚙️ Craft \(g.name)" : "Need more parts") { act(Guns.craft(g.id, store: store)) }
                            .buttonStyle(WebButtonStyle(kind: can ? .gold : .ghost)).disabled(!can)
                            .accessibilityLabel(can ? "Craft \(g.name)" : "Need more parts to craft \(g.name). " + need.map { "\(Guns.part($0.key)?.name ?? $0.key): have \(parts[$0.key, default: 0]), need \($0.value)" }.joined(separator: ". "))
                    } else {
                        let can = wallet.diamonds >= g.diamondCost
                        Button(can ? "💎 Buy — \(g.diamondCost) diamonds" : "💎 \(g.diamondCost) diamonds (need more)") { act(Guns.buy(g.id, wallet: wallet, store: store)) }
                            .buttonStyle(WebButtonStyle(kind: can ? .gold : .ghost)).disabled(!can)
                            .accessibilityLabel("\(g.name). Costs \(g.diamondCost) diamonds. " + (can ? "Press to buy." : "Cannot afford."))
                    }
                }
                .padding(10).background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
            }
            if mode == .buy && owned.isEmpty {
                Text("Earn diamonds by defeating dungeon bosses or digging in the Mine, or craft guns at Home from gun parts.")
                    .font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555))
            }
        }
        .id(tick)
    }

    private func act(_ msg: String) {
        Sound.sfx(msg.hasPrefix("You") && !msg.hasPrefix("You already") ? "sfx-unlock" : "sfx-select")
        Feedback.announce(msg)
        tick += 1
    }
}
