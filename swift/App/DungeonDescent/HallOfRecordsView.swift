import SwiftUI
import DungeonCore

/// "Hall of Records", the web version's #screen-globalstats: lifetime
/// stats, milestone awards to claim, and the Hall of Legends.
@MainActor
struct HallOfRecordsView: View {
    @EnvironmentObject var game: GameModel
    @State private var tab = "stats"
    @State private var refresh = 0

    struct Award {
        let id, name, icon, desc, stat: String
        let target: Int
        let reward: String
        let coins: Int
        let effect: String?
    }

    /// GLOBAL_AWARDS
    static let awards: [Award] = [
        Award(id: "ga-kills-100", name: "Century Slayer", icon: "⚔️", desc: "Defeat 100 enemies total.", stat: "totalKills", target: 100, reward: "1 Mystery Coin", coins: 1, effect: nil),
        Award(id: "ga-kills-500", name: "Mass Exterminator", icon: "💀", desc: "Defeat 500 enemies total.", stat: "totalKills", target: 500, reward: "3 Mystery Coins", coins: 3, effect: nil),
        Award(id: "ga-runs-10", name: "Seasoned Descender", icon: "🏰", desc: "Complete 10 dungeon runs.", stat: "runsCompleted", target: 10, reward: "2 Mystery Coins", coins: 2, effect: nil),
        Award(id: "ga-runs-25", name: "Veteran Explorer", icon: "👑", desc: "Complete 25 dungeon runs.", stat: "runsCompleted", target: 25, reward: "5 Mystery Coins", coins: 5, effect: nil),
        Award(id: "ga-raids-5", name: "Raid Survivor", icon: "⚔️", desc: "Win 5 raids.", stat: "raidsWon", target: 5, reward: "2 Mystery Coins", coins: 2, effect: nil),
        Award(id: "ga-gold-1000", name: "Gilded Adventurer", icon: "💰", desc: "Earn 1000 total gold.", stat: "totalGold", target: 1000, reward: "+10 Max HP forever", coins: 0, effect: "hpUp"),
        Award(id: "ga-gold-5000", name: "Lord of Gold", icon: "🪙", desc: "Earn 5000 total gold.", stat: "totalGold", target: 5000, reward: "5 Mystery Coins", coins: 5, effect: nil),
        Award(id: "ga-deaths-10", name: "Stubborn Soul", icon: "💔", desc: "Die 10 times and keep coming back.", stat: "totalDeaths", target: 10, reward: "1 Mystery Coin", coins: 1, effect: nil),
        Award(id: "ga-deaths-50", name: "The Unkillable", icon: "🩸", desc: "Die 50 times total.", stat: "totalDeaths", target: 50, reward: "Second Wind free", coins: 0, effect: "secondWind"),
        Award(id: "ga-floors-50", name: "Deep Diver", icon: "🪜", desc: "Descend 50 floors total.", stat: "totalFloors", target: 50, reward: "1 Mystery Coin", coins: 1, effect: nil),
        Award(id: "ga-floors-100", name: "Abyss Walker", icon: "🌑", desc: "Descend 100 floors total.", stat: "totalFloors", target: 100, reward: "3 Mystery Coins", coins: 3, effect: nil),
        Award(id: "ga-crits-50", name: "Critical Eye", icon: "🎯", desc: "Land 50 critical hits.", stat: "totalCrits", target: 50, reward: "+2 Attack forever", coins: 0, effect: "atkUp"),
    ]

    private var stats: [String: Int] {
        game.achievements.globalStats.compactMapValues { if case .number(let n) = $0 { return Int(n) }; return nil }
    }

    private var claimed: [String] {
        guard let s = game.store.getItem("dd_claimed_awards"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return v
    }

    var body: some View {
        let _ = refresh
        WebScreen {
            ScreenHeader(title: "Hall of Records")
            HStack(spacing: 0) {
                tabButton("stats", "📊 Stats")
                tabButton("awards", "🏅 Milestones")
                tabButton("legends", "👑 Legends")
            }
            .overlay(Rectangle().stroke(Theme.borderDim))
            .padding(.bottom, 14)
            switch tab {
            case "stats": statsPanel
            case "awards": awardsPanel
            default: legendsPanel
            }
        }
        .onAppear {
            let s = stats
            let ready = Self.awards.filter { (s[$0.stat] ?? 0) >= $0.target && !claimed.contains($0.id) }.count
            Feedback.announce("Hall of Records. \(s["totalKills"] ?? 0) total kills. \(s["runsCompleted"] ?? 0) runs completed. "
                              + (ready > 0 ? "\(ready) award\(ready > 1 ? "s" : "") ready to claim!" : "No new awards ready."))
        }
    }

    private func tabButton(_ id: String, _ label: String) -> some View {
        let on = tab == id
        return Button {
            tab = id
            Feedback.announce(id == "stats" ? "Stats tab. Your lifetime statistics."
                              : id == "awards" ? "Milestones tab. Your earned milestone rewards." : "Hall of Legends. Your greatest moments preserved forever.")
        } label: {
            Text(label).font(Theme.cinzel(11)).tracking(1.5).textCase(.uppercase)
                .foregroundStyle(on ? Theme.gold : Theme.textDim).lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? Color(hex: 0x1e1a10) : Color(hex: 0x12100d))
                .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.gold).frame(height: 2) } }
        }
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Theme.cinzel(11.2)).tracking(3.4).textCase(.uppercase).foregroundStyle(Theme.goldDim)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.vertical, 18).padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.goldDim).frame(width: 3) }
    }

    private var statsPanel: some View {
        let s = stats
        let chars = game.characters
        var counts: [String: Int] = [:]
        for c in chars { counts[c.cls, default: 0] += 1 }
        let fav = counts.max { $0.value < $1.value }?.key ?? "None yet"
        let rows: [(String, String, Bool)] = [
            ("Total Kills", "\(s["totalKills"] ?? 0)", true), ("Total Gold", "\(s["totalGold"] ?? 0)g", false),
            ("Total Deaths", "\(s["totalDeaths"] ?? 0)", false), ("Floors Descended", "\(s["totalFloors"] ?? 0)", false),
            ("Runs Started", "\(s["runsStarted"] ?? 0)", false), ("Runs Completed", "\(s["runsCompleted"] ?? 0)", false),
            ("Raids Won", "\(s["raidsWon"] ?? 0)", false), ("Critical Hits", "\(s["totalCrits"] ?? 0)", false),
            ("Potions Drunk", "\(s["totalPotions"] ?? 0)", false), ("Best Floor", "\(s["bestFloor"] ?? 0)", false),
            ("Characters", "\(chars.count)", false), ("Fav Class", fav, false),
        ]
        return section("Lifetime Statistics") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.0).font(Theme.cinzel(9.3)).tracking(1.4).textCase(.uppercase).foregroundStyle(Theme.textDim)
                        Text(row.1).font(Theme.decorative(row.2 ? 22 : 17.6)).foregroundStyle(Theme.gold)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgStone).overlay(Rectangle().stroke(Theme.borderDim))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.0): \(row.1)")
                }
            }
        }
    }

    private var awardsPanel: some View {
        let s = stats
        let done = claimed
        return section("Milestone Awards") {
            ForEach(Self.awards, id: \.id) { a in
                let cur = s[a.stat] ?? 0
                let isClaimed = done.contains(a.id)
                let claimable = cur >= a.target && !isClaimed
                HStack(spacing: 14) {
                    Text(a.icon).font(.system(size: 22)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.name).font(Theme.cinzel(13.1)).foregroundStyle(Theme.ashLight)
                        Text(a.desc).font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textSecondary)
                        Text("\(cur) / \(a.target)\(isClaimed ? " — Reward: \(a.reward)" : "")").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
                        Bar(value: Double(cur) / Double(a.target), colors: [Theme.goldDim, Theme.goldDim], track: Theme.gold.opacity(0.1), height: 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(a.name). \(a.desc) Progress: \(cur) of \(a.target). \(isClaimed ? "Claimed." : claimable ? "Ready to claim! Reward: \(a.reward)." : "Reward: \(a.reward).")")
                    if claimable {
                        Button("✦ Claim") { claim(a) }
                            .buttonStyle(WebButtonStyle(kind: .gold))
                            .accessibilityLabel("Claim reward: \(a.reward)")
                    } else if isClaimed {
                        Text("✦ Claimed").font(Theme.cinzel(10.4)).tracking(1).foregroundStyle(Color(hex: 0x7aaa7a))
                    }
                }
                .padding(.vertical, 14).padding(.horizontal, 18)
                .background(claimable ? Theme.gold.opacity(0.05) : Theme.bgPanel)
                .overlay(Rectangle().stroke(claimable ? Theme.goldDim : Theme.borderDim))
                .opacity(isClaimed ? 0.45 : 1)
            }
        }
    }

    private func claim(_ a: Award) {
        var c = claimed
        guard !c.contains(a.id) else { return }
        c.append(a.id)
        game.setJSON("dd_claimed_awards", c)
        if a.coins > 0 { game.addMysteryCoins(a.coins) }
        if let e = a.effect { game.addMilestoneEffect(e) }
        Sound.sfx("sfx-unlock")
        Feedback.announce("Award claimed: \(a.name). Reward: \(a.reward)!")
        refresh += 1
    }

    private var legendsPanel: some View {
        let l = game.jsonObject("dd_legends")
        func o(_ k: String) -> [String: JSONValue]? { if case .object(let x)? = l[k] { return x }; return nil }
        func str(_ x: [String: JSONValue], _ k: String) -> String {
            switch x[k] { case .string(let s)?: return s; case .number(let n)?: return String(Int(n)); default: return "" }
        }
        var rows: [(String, String, String, String)] = []
        if let b = o("bestKills") {
            rows.append(("⚔️", "MOST ENEMIES IN ONE RUN", "\(str(b, "kills")) kills", "\(str(b, "name")) · \(str(b, "race")) \(str(b, "cls")) · \(str(b, "dungeon"))"))
        } else { rows.append(("⚔️", "MOST ENEMIES IN ONE RUN", "—", "Complete a run to set this record.")) }
        if let b = o("bestGold") {
            rows.append(("🪙", "MOST GOLD IN ONE RUN", "\(str(b, "gold"))g", "\(str(b, "name")) · \(str(b, "race")) \(str(b, "cls"))"))
        } else { rows.append(("🪙", "MOST GOLD IN ONE RUN", "—", "Complete a run to set this record.")) }
        if let b = o("deepestFloor") {
            rows.append(("🗺️", "DEEPEST FLOOR REACHED", "Floor \(str(b, "floor"))", "\(str(b, "name")) · \(str(b, "dungeon"))"))
        } else { rows.append(("🗺️", "DEEPEST FLOOR REACHED", "—", "Enter a dungeon to set this record.")) }
        if let b = o("bestDmg") {
            rows.append(("💥", "HIGHEST SINGLE HIT", "\(str(b, "dmg")) damage", "\(str(b, "name")) · \(str(b, "dungeon"))"))
        } else { rows.append(("💥", "HIGHEST SINGLE HIT", "—", "Deal damage in combat to set this record.")) }
        let fc = o("firstClears") ?? [:]
        var clears: [(String, String, String, String)] = []
        for d in GameData.dungeons {
            if case .object(let x)? = fc[d] {
                clears.append(("👑", d.uppercased(), str(x, "name"), "\(str(x, "race")) \(str(x, "cls")) · \(str(x, "date"))"))
            } else {
                clears.append(("🔒", d.uppercased(), "Not yet conquered", "Complete this dungeon to claim the first clear record."))
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("YOUR GREATEST MOMENTS — SAVED FOREVER").font(Theme.cinzel(10.4)).tracking(3).foregroundStyle(Theme.goldDim)
                .padding(.bottom, 6)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in legendRow(r) }
            Text("FIRST COMPLETIONS").font(Theme.cinzel(10.4)).tracking(3).foregroundStyle(Theme.goldDim)
                .padding(.top, 8).padding(.bottom, 2)
            ForEach(Array(clears.enumerated()), id: \.offset) { _, r in legendRow(r) }
        }
    }

    private func legendRow(_ r: (String, String, String, String)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(r.0) \(r.1)").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
            Text(r.2).font(Theme.decorative(17.6)).foregroundStyle(Theme.gold)
            if !r.3.isEmpty { Text(r.3).font(Theme.crimson(11.5)).foregroundStyle(Theme.textDim) }
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.goldDim).frame(width: 3) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.1.capitalized): \(r.2). \(r.3)")
    }
}
