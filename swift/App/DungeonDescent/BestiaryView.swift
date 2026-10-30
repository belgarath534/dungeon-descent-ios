import SwiftUI
import DungeonCore

/// "The Bestiary", the web version's #screen-bestiary enemy tab.
@MainActor
struct BestiaryView: View {
    @EnvironmentObject var game: GameModel
    @State private var tab = "enemies"
    @State private var filter = "all"
    @State private var search = ""
    @State private var visible = 40

    struct Filter {
        let id: String
        let label: String
        let voice: String?
        init(_ id: String, _ label: String, _ voice: String?) { self.id = id; self.label = label; self.voice = voice }
    }

    static let filters: [Filter] = [
        Filter("all", "All", nil), Filter("crypt", "Crypt", nil), Filter("ash", "Ashbound", nil), Filter("frost", "Frosthold", nil),
        Filter("sunken", "Archives", nil), Filter("hollow", "Hollow", nil), Filter("nightmare", "Nightmare", nil), Filter("elite", "Elite", nil),
        Filter("mine", "⛏ Mine", nil), Filter("whisper", "🌲 Forest", "Show Whispering Forest enemies"),
        Filter("spire", "🗼 Spire", "Show The Spire enemies"), Filter("type-undead", "💀 Undead", "Show undead enemies"),
        Filter("type-beast", "🐺 Beast", "Show beast enemies"), Filter("type-demon", "😈 Demon", "Show demon enemies"),
        Filter("type-elemental", "⚡ Elemental", "Show elemental enemies"), Filter("type-spirit", "👻 Spirit", "Show spirit enemies"),
        Filter("infernal", "🔥 Infernal", "Show The Infernal enemies"), Filter("abyssal", "🌊 Abyssal", "Show The Abyssal Deep enemies"),
        Filter("shadow", "🌑 Shadow", "Show The Shadow World enemies"),
        Filter("special", "✨ Special", "Special enemies — Void Mode, Boss Rush, AFK, and seasonal"),
    ]

    private var filtered: [BestiaryData.Entry] {
        var list = BestiaryData.shared.entries
        if filter == "elite" { list = list.filter { $0.isElite == true } }
        else if filter.hasPrefix("type-") { list = list.filter { $0.enemyType == String(filter.dropFirst(5)) } }
        else if filter != "all" { list = list.filter { $0.dungeon == filter } }
        let q = search.lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) || $0.desc.lowercased().contains(q) || $0.tier.lowercased().contains(q) }
        }
        return list
    }

    var body: some View {
        let kills = game.bestiaryKills
        let list = filtered
        let revealed = list.filter { (kills[$0.id] ?? 0) > 0 }.count
        WebScreen {
            ScreenHeader(title: "The Bestiary")
            HStack(spacing: 0) {
                tabButton("enemies", "Enemies")
                tabButton("spirits", "Spirits")
                tabButton("community", "⚔ Community")
            }
            .overlay(Rectangle().stroke(Theme.borderDim))
            .padding(.bottom, 14)
            if tab == "spirits" {
                SpiritBestiary(characters: game.characters)
            } else if tab != "enemies" {
                Text("Community enemies aren't in the Swift version yet. Coming soon.")
                    .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
            } else {
                Text("A record of the creatures you have faced in the dark.").font(Theme.crimson(14.4, italic: true))
                    .foregroundStyle(Theme.textSecondary)
                (Text("Enemies revealed: ") + Text("\(revealed)").foregroundColor(Theme.gold) + Text(" of ")
                 + Text("\(list.count)").foregroundColor(Theme.gold))
                    .font(Theme.cinzel(10.9)).tracking(1).foregroundStyle(Theme.textDim)
                HStack(spacing: 6) {
                    TextField("", text: $search, prompt: Text("Search enemies...").foregroundColor(Theme.textDim))
                        .font(Theme.cinzel(12)).padding(10).background(Theme.bgStone).overlay(Rectangle().stroke(Theme.borderDim))
                        .accessibilityLabel("Search bestiary by enemy name")
                        .onChange(of: search) { _ in visible = 40 }
                    Button("✕") { search = "" }.font(Theme.cinzel(12)).foregroundStyle(Theme.ash)
                        .padding(10).overlay(Rectangle().stroke(Theme.borderDim))
                        .accessibilityLabel("Clear search")
                }
                FlowRow(spacing: 0) {
                    ForEach(Self.filters, id: \.id) { f in
                        let on = filter == f.id
                        Button {
                            filter = f.id
                            visible = 40
                        } label: {
                            Text(f.label).font(Theme.cinzel(10)).tracking(1).textCase(.uppercase)
                                .foregroundStyle(on ? Theme.gold : Theme.textDim)
                                .padding(.vertical, 8).padding(.horizontal, 9).frame(minHeight: 40)
                                .background(on ? Color(hex: 0x1e1a10) : Color(hex: 0x12100d))
                                .overlay(Rectangle().stroke(Theme.borderDim))
                        }
                        .accessibilityLabel(f.voice ?? f.label)
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Filter by dungeon")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(Array(list.prefix(visible).enumerated()), id: \.offset) { _, e in
                        card(e, kills: kills[e.id] ?? 0)
                    }
                }
                .padding(.top, 8)
                if list.count > visible {
                    let left = list.count - visible
                    Button("Load More (\(left) remaining)") { visible += 40 }
                        .buttonStyle(WebButtonStyle(kind: .ghost))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Load \(min(40, left)) more entries. \(left) remaining.")
                }
                if list.isEmpty {
                    Text("No enemies match.").font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textDim)
                }
            }
        }
        .onAppear {
            Feedback.announce("Bestiary. \(revealed) of \(list.count) enemies revealed.")
        }
    }

    private func tabButton(_ id: String, _ label: String) -> some View {
        let on = tab == id
        return Button { tab = id } label: {
            Text(label).font(Theme.cinzel(11.5)).tracking(1.7).textCase(.uppercase)
                .foregroundStyle(on ? Theme.gold : Theme.textDim)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Color(hex: 0x1e1a10) : Color(hex: 0x12100d))
                .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.gold).frame(height: 2) } }
        }
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func card(_ e: BestiaryData.Entry, kills: Int) -> some View {
        let revealed = kills > 0
        let nightmare = e.dungeon == "nightmare"
        let name = revealed ? e.name : nightmare ? "It has no name" : "Unknown Creature"
        let desc = revealed ? e.desc : nightmare
            ? "The dungeon refuses to speak of this. Face it in Nightmare Mode to reveal the truth." : "Venture deeper to reveal this entry."
        let edge: Color = e.isElite == true ? (revealed ? Theme.gold : Color(hex: 0x6a5a20))
            : nightmare ? Color(hex: 0x4a0a4a) : e.dungeon == "sunken" ? Color(hex: 0x2a4a7a)
            : revealed ? Theme.blood : Theme.borderDim
        let milestone = BestiaryData.shared.milestones[e.id]
        return VStack(alignment: .leading, spacing: 3) {
            Text(revealed ? e.icon : nightmare ? "🟣" : "❓").font(.system(size: 30)).opacity(revealed ? 1 : 0.4).padding(.bottom, 5)
            Text(name).font(Theme.cinzel(14, weight: .semibold))
                .foregroundStyle(nightmare && !revealed ? Color(hex: 0x7a207a) : revealed ? Theme.ashLight : Theme.textDim)
            Text(e.tier).font(Theme.cinzel(9.9)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.goldDim).padding(.bottom, 5)
            Text(desc).font(Theme.crimson(12.8, italic: revealed)).foregroundStyle(revealed ? Theme.textSecondary : Theme.textDim)
                .lineSpacing(2).padding(.bottom, 6)
            Text(revealed ? "Defeated: \(kills) time\(kills != 1 ? "s" : "")" : "Not yet encountered")
                .font(Theme.cinzel(10.9)).tracking(1).foregroundStyle(revealed ? Theme.bloodBright : Theme.textDim)
            if revealed, let m = milestone {
                Bar(value: Double(kills) / Double(max(m.kills, 1)), colors: [Theme.goldDim, Theme.gold], track: Theme.gold.opacity(0.1), height: 3)
                    .padding(.top, 4)
                Text((kills >= m.kills ? "✦ " : "") + m.reward + (kills >= m.kills ? "" : " (\(kills)/\(m.kills))"))
                    .font(Theme.cinzel(10.4)).foregroundStyle(Theme.goldDim)
                    .padding(.vertical, 4).padding(.horizontal, 8).overlay(Rectangle().stroke(Theme.borderDim))
                    .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel)
        .overlay(Rectangle().stroke(Theme.borderDim))
        .overlay(alignment: .leading) { Rectangle().fill(edge).frame(width: 3) }
        .overlay(alignment: .topTrailing) {
            if revealed && e.isBoss == true { badge("BOSS") } else if revealed && e.isElite == true { badge("★ ELITE") }
        }
        .opacity(revealed ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(revealed
            ? "\(e.name). \(e.tier). \(e.desc) Defeated \(kills) time\(kills != 1 ? "s" : "").\(milestone.map { " Milestone: \($0.reward) \(min(kills, $0.kills)) of \($0.kills)." } ?? "")"
            : "\(name). \(e.tier). \(desc)")
    }

    private func badge(_ t: String) -> some View {
        Text(t).font(Theme.cinzel(9.6)).tracking(0.8).foregroundStyle(Theme.gold)
            .padding(.vertical, 2).padding(.horizontal, 7)
            .background(Theme.gold.opacity(0.08)).overlay(Rectangle().stroke(Theme.goldDim))
            .padding(10)
    }
}

/// The Bestiary's Spirits tab (renderSpiritBestiary): every spirit, grouped by
/// rarity, unlocked once any of your characters has earned it.
struct SpiritBestiary: View {
    let characters: [PlayerCharacter]

    static let groups = [("starter", "Starter Spirits"), ("rare", "Rare Spirits — Dungeon Rewards"),
                         ("elite", "Elite Spirits — Elite Enemy Drops")]
    static let rareHints = ["bone-hound-prime": "Complete Crypt of Malachar", "inferno-hawk": "Complete Ashbound Wastes",
                            "glacial-wolf": "Complete Frosthold Abyss", "crystal-serpent": "Complete Frosthold Abyss",
                            "void-wraith": "Complete Nightmare Mode", "ash-phoenix": "Complete Ashbound Wastes",
                            "shadow-stalker": "Complete Crypt of Malachar"]

    private var earned: Set<String> {
        var s = Set<String>()
        for ch in characters {
            if case .array(let a)? = ch.extra["earnedSpirits"] {
                for v in a { if case .string(let id) = v { s.insert(id) } }
            }
        }
        return s
    }

    var body: some View {
        let got = earned
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.groups, id: \.0) { rarity, label in
                let list = Spirits.all.filter { $0.rarity == rarity }
                if !list.isEmpty {
                    Text(label).font(Theme.cinzel(10.9)).tracking(3).textCase(.uppercase).foregroundStyle(Theme.goldDim)
                        .padding(.top, 8).padding(.bottom, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderDim).frame(height: 1) }
                        .accessibilityAddTraits(.isHeader)
                    ForEach(list) { sp in card(sp, earned: rarity == "starter" || got.contains(sp.id)) }
                }
            }
        }
        .onAppear {
            let total = Spirits.all.filter { $0.rarity != "starter" }.count
            let n = Spirits.all.filter { $0.rarity != "starter" && got.contains($0.id) }.count
            Feedback.announce("Spirit Bestiary. \(n) of \(total) non-starter spirits earned across all characters.", after: 0.3)
        }
    }

    private func card(_ sp: Spirit, earned: Bool) -> some View {
        let hint = earned ? "" : sp.rarity == "rare" ? (Self.rareHints[sp.id] ?? "Complete a dungeon to unlock")
            : sp.rarity == "elite" ? "Defeat elite enemies for a chance to unlock" : ""
        let color = sp.rarity == "elite" ? Color(hex: 0xcc88ff) : sp.rarity == "rare" ? Theme.gold : Theme.ash
        return HStack(alignment: .top, spacing: 12) {
            Text(earned ? sp.icon : "🔒").font(.system(size: 26)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(sp.name).font(Theme.cinzel(13)).foregroundStyle(earned ? Theme.ashLight : Theme.textDim)
                Text(sp.rarity.uppercased() + (sp.rarity != "starter" ? " · LV \(sp.minLevel)+" : ""))
                    .font(Theme.cinzel(9.6)).tracking(1.5).foregroundStyle(color)
                Text(earned ? sp.desc : "???").font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textSecondary)
                if earned { Text("✦ " + sp.ability).font(Theme.cinzel(10.9)).foregroundStyle(Theme.gold) }
                if !hint.isEmpty { Text("🔒 " + hint).font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.bgPanel)
        .overlay(Rectangle().stroke(earned ? (sp.rarity == "elite" ? Color(hex: 0x6a3a8a) : Theme.goldDim) : Theme.borderDim))
        .opacity(earned ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sp.name). \(sp.rarity). " + (earned ? "\(sp.desc) Ability: \(sp.ability)" : "Locked. \(hint)"))
    }
}
