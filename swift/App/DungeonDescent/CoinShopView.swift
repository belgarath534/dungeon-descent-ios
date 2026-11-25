import SwiftUI
import DungeonCore

/// The web version's #screen-coinshop. The Watch Ad and Buy Coins boxes
/// (Android ads, in-app purchases) are left out.
@MainActor
struct CoinShopView: View {
    @EnvironmentObject var game: GameModel
    @State private var coins = 0
    @State private var owned: Set<String> = []
    @State private var message = ""
    @State private var ranks: [String: Int] = [:]

    var body: some View {
        WebScreen {
            ScreenHeader(title: "Mystery Coin Shop")
            HStack(spacing: 14) {
                Text("🪙").font(.system(size: 28)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(coins) Mystery Coin\(coins != 1 ? "s" : "")" as String)
                        .font(Theme.cinzel(14)).foregroundStyle(Theme.gold)
                    Text("Earned by completing daily raids. Permanent upgrades apply to all future runs.")
                        .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14).padding(.horizontal, 20)
            .background(Theme.bgPanel)
            .overlay(Rectangle().stroke(Theme.borderDim))
            .overlay(alignment: .leading) { Rectangle().fill(Theme.gold).frame(width: 3) }
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Your Mystery Coins: \(coins)." as String)

            // 12.2: Mastery, ranks that never run out.
            Text("MASTERY — RANKS THAT NEVER RUN OUT").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
                .accessibilityAddTraits(.isHeader).padding(.top, 4)
            Text("Each rank costs half again as much as the last.")
                .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textSecondary)
            VStack(spacing: 10) {
                ForEach(CoinShop.masteries) { masteryRow($0) }
            }
            Text("UPGRADES").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
                .accessibilityAddTraits(.isHeader).padding(.top, 10)
            VStack(spacing: 10) {
                ForEach(CoinShop.upgrades) { row($0) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Available upgrades")

            Text(message)
                .font(Theme.cinzel(12.5)).italic().foregroundStyle(Color(hex: 0xa0d4a0))
                .frame(maxWidth: .infinity, minHeight: 20).multilineTextAlignment(.center)
                .padding(.top, 12)
        }
        .onAppear {
            refresh()
            let available = CoinShop.upgrades.filter { !owned.contains($0.id) }.count
            Feedback.announce("Mystery Coin Shop. You have \(coins) coins. \(available) upgrades available.")
        }
    }

    private func refresh() {
        coins = CoinShop.coins(game.store)
        owned = CoinShop.owned(game.store)
        ranks = CoinShop.ranks(game.store)
    }

    private func masteryRow(_ m: CoinShop.Mastery) -> some View {
        let r = ranks[m.id] ?? 0, cost = CoinShop.rankCost(r), can = coins >= cost
        return Button {
            guard CoinShop.buyRank(m, store: game.store) else { Feedback.announce("Not enough Mystery Coins."); return }
            Sound.sfx("sfx-unlock")
            refresh()
            message = "\(m.name) rank \(r + 1)! \(m.perRank) more on every run."
            Feedback.announce(message)
        } label: {
            HStack(spacing: 16) {
                Text(m.icon).font(.system(size: 26))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(m.name) — Rank \(r)" as String).font(Theme.cinzel(14)).foregroundStyle(Theme.ashLight)
                    Text("\(m.perRank) a rank on every run. Now: \(r) rank\(r == 1 ? "" : "s")." as String)
                        .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Text("\(cost) 🪙" as String).font(Theme.cinzel(13)).foregroundStyle(Theme.gold).fixedSize()
            }
            .padding(.vertical, 18).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            .opacity(can ? 1 : 0.5).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!can)
        .accessibilityLabel("\(m.name), rank \(r). \(m.perRank) a rank on every run. Next rank costs \(cost) coins.\(can ? "" : " Not enough coins.")" as String)
    }

    @ViewBuilder
    private func row(_ u: CoinShop.Upgrade) -> some View {
        let isOwned = owned.contains(u.id)
        let canAfford = coins >= u.cost
        let label = u.name + ". " + u.desc + (isOwned ? " Already purchased."
            : " Cost: \(u.cost) coin\(u.cost != 1 ? "s" : "")." + (canAfford ? "" : " Not enough coins."))
        Button { buy(u) } label: {
            HStack(spacing: 16) {
                Text(u.icon).font(.system(size: 26))
                VStack(alignment: .leading, spacing: 3) {
                    Text(u.name).font(Theme.cinzel(14)).foregroundStyle(Theme.ashLight)
                    Text(u.desc).font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if isOwned {
                    Text("✦ Owned").font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0x7aaa7a))
                } else {
                    Text("\(u.cost) 🪙" as String).font(Theme.cinzel(13)).foregroundStyle(Theme.gold).fixedSize()
                }
            }
            .padding(.vertical, 18).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgPanel)
            .overlay(Rectangle().stroke(Theme.borderDim))
            .overlay(alignment: .leading) { if isOwned { Rectangle().fill(Theme.gold).frame(width: 3) } }
            .opacity(!isOwned && !canAfford ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOwned || !canAfford)
        .accessibilityLabel(label)
    }

    private func buy(_ u: CoinShop.Upgrade) {
        guard CoinShop.buy(u, store: game.store) else {
            Feedback.announce("Not enough Mystery Coins.")
            return
        }
        Sound.sfx("sfx-unlock")
        message = "\(u.name) purchased! \(u.desc)"
        refresh()
        Feedback.announce("\(u.name) purchased! \(u.desc)")
    }
}
