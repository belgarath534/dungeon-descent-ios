import SwiftUI
import DungeonCore

extension Item {
    /// WEAPON_RARITIES symbol and color for gear that rolled a rarity.
    var raritySymbol: String? {
        if case .string(let s)? = extra["raritySymbol"] { return s }
        return nil
    }

    var rarityColor: String? {
        guard case .string(let id)? = extra["rarity"] else { return nil }
        return ["common": "#888", "uncommon": "#44aa44", "rare": "#4488cc", "epic": "#aa44cc",
                "legendary": "#cc9944", "mythic": "#cc2222"][id]
    }
}

/// A dark full-screen overlay holding one box, read by VoiceOver as a dialog.
struct DungeonDialog<Content: View>: View {
    var dim = 0.92
    var maxWidth: CGFloat = 500
    var background = Color(hex: 0x0a0800)
    var border = Color(hex: 0x3a2a00)
    var top: Color = Theme.gold
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(dim).ignoresSafeArea().accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .padding(20)
                    .frame(maxWidth: maxWidth, alignment: .leading)
                    .background(background)
                    .overlay(Rectangle().stroke(border))
                    .overlay(alignment: .top) { Rectangle().fill(top).frame(height: 2) }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityAddTraits(.isModal)
        }
    }
}

// MARK: Shop (#ov-shop)

@MainActor
struct ShopOverlay: View {
    @ObservedObject var model: RunModel
    @State private var selling = false

    var body: some View {
        let run = model.run
        let night = model.hour >= 20 || model.hour < 8
        DungeonDialog {
            Text("⚗ The Wandering Merchant").font(Theme.decorative(15.2)).foregroundStyle(Theme.gold)
                .padding(.bottom, 2).accessibilityAddTraits(.isHeader)
            Text("A hooded figure crouches in the stairwell, wares spread on a ragged cloth.")
                .font(Theme.crimson(11.5, italic: true)).foregroundStyle(Color(hex: 0x555555)).padding(.bottom, 10)
            Text("💰 \(run.gold)g\(night ? "  🌙 Night Discount Active" : "")")
                .font(Theme.cinzel(12.8)).tracking(1.3).foregroundStyle(Color(hex: 0xffdd44))
                .padding(.vertical, 8).padding(.horizontal, 14)
                .background(Color(hex: 0x0d0a00)).overlay(Rectangle().stroke(Color(hex: 0x332200)))
                .padding(.bottom, 14)
                .accessibilityLabel("Your gold: \(run.gold).\(night ? " Night discount active." : "")")
            VStack(spacing: 8) {
                ForEach(model.shop) { entry in row(entry, gold: run.gold, night: night) }
            }
            .padding(.bottom, 14)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Items for sale")
            Button("💰 Sell Your Items") {
                Sound.sfx("sfx-select")
                selling.toggle()
                Feedback.announce(selling ? "Sell section opened. Swipe through your items to sell them." : "Sell section closed.")
            }
            .font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x888888))
            .padding(.vertical, 8).padding(.horizontal, 12).overlay(Rectangle().stroke(Color(hex: 0x333333)))
            .padding(.bottom, 12)
            .accessibilityLabel("Toggle sell your items section")
            if selling { sellList(model.run) }
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button("🔄 Refresh Items (\(Inventory.refreshCost)g)") { model.refreshShop() }
                        .buttonStyle(WebButtonStyle(kind: .ghost))
                        .accessibilityLabel("Refresh shop items for \(Inventory.refreshCost) gold — get a new set of items")
                    Button("Continue Descent ↓") { model.leaveShop() }
                        .buttonStyle(WebButtonStyle(kind: .ghost))
                        .accessibilityLabel("Leave the shop and continue descending")
                }
            }
        }
    }

    private func row(_ entry: Inventory.ShopItem, gold: Int, night: Bool) -> some View {
        let item = entry.item
        let price = model.price(entry)
        let afford = gold >= price
        return HStack(spacing: 12) {
            Text(item.icon).font(.system(size: 24)).frame(width: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.name).font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xccaa66))
                    if entry.sold { Text("[SOLD]").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555)) }
                }
                Text(item.desc).font(Theme.crimson(10.4, italic: true)).foregroundStyle(Color(hex: 0x555555)).lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(!entry.sold)
            VStack(alignment: .trailing, spacing: 5) {
                Group {
                    if entry.sold {
                        Text("—")
                    } else if night, let full = item.cost, full != price {
                        Text("\(full)g").strikethrough().foregroundColor(Color(hex: 0x555555)).font(Theme.cinzel(10.4))
                            + Text(" 🌙\(price)g").foregroundColor(Color(hex: 0x6ab0f0))
                    } else {
                        Text("\(price)g")
                    }
                }
                .font(Theme.cinzel(12.5, weight: .bold))
                .foregroundStyle(afford || entry.sold ? Theme.gold : Color(hex: 0xcc4444))
                .accessibilityHidden(true)
                if !entry.sold {
                    Button(afford ? "Buy" : "Too costly") { model.buy(entry.id) }
                        .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xcc9944))
                        .padding(.vertical, 5).padding(.horizontal, 12)
                        .background(Color(hex: 0x0d0900)).overlay(Rectangle().stroke(Color(hex: 0x886622)))
                        .opacity(afford ? 1 : 0.3)
                        .disabled(!afford)
                        .accessibilityLabel("\(item.name). \(item.desc). Cost: \(price) gold.\(afford ? " Press to buy." : " Cannot afford.")")
                }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Color(hex: 0x080600))
        .overlay(Rectangle().stroke(!entry.sold && !afford ? Color(hex: 0x330000) : Color(hex: 0x221800)))
        .opacity(entry.sold ? 0.3 : 1)
    }

    /// #shop-sell-list
    @ViewBuilder
    private func sellList(_ run: Run) -> some View {
        VStack(spacing: 0) {
            if run.inventory.isEmpty {
                Text("Nothing in inventory to sell.").font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x555555))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            ForEach(Array(run.inventory.enumerated()), id: \.offset) { i, item in
                let price = Inventory.sellPrice(item)
                HStack(spacing: 8) {
                    Text("\(item.icon) \(item.name)").font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xcc9944))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("\(price)g") { model.sell(at: i) }
                        .font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0xcc8844))
                        .padding(.vertical, 4).padding(.horizontal, 10)
                        .background(Color(hex: 0x1a0800)).overlay(Rectangle().stroke(Color(hex: 0xaa6622)))
                        .accessibilityLabel("Sell \(item.name) for \(price) gold")
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x1a1a00)).frame(height: 1) }
            }
        }
        .padding(.bottom, 12)
    }
}

// MARK: Level up (#ov-levelup) and skill choice (#skill-choice-overlay)

@MainActor
struct LevelUpOverlay: View {
    @ObservedObject var model: RunModel
    let level: Int

    var body: some View {
        let lp = model.run.levelPoints
        DungeonDialog(maxWidth: 420, background: Color(hex: 0x0a0a06), border: Theme.goldDim) {
            Text("⬆ Level \(level)!").font(Theme.decorative(22)).foregroundStyle(Theme.gold)
                .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
            Text("\(model.run.name) grows stronger. You have \(lp) Level Point\(lp != 1 ? "s" : "") to spend.")
                .font(Theme.crimson(14.4, italic: true)).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 10)
            (Text("ALLOCATE LEVEL POINTS — \(lp) remaining ") + Text("(unspent points carry over)").foregroundColor(Color(hex: 0x666666)))
                .font(Theme.cinzel(10.4)).tracking(1).foregroundStyle(Color(hex: 0xffaa44)).padding(.bottom, 8)
            VStack(spacing: 6) {
                ForEach(Progression.Stat.allCases, id: \.self) { stat in
                    Button {
                        if model.run.levelPoints <= 0 { Feedback.announce("No Level Points remaining."); return }
                        model.spend(stat)
                        Sound.sfx("sfx-confirm")
                    } label: {
                        HStack(spacing: 8) {
                            Text("\(Self.icon(stat)) \(stat.label)")
                            Text(stat.summary).font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x888888))
                            Spacer()
                        }
                        .font(Theme.cinzel(12)).foregroundStyle(lp > 0 ? Color(hex: 0xffaa44) : Color(hex: 0x555555))
                        .padding(.vertical, 8).padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(lp > 0 ? Color(hex: 0xffaa44) : Color(hex: 0x333333)))
                    }
                    .disabled(lp <= 0)
                    .accessibilityLabel("\(Self.icon(stat)) \(stat.label). \(stat.summary). Tap to spend 1 Level Point.")
                }
            }
            .padding(.bottom, 16)
            Button("Continue Descent") { model.continueAfterLevelUp() }
                .buttonStyle(WebButtonStyle(kind: .gold))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Continue your descent")
        }
    }

    static func icon(_ s: Progression.Stat) -> String {
        switch s {
        case .strength: return "⚔️"
        case .stamina: return "❤️"
        case .defense: return "🛡️"
        case .intelligence: return "🧠"
        case .agility: return "🏃"
        case .luck: return "🍀"
        }
    }
}

@MainActor
struct SkillChoiceOverlay: View {
    @ObservedObject var model: RunModel

    var body: some View {
        let run = model.run
        DungeonDialog(maxWidth: 520, background: Color(hex: 0x0a0a14), border: Theme.goldDim) {
            Text("✨ Choose Your Skill").font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            Text("Level \(run.level) reached. Choose one skill to unlock. The others are gone.")
                .font(Theme.crimson(13.6, italic: true)).foregroundStyle(Theme.textSecondary).lineSpacing(3).padding(.bottom, 20)
            VStack(spacing: 10) {
                ForEach(run.skillChoices, id: \.self) { effect in
                    if let s = Skills.skill(effect, cls: run.cls) {
                        Button { model.pickSkill(effect) } label: { card(s) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(s.name). \(s.tier). \(s.desc) Costs \(s.spCost) SP.")
                    }
                }
            }
        }
    }

    private func card(_ s: Skill) -> some View {
        let tierColor: Color = s.tier == "legendary" ? Theme.gold : s.tier == "rare" ? Color(hex: 0x4a80d0) : Theme.ash
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\(s.icon) \(s.name)").font(Theme.cinzel(14)).foregroundStyle(Theme.ashLight)
                Text(s.tier).font(Theme.cinzel(9.3)).tracking(0.8).textCase(.uppercase).foregroundStyle(tierColor)
                    .padding(.vertical, 2).padding(.horizontal, 7)
                    .overlay(Rectangle().stroke(s.tier == "legendary" ? Theme.goldDim : s.tier == "rare" ? Color(hex: 0x2a5090) : Theme.borderDim))
            }
            Text(s.desc).font(Theme.crimson(13)).foregroundStyle(Theme.textSecondary)
            Text("Cost: \(s.spCost) SP").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x7090c0))
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical, 14).padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(s.tier == "legendary" ? Theme.gold.opacity(0.04) : Theme.bgStone)
        .overlay(Rectangle().stroke(Theme.borderDim))
        .overlay(alignment: .leading) { Rectangle().fill(tierColor).frame(width: 3) }
    }
}

// MARK: Stats (#stats-overlay, showStats)

/// The character stats panel, from the dungeon or the character list.
struct StatsOverlay: View {
    let run: Run
    let deaths: [PlayerCharacter.Death]
    let close: () -> Void

    var body: some View {
        let skills = Skills.unlocked(run)
        let all = Skills.all(for: run.cls)
        let needed = run.level < run.levelCap ? "\(Progression.xpNeeded(atLevel: run.level))" : "MAX"
        DungeonDialog(maxWidth: 520, background: Color(hex: 0x0a0806), border: Theme.borderDim) {
            Text("📊 \(run.name)").font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)
            section("Character")
            grid(2, [("Class", "\(run.race) \(run.cls)"), ("Profession", run.prof),
                     ("Dungeon", run.dungeon.replacingOccurrences(of: "The ", with: "")), ("Difficulty", run.difficulty.rawValue)])
            section("Combat Stats")
            grid(3, [("Level", "Lv \(run.level)"), ("XP", "\(run.xp) / \(needed)"), ("Floor", "\(run.floor) / 10"),
                     ("HP", "\(run.hp) / \(run.maxHp)"), ("SP", "\(run.sp) / \(run.maxSp)"), ("Lives", "\(run.lives) / \(run.maxLives)"),
                     ("Attack", "\(run.atk.lowerBound + run.totalAtkBonus) — \(run.atk.upperBound + run.totalAtkBonus)"),
                     ("Defense", "\(run.totalDef)"), ("Gold", "\(run.gold)g")])
            section("Run Progress")
            grid(2, [("Enemies Slain", "\(run.kills)"), ("Potions Used", run.usedPotion ? "Yes" : "None yet"),
                     ("NG+", run.ngPlus ? "Active" : "No"), ("Daily Challenge", "None")])
            section("Unlocked Skills (\(skills.count) of \(all.count))")
            if skills.isEmpty {
                Text("No skills unlocked yet — level up to choose skills.").font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
            } else {
                VStack(spacing: 5) {
                    ForEach(skills, id: \.effect) { s in
                        HStack {
                            Text("\(s.icon) \(s.name) ") + Text(s.tier).font(Theme.cinzel(9.3)).foregroundColor(Theme.textDim)
                            Spacer()
                            Text("\(s.spCost) SP").foregroundStyle(Color(hex: 0x7090c0))
                        }
                        .font(Theme.cinzel(11.5)).foregroundStyle(Theme.ashLight)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.bottom, 8)
            }
            section("Inventory (\(run.inventory.count) items)")
            if run.inventory.isEmpty {
                Text("Empty satchel.").font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
            } else {
                FlowRow(spacing: 6) {
                    ForEach(Array(run.inventory.enumerated()), id: \.offset) { _, i in
                        Text("\(i.icon) \(i.name)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.ash)
                            .padding(.vertical, 4).padding(.horizontal, 10)
                            .background(Theme.bgStone).overlay(Rectangle().stroke(Theme.borderDim))
                    }
                }
                .padding(.bottom, 8)
            }
            if !deaths.isEmpty {
                section("Death Log")
                ForEach(Array(deaths.enumerated()), id: \.offset) { _, d in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("☠ Floor \(d.floor) · Lv \(d.level > 0 ? "\(d.level)" : "?") · \(d.date)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.bloodBright)
                        Text("Slain by \(d.killedBy) — \(d.kills) kills, \(d.gold)g\(d.bestDmg > 0 ? ", best hit: \(d.bestDmg)" : "")")
                            .font(Theme.crimson(12.5)).foregroundStyle(Theme.textSecondary)
                        Text(d.flavor).font(Theme.crimson(11.2, italic: true)).foregroundStyle(Theme.textDim)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }
            }
            Button("← Close") { close(); Feedback.announce("Stats closed.") }
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .accessibilityLabel("Close stats")
        }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(Theme.cinzel(10.4)).tracking(2.5).textCase(.uppercase).foregroundStyle(Theme.goldDim)
            .padding(.top, 10).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func grid(_ cols: Int, _ items: [(String, String)]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols), spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, kv in
                VStack(spacing: 2) {
                    Text(kv.1).font(Theme.cinzel(12.5)).foregroundStyle(Theme.ashLight).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    Text(kv.0).font(Theme.cinzel(8.8)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.textDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8).padding(.horizontal, 4)
                .background(Theme.bgDeep).overlay(Rectangle().stroke(Theme.borderDim))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(kv.0): \(kv.1)")
            }
        }
    }
}

// MARK: Death cinematic (#death-cinematic)

@MainActor
struct DeathCinematic: View {
    @ObservedObject var model: RunModel
    @State private var line = ""

    var body: some View {
        let r = model.run
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("\(r.dungeon.uppercased()) · FLOOR \(r.floor)").font(Theme.cinzel(10.4)).tracking(3.5)
                    .foregroundStyle(Color(hex: 0x664444))
                Text(line).font(Theme.crimson(20, italic: true)).foregroundStyle(Color(hex: 0xd4a0a0))
                    .multilineTextAlignment(.center).lineSpacing(5)
                Text("\(r.name) — \(r.race) \(r.cls)").font(Theme.cinzel(13)).foregroundStyle(Theme.ashLight)
                Text("Slain by \(model.killer) · \(r.kills) enemies defeated").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x666666))
                Text("· TAP TO CONTINUE ·").font(Theme.cinzel(8.8)).tracking(3.5).foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 32)
            }
            .padding(30)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to continue to run summary")
        .accessibilityAction { finish() }
        .onAppear {
            line = model.deathCinematicLine
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) { finish() }
        }
    }

    private func finish() {
        guard model.showingDeathCinematic else { return }
        withAnimation { model.showingDeathCinematic = false }
        Feedback.announce("Run ended. Return to menu when ready.")
    }
}

// MARK: Run summary (#screen-runsummary)

@MainActor
struct RunSummaryView: View {
    @ObservedObject var model: RunModel
    let victory: Bool
    @Binding var choosingPath: Bool
    @EnvironmentObject var router: Router

    var body: some View {
        let r = model.run
        let t = model.elapsed
        let time = "\(t / 60)m \(t % 60 < 10 ? "0" : "")\(t % 60)s"
        let skills = Skills.unlocked(r)
        ZStack {
            WebBackground()
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        Text(victory ? "👑" : "💀").font(.system(size: 52)).accessibilityHidden(true)
                        Text(r.dungeon.uppercased()).font(Theme.cinzel(11.2)).tracking(4).foregroundStyle(Theme.goldDim)
                        Text(victory ? "Dungeon Cleared" : "The Dark Claims You").font(Theme.decorative(26))
                            .foregroundStyle(victory ? Theme.gold : Theme.bloodBright)
                            .accessibilityAddTraits(.isHeader)
                        Text("\(r.name) · \(r.race) \(r.cls) · \(r.difficulty.rawValue)").font(Theme.cinzel(11.5)).foregroundStyle(Theme.ash)
                    }
                    .multilineTextAlignment(.center)
                    Text(victory ? UIText.shared.closingLine(dungeon: r.dungeon, cls: r.cls)
                         : "The dungeon claimed you on floor \(r.floor). It will not forget your name. Neither should you.")
                        .font(Theme.crimson(16, italic: true)).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center).lineSpacing(4)
                        .padding(.horizontal, 10)
                        .accessibilityLabel("Closing line: " + (victory ? UIText.shared.closingLine(dungeon: r.dungeon, cls: r.cls)
                                                                 : "The dungeon claimed you on floor \(r.floor). It will not forget your name. Neither should you."))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        stat("\(r.kills)", "Enemies Slain")
                        stat("Floor \(r.floor)", "Reached")
                        stat("Lv \(r.level)", "Level")
                        stat("\(r.gold)g", "Gold")
                        stat(time, "Time")
                        stat(victory ? "✓" : "✗", "Cleared")
                        if r.bestHit > 0 { stat("\(r.bestHit)", "Best Hit") }
                        if r.potionsUsed > 0 { stat("\(r.potionsUsed)", "Potions Used") }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Run statistics")
                    if !skills.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SKILLS USED THIS RUN").font(Theme.cinzel(10.4)).tracking(3).foregroundStyle(Theme.goldDim)
                            ForEach(skills, id: \.effect) { s in
                                HStack {
                                    Text("\(s.icon) \(s.name)").foregroundStyle(Theme.ashLight)
                                    Spacer()
                                    Text("\(s.tier) · \(s.spCost) SP").font(Theme.cinzel(11.5)).foregroundStyle(Theme.textDim)
                                }
                                .font(Theme.cinzel(12.5))
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.bgDeep).overlay(Rectangle().stroke(Theme.borderDim))
                    }
                    VStack(spacing: 10) {
                        if !model.characterGone {
                            Button("⚔ Play Again") { router.goTo(.dungeon(model.characterID, resume: false)) }
                                .buttonStyle(WebButtonStyle(kind: .gold))
                                .accessibilityLabel("Play again with this character")
                        }
                        if victory {
                            Button("⬆ Continue...") { choosingPath = true }
                                .buttonStyle(WebButtonStyle(kind: .gold))
                                .accessibilityLabel("Continue Journey to next dungeon or New Game Plus")
                        }
                        Button("← Character Select") { router.goTo(.charlist) }
                            .buttonStyle(WebButtonStyle(kind: .ghost))
                            .accessibilityLabel("Return to character selection")
                    }
                    .padding(.top, 6)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(Theme.cinzel(15, weight: .semibold)).foregroundStyle(Theme.gold).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.cinzel(8.8)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.bgDeep).overlay(Rectangle().stroke(Theme.borderDim))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(v)")
    }
}

/// Gambler's Spirit's choice (showChoiceModal).
@MainActor
struct GambleOverlay: View {
    @ObservedObject var model: RunModel

    var body: some View {
        let gold = model.run.gold
        DungeonDialog(maxWidth: 420) {
            Text("🎲 Gambler's Spirit — Choose Your Fate").font(Theme.decorative(15.2)).foregroundStyle(Theme.gold)
                .padding(.bottom, 8).accessibilityAddTraits(.isHeader)
            Text("Double your gold (\(gold) → \(gold * 2)g) or halve it (\(gold) → \(gold / 2)g). No refunds.")
                .font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary).padding(.bottom, 16)
            HStack(spacing: 10) {
                Button("Double (\(gold * 2)g)") { model.gamble(double: true) }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                Button("Halve (\(gold / 2)g)") { model.gamble(double: false) }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
            }
        }
        .onAppear { Feedback.announce("Gambler's Spirit. Double your gold to \(gold * 2), or halve it to \(gold / 2). No refunds.") }
    }
}

// MARK: Subclass (#ov-subclass)

@MainActor
struct SubclassOverlay: View {
    @ObservedObject var model: RunModel

    var body: some View {
        let run = model.run
        let options = Subclasses.options(for: run.cls)
        DungeonDialog(dim: 0.97, maxWidth: 480) {
            Text("Choose Your Subclass").font(Theme.decorative(16)).foregroundStyle(Theme.gold)
                .frame(maxWidth: .infinity).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
            Text("You are a \(run.cls). Your training diverges at level 5. This choice is permanent for this run.")
                .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x555555)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.bottom, 20)
            VStack(spacing: 12) {
                ForEach(options) { sub in
                    Button { model.chooseSubclass(sub.id) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Text(sub.icon).font(.system(size: 24))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sub.name).font(Theme.cinzel(12.8)).foregroundStyle(Theme.gold)
                                    Text(sub.passive).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x44aa44))
                                }
                            }
                            Text(sub.desc).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x888888)).lineSpacing(5)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0x080808)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(sub.name). \(sub.desc). Passive: \(sub.passive). Press to choose this subclass.")
                }
            }
        }
        .onAppear {
            if options.count >= 2 {
                Feedback.announce("Level 5 reached. Choose your subclass as a \(run.cls). Option 1: \(options[0].name). \(options[0].desc). Option 2: \(options[1].name). \(options[1].desc)")
            }
        }
    }
}
