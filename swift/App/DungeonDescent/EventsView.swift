import SwiftUI
import DungeonCore

/// The web version's #screen-events: every seasonal and weekly event, the
/// one running now first in its own colors.
@MainActor
struct EventsView: View {
    var body: some View {
        let active = Events.active()
        WebScreen {
            ScreenHeader(title: "Seasonal Events")
            Text("Special events change the dungeon. Active events apply automatically when you play.")
                .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 12)
            VStack(spacing: 12) {
                ForEach(Events.list, id: \.id) { card($0, active: $0.id == active) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Events list")
        }
        .onAppear {
            let label = Events.current()?.label
            Feedback.announce("Seasonal Events. " + (label.map { "\($0) is active now." } ?? "No event is active right now."))
        }
    }

    private func dates(_ e: Events.ListEntry) -> String {
        guard e.id == "easter" else { return e.dates }
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let c = Events.easter(year)
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        guard let start = Calendar(identifier: .gregorian).date(from: c),
              let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: 2, to: start) else { return "" }
        return "Active: \(f.string(from: start)) — \(f.string(from: end))"
    }

    private func card(_ e: Events.ListEntry, active: Bool) -> some View {
        let days = active ? Events.daysLeft(e.id) : Events.daysUntil(e.id)
        let accent = Color(hex: e.id == "halloween" || e.id == "friday13" ? 0xff8833 : 0xcc9944)
        return VStack(alignment: .leading, spacing: 6) {
            if active { Text("✦ ACTIVE NOW").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Color(hex: 0x44ff88)) }
            Text(e.title).font(Theme.cinzel(14)).foregroundStyle(accent)
            Text(e.desc).font(Theme.crimson(13.5)).foregroundStyle(Theme.textSecondary)
            Text(e.bonuses).font(Theme.crimson(13, italic: true)).foregroundStyle(Color(hex: 0xa0d4a0))
            Text(dates(e)).font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
            Text(active ? "✦ \(days) days remaining" : "Next occurrence in \(days) days")
                .font(Theme.cinzel(10.4)).foregroundStyle(active ? Theme.gold : Theme.textDim)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel)
        .overlay(Rectangle().stroke(active ? accent : Theme.borderDim))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(e.title). " + (active ? "ACTIVE NOW. " : "Upcoming in \(days) days. ") + "\(e.desc) Bonuses: \(e.bonuses) \(dates(e))")
    }
}

/// The seasonal shop (#screen-seasonal-shop): spend the event's currency.
@MainActor
struct SeasonalShopView: View {
    @EnvironmentObject var game: GameModel
    @State private var bought: Set<String> = []
    @State private var coins = 0
    @State private var message = ""

    var body: some View {
        WebScreen {
            if let cur = Events.current()?.currency {
                ScreenHeader(title: cur.shop)
                Text("\(cur.icon) \(coins) \(cur.name)").font(Theme.cinzel(14)).foregroundStyle(Theme.gold)
                    .frame(maxWidth: .infinity).padding(.bottom, 10)
                    .accessibilityLabel("You have \(coins) \(cur.name).")
                VStack(spacing: 10) {
                    ForEach(Events.shop(cur.key), id: \.id) { row($0, cur) }
                }
                if !message.isEmpty {
                    Text(message).font(Theme.cinzel(12)).italic().foregroundStyle(Color(hex: 0xa0d4a0))
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 12)
                }
                Text("Earn \(cur.name) by defeating enemies during the event: 30% of kills drop one.")
                    .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim).padding(.top, 12)
            } else {
                ScreenHeader(title: "Seasonal Shop")
                Text("No seasonal shop available right now.").font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary)
            }
        }
        .onAppear {
            guard let cur = Events.current()?.currency else { Feedback.announce("No seasonal shop available right now."); return }
            coins = Events.currency(cur.key, store: game.store)
            Feedback.announce("\(cur.shop). You have \(coins) \(cur.name). \(Events.shop(cur.key).count) items available.")
        }
    }

    private func row(_ item: Events.ShopItem, _ cur: Events.Currency) -> some View {
        let soon = Events.comingSoon(item.id)
        let done = bought.contains(item.id)
        let afford = coins >= item.cost
        return Button { buy(item, cur) } label: {
            HStack(spacing: 14) {
                Text(item.icon).font(.system(size: 24))
                VStack(alignment: .leading, spacing: 3) {
                    Text(done ? "✅ Purchased!" : item.name).font(Theme.cinzel(13.5)).foregroundStyle(Theme.ashLight)
                    Text(soon ? "\(item.desc) This isn't in the Swift version yet. Coming soon." : item.desc)
                        .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text("\(item.cost)\(cur.icon)").font(Theme.cinzel(13)).foregroundStyle(Theme.gold).fixedSize()
            }
            .padding(.vertical, 14).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            .opacity(afford && !soon ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(done)
        .accessibilityLabel("\(item.name). \(item.desc). Cost: \(item.cost) \(cur.name)" + (soon ? ". Not in the Swift version yet." : afford ? "" : ". Cannot afford."))
    }

    private func buy(_ item: Events.ShopItem, _ cur: Events.Currency) {
        if Events.comingSoon(item.id) { Feedback.announce("\(item.name) isn't in the Swift version yet. Coming soon."); return }
        guard let msg = Events.buy(item, currency: cur.key, store: game.store, wallet: game.wallet) else {
            Feedback.announce("Not enough \(cur.name).")
            return
        }
        Sound.sfx("sfx-purchase")
        bought.insert(item.id)
        coins = Events.currency(cur.key, store: game.store)
        message = msg
        Feedback.announce(msg)
    }
}
