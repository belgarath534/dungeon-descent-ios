import SwiftUI
import DungeonCore

/// The web version's #ov-home: buy a home, sleep in your bed, keep gold in
/// the safe, upgrade skills, and manage the minions you've captured.
@MainActor
struct HomeOverlay: View {
    @ObservedObject var model: RunModel
    @EnvironmentObject var game: GameModel
    @State private var tab = "home"
    @State private var buyMsg = ""
    @State private var bedMsg = ""
    @State private var safeDraft = ""
    @State private var safeMsg = ""
    @State private var skillMsg = ""
    @State private var minionMsg = ""
    @State private var forgeMsg = ""
    @State private var brewMsg = ""
    @State private var shopMsg = ""
    @State private var vendorMsg = ""
    /// Bumped after every change so the saved home is read again.
    @State private var refresh = 0

    private let tabs: [(id: String, title: String, label: String)] = [
        ("home", "🏠 HOME", "Home tab"), ("spirits", "✨ SPIRITS", "Spirits tab"), ("minions", "👾 MINIONS", "Minions tab"),
        ("forge", "🔨 FORGE", "Forge tab"), ("alchemy", "⚗️ ALCHEMY", "Alchemy tab"),
        ("elixirs", "🏪 VENDOR", "Elixir Vendor tab"), ("gunshop", "🔫 GUNS", "Gun Workshop tab"),
    ]

    var body: some View {
        ZStack {
            DungeonDialog(maxWidth: 520, background: Color(hex: 0x0a0806), border: Color(hex: 0x3a2a10), top: Color(hex: 0xcc9944)) {
                HStack {
                    Text("🏠 Your Home").font(Theme.decorative(14.4)).foregroundStyle(Color(hex: 0xcc9944))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("✕ Back") { model.closeHome() }
                        .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x888888))
                        .padding(.vertical, 6).padding(.horizontal, 10).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                        .accessibilityLabel("Close home and return to dungeon")
                }
                .padding(.bottom, 12)
                FlowRow(spacing: 4) {
                    ForEach(tabs, id: \.id) { t in
                        Button(t.title) { tab = t.id }
                            .font(Theme.cinzel(9.6)).tracking(1)
                            .foregroundStyle(tab == t.id ? Color(hex: 0xcc9944) : Color(hex: 0x555555))
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .background(tab == t.id ? Color(hex: 0x1a1206) : .clear)
                            .overlay(Rectangle().stroke(tab == t.id ? Color(hex: 0x664422) : Color(hex: 0x222222)))
                            .accessibilityLabel(t.label)
                            .accessibilityAddTraits(tab == t.id ? .isSelected : [])
                    }
                }
                .padding(.bottom, 14)
                Group {
                    switch tab {
                    case "home": homeTab
                    case "spirits": spiritsTab
                    case "minions": minionsTab
                    case "forge": forgeTab
                    case "alchemy": alchemyTab
                    case "elixirs": vendorTab
                    case "gunshop": GunWorkshop(mode: .craft, store: game.store, wallet: game.wallet)
                    default: comingSoon("The " + (tabs.first { $0.id == tab }?.label.replacingOccurrences(of: " tab", with: "") ?? ""))
                    }
                }
                .id(refresh)
            }
            if let d = model.dream { dreamModal(d) }
        }
    }

    private func refreshed() { refresh += 1 }

    // MARK: Home tab

    @ViewBuilder
    private var homeTab: some View {
        if !Home.owned(game.store) {
            VStack(spacing: 10) {
                Text("🏠").font(.system(size: 40)).accessibilityHidden(true)
                Text("Claim Your Home").font(Theme.decorative(14.4)).foregroundStyle(Color(hex: 0xcc9944))
                    .accessibilityAddTraits(.isHeader)
                Text("A small dwelling on the edge of the dungeon. A fire. A bed. A safe. Yours for 500 gold.")
                    .font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                Button("🏠 Buy Home — 500g") { buyMsg = model.buyHome(); refreshed() }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                    .accessibilityLabel("Buy your home for 500 gold")
                message(buyMsg, Color(hex: 0x666666))
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                bed
                safe
                skills
            }
        }
    }

    private var bed: some View {
        section("🛏 BED") {
            if !Home.hasBed(game.store) {
                note("You need a bed to sleep. Buy one for 75 gold.")
                Button("🛏 Buy Bed — 75g") { bedMsg = model.buyBed(); refreshed() }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                    .accessibilityLabel("Buy a bed for 75 gold")
                message(bedMsg, Color(hex: 0x555555))
            } else {
                let left = Home.roomsBeforeSleep(model.run, store: game.store)
                note(left == 0 ? "The bed is ready. Sleep to fully restore HP and SP."
                     : "Explore \(left) more rooms before resting again.")
                Button("😴 Sleep — Restore HP & SP") { model.sleep(); refreshed() }
                    .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x44aa44))
                    .frame(maxWidth: .infinity).padding(10)
                    .background(Color(hex: 0x080a08)).overlay(Rectangle().stroke(Color(hex: 0x1a2a1a)))
                    .opacity(left == 0 ? 1 : 0.4)
                    .disabled(left > 0)
                    .accessibilityLabel("Sleep to restore HP and SP")
            }
        }
    }

    private var safe: some View {
        section("🏦 THE SAFE") {
            (Text("Stored: ") + Text("\(Home.safe(game.store))g").bold().foregroundColor(Color(hex: 0xffaa44))
             + Text("  ·  On hand: ") + Text("\(game.wallet.gold)g").bold().foregroundColor(Color(hex: 0xffdd44)))
                .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x888888))
            HStack(spacing: 6) {
                TextField("Amount...", text: $safeDraft)
                    .keyboardType(.numberPad)
                    .font(Theme.cinzel(12)).foregroundStyle(.white)
                    .padding(8).background(Color(hex: 0x050505)).overlay(Rectangle().stroke(Color(hex: 0x2a2200)))
                    .accessibilityLabel("Gold amount")
                Button("Deposit") { safeMsg = model.deposit(Int(safeDraft) ?? 0); clearIfDone() }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                    .accessibilityLabel("Deposit gold into safe")
                Button("Withdraw") { safeMsg = model.withdraw(Int(safeDraft) ?? 0); clearIfDone() }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Withdraw gold from safe")
            }
            message(safeMsg, Color(hex: 0x888888))
        }
    }

    private func clearIfDone() {
        if safeMsg.hasPrefix("Deposited") || safeMsg.hasPrefix("Withdrew") { safeDraft = "" } else { Feedback.announce(safeMsg) }
        refreshed()
    }

    private var skills: some View {
        section("⬆️ SKILL UPGRADE") {
            note("Upgrade a skill up to level 5. Each level above 1 adds 10% to that skill's damage.")
            let list = Array(Skills.all(for: model.run.cls).prefix(8))
            let levels = Home.skillLevels(game.store)
            let cooldown = Home.skillCooldownLeft(game.store)
            if list.isEmpty { note("No upgradeable skills found.") }
            ForEach(list, id: \.effect) { s in
                let level = levels[Home.skillKey(cls: model.run.cls, name: s.name)] ?? 1
                let maxed = level >= Home.maxSkillLevel
                let cost = level * 80
                let can = !maxed && cooldown == 0 && game.wallet.gold >= cost
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(s.icon) \(s.name)").font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xaaaaaa))
                        Text("Lv \(level) / \(Home.maxSkillLevel)\(maxed ? " — MAXED" : "")").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555))
                    }
                    .accessibilityHidden(true)
                    Spacer()
                    Button(maxed ? "Maxed" : "\(cost)g ↑") { skillMsg = model.upgradeSkill(s.name); refreshed() }
                        .font(Theme.cinzel(9.9))
                        .foregroundStyle(can ? Color(hex: 0x44aaff) : Color(hex: 0x333333))
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(Color(hex: 0x050505)).overlay(Rectangle().stroke(can ? Color(hex: 0x44aaff) : Color(hex: 0x222222)))
                        .disabled(!can)
                        .accessibilityLabel("\(s.name) level \(level). " + (maxed ? "Maxed." : "Upgrade for \(cost) gold."))
                }
                .padding(8).background(Color(hex: 0x050505)).overlay(Rectangle().stroke(Color(hex: 0x111111)))
            }
            if cooldown > 0 {
                Text("⏳ Cooldown — \(Int((Double(cooldown) / 60).rounded(.up))) min remaining.")
                    .font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x555555)).frame(maxWidth: .infinity)
            }
            message(skillMsg, Color(hex: 0x44aaff))
            let orbs = Home.skillOrbs(game.store)
            if !orbs.isEmpty {
                Text("✨ SKILL ORBS").font(Theme.cinzel(11.2)).foregroundStyle(Theme.gold).padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)
                note("Upgraded skills left by fallen characters. Use one on a character of the same class.")
                ForEach(Array(orbs.enumerated()), id: \.offset) { i, o in
                    let mine = o.className == model.run.cls
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("✨ \(o.skillName) — Lv \(o.level)").font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xaaaaaa))
                            Text("\(o.className) · from \(o.fromChar)").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555))
                        }
                        .accessibilityHidden(true)
                        Spacer()
                        Button("Use") { skillMsg = model.useSkillOrb(at: i); refreshed() }
                            .font(Theme.cinzel(9.9))
                            .foregroundStyle(mine ? Color(hex: 0xcc88ff) : Color(hex: 0x333333))
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(Color(hex: 0x050505)).overlay(Rectangle().stroke(mine ? Color(hex: 0xcc88ff) : Color(hex: 0x222222)))
                            .accessibilityLabel("Skill Orb, \(o.skillName) level \(o.level), \(o.className), from \(o.fromChar). " + (mine ? "Use." : "Needs a \(o.className)."))
                    }
                    .padding(8).background(Color(hex: 0x050505)).overlay(Rectangle().stroke(Color(hex: 0x111111)))
                }
            }
        }
    }

    // MARK: Spirits and Minions tabs

    private var spiritsTab: some View {
        section("✨ SPIRIT FORGE") {
            note("Spirits are passive companions. They may assist you in battle, grant buffs, or whisper warnings. Create yours in the Spirit Forge.")
            comingSoon("The Spirit Forge")
        }
    }

    private var minionsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            note("Enemies you have captured. Activate one to fight alongside you.")
            let list = Home.minions(game.store)
            let active = Home.activeMinion(game.store)?.id
            if list.isEmpty {
                Text("No minions yet. Use a Soul Trap in combat to capture enemies.")
                    .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x444444))
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            ForEach(list) { m in
                let on = m.id == active
                HStack(spacing: 10) {
                    Text(m.icon).font(.system(size: 22)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(m.name).foregroundStyle(on ? Color(hex: 0x44ff88) : Color(hex: 0xaaaaaa))
                            if m.tier == "elite" {
                                Text("ELITE").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0xcc88ff))
                                    .padding(.horizontal, 5).overlay(Rectangle().stroke(Color(hex: 0x884499)))
                            }
                            if on { Text("[ACTIVE]").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x44aa44)) }
                        }
                        .font(Theme.cinzel(11.5))
                        Text("ATK: \(m.atk) per round").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(m.tier == "elite" ? "Elite " : "")\(m.name)\(on ? ", active" : ""). Attack \(m.atk) per round.")
                    Spacer()
                    Button(on ? "Deactivate" : "Activate") { minionMsg = model.toggleMinion(m); refreshed() }
                        .font(Theme.cinzel(9.9)).foregroundStyle(on ? Color(hex: 0x44ff88) : Color(hex: 0x888888))
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(on ? Color(hex: 0x0a1a0a) : Color(hex: 0x0a0a0a))
                        .overlay(Rectangle().stroke(on ? Color(hex: 0x44aa44) : Color(hex: 0x444444)))
                        .accessibilityLabel("\(on ? "Deactivate" : "Activate") \(m.name)")
                    Button("✕") { model.releaseMinion(m); refreshed() }
                        .font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x884444))
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .background(Color(hex: 0x0a0808)).overlay(Rectangle().stroke(Color(hex: 0x330000)))
                        .accessibilityLabel("Release \(m.name)")
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .background(on ? Color(hex: 0x0a1a0a) : Color(hex: 0x080808))
                .overlay(Rectangle().stroke(on ? Color(hex: 0x44aa44) : Color(hex: 0x222222)))
            }
            message(minionMsg, Color(hex: 0x44ff88))
            section("🪤 HOW TO CAPTURE") {
                note("Find a Soul Trap in chests or buy one from the shop. Use it during combat to capture the current enemy. Captured enemies become permanent minions. You can keep up to \(Home.maxMinions).")
            }
        }
    }

    // MARK: Forge tab

    private var forgeTab: some View {
        let stash = WeaponForge.stash(game.store)
        return VStack(alignment: .leading, spacing: 14) {
            note("Kill enemies to collect materials. Combine them into weapons with random special effects. Keep a weapon and it goes to your inventory and your stash.")
            section("📦 MATERIALS") {
                let have = WeaponForge.materials.filter { (stash[$0.id] ?? 0) > 0 }
                if have.isEmpty {
                    Text("None yet. Kill enemies to find materials.").font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x444444))
                } else {
                    FlowRow(spacing: 10) {
                        ForEach(have.indices, id: \.self) { i in
                            Text("\(have[i].icon) \(have[i].name) x\(stash[have[i].id] ?? 0)")
                                .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xaaaaaa))
                        }
                    }
                }
            }
            if let w = model.forged { forgeResult(w, scraps: stash["iron-scrap"] ?? 0) }
            section("⚒️ RECIPES") {
                ForEach(WeaponForge.recipes.indices, id: \.self) { i in
                    let r = WeaponForge.recipes[i]
                    let can = WeaponForge.canCraft(r, stash) && model.forged == nil
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.icon) \(r.name) — ATK \(r.atk.lowerBound)-\(r.atk.upperBound)")
                                .font(Theme.cinzel(11.2)).foregroundStyle(can ? Color(hex: 0x44ff88) : Color(hex: 0x888888))
                            Text(WeaponForge.needs(r)).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555))
                        }
                        .accessibilityHidden(true)
                        Spacer()
                        Button(can ? "Craft" : "Need mats") { forgeMsg = model.forgeCraft(r.id); refreshed() }
                            .font(Theme.cinzel(9.9)).foregroundStyle(can ? Color(hex: 0x44ff88) : Color(hex: 0x444444))
                            .padding(.vertical, 6).padding(.horizontal, 12)
                            .background(can ? Color(hex: 0x0a1a0a) : Color(hex: 0x0a0a0a))
                            .overlay(Rectangle().stroke(can ? Color(hex: 0x44aa44) : Color(hex: 0x333333)))
                            .disabled(!can)
                            .accessibilityLabel("Craft \(r.name). Attack \(r.atk.lowerBound) to \(r.atk.upperBound). Needs \(WeaponForge.needs(r))."
                                                + (model.forged != nil ? " Keep the weapon on the anvil first." : can ? "" : " Not enough materials."))
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(can ? Color(hex: 0x0a1a0a) : Color(hex: 0x080808))
                    .overlay(Rectangle().stroke(can ? Color(hex: 0x44aa44) : Color(hex: 0x222222)))
                }
            }
            message(forgeMsg, Color(hex: 0x44ff88))
            Text("Forged so far: \(WeaponForge.count(game.store))").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555))
        }
    }

    private func forgeResult(_ w: Item, scraps: Int) -> some View {
        let fx = w.forgeEffect.flatMap(WeaponForge.effect)
        let atk = w.weaponAttack
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(w.icon) \(w.name)").font(Theme.cinzel(12)).bold().foregroundStyle(Color(hex: 0xffdd44))
                .accessibilityAddTraits(.isHeader)
            Text("ATK: \(atk.lowerBound) – \(atk.upperBound)").font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xaaaaaa))
            if let fx {
                (Text("✨ Effect: ") + Text(fx.name).bold().foregroundColor(Color(hex: 0xaa88ff)) + Text(" — \(fx.desc)"))
                    .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x888888))
            }
            HStack(spacing: 8) {
                Button("✓ Keep") { forgeMsg = model.forgeKeep(); refreshed() }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                    .accessibilityLabel("Keep \(w.name)")
                Button("🎲 Reroll Effect (2 Iron Scrap)") { forgeMsg = model.forgeReroll(); refreshed() }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Reroll the special effect for 2 Iron Scraps. You have \(scraps).")
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x0a0a00)).overlay(Rectangle().stroke(Color(hex: 0x665500)))
        .accessibilityElement(children: .contain)
    }

    // MARK: Alchemy tab

    private var alchemyTab: some View {
        let stock = Alchemy.stock(game.store)
        let alch = model.run.cls == "Alchemist"
        return VStack(alignment: .leading, spacing: 14) {
            note(alch ? "⚗️ Alchemist detected. Full recipe access. Your potions are stronger than normal."
                      : "Craft potions from ingredients. As a non-Alchemist your results are weaker and some recipes are locked.")
            section("🌿 YOUR INGREDIENTS") {
                let have = Alchemy.ingredients.filter { (stock[$0.id] ?? 0) > 0 }
                Text(have.isEmpty ? "None yet. Buy from the shop or find them in dungeons."
                                  : have.map { "\($0.icon) \($0.name) ×\(stock[$0.id] ?? 0)" }.joined(separator: "  ·  "))
                    .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xaaaaaa)).fixedSize(horizontal: false, vertical: true)
            }
            if !brewMsg.isEmpty {
                Text(brewMsg).font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xcc88ff))
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x0a000a)).overlay(Rectangle().stroke(Color(hex: 0x663399)))
            }
            section("⚗️ RECIPES") {
                ForEach(Alchemy.recipes(alchemist: alch).indices, id: \.self) { i in
                    let r = Alchemy.recipes(alchemist: alch)[i]
                    let can = Alchemy.canCraft(r, stock)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(r.icon).font(.system(size: 18)).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name + (r.alchemistOnly ? " [ALCHEMIST ONLY]" : ""))
                                    .font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xcc88ff))
                                Text(r.desc).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x666666))
                            }
                        }
                        .accessibilityHidden(true)
                        FlowRow(spacing: 8) {
                            ForEach(r.ingredients.indices, id: \.self) { j in
                                let x = r.ingredients[j]
                                let ok = (stock[x.id] ?? 0) >= x.count
                                Text("\(Alchemy.ingredient(x.id)?.icon ?? "") \(Alchemy.ingredient(x.id)?.name ?? x.id) ×\(x.count)")
                                    .font(Theme.cinzel(9.6)).foregroundStyle(ok ? Color(hex: 0x44ff88) : Color(hex: 0xff4444))
                            }
                        }
                        .accessibilityHidden(true)
                        Button("Craft") { brewMsg = model.brew(r.id); refreshed() }
                            .font(Theme.cinzel(9.9)).foregroundStyle(can ? Color(hex: 0xcc88ff) : Color(hex: 0x444444))
                            .frame(maxWidth: .infinity).padding(6)
                            .background(can ? Color(hex: 0x1a001a) : Color(hex: 0x080808))
                            .overlay(Rectangle().stroke(can ? Color(hex: 0xcc88ff) : Color(hex: 0x333333)))
                            .disabled(!can)
                            .accessibilityLabel("Craft \(r.name)\(r.alchemistOnly ? ", Alchemist only" : ""). \(r.desc) Needs \(Alchemy.needs(r, stock)).")
                    }
                    .padding(10)
                    .background(Color(hex: 0x0a000a)).overlay(Rectangle().stroke(r.alchemistOnly ? Color(hex: 0x9944ff) : Color(hex: 0x2a002a)))
                }
            }
            section("🛒 INGREDIENT SHOP") {
                Text("Your gold: \(game.wallet.gold)g").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xffdd44))
                ForEach(Alchemy.ingredients.indices, id: \.self) { i in
                    let ing = Alchemy.ingredients[i]
                    HStack(spacing: 8) {
                        Text(ing.icon).font(.system(size: 17)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(ing.name) ×\(stock[ing.id] ?? 0)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xcc88ff))
                            Text(ing.desc).font(Theme.cinzel(9.3)).foregroundStyle(Color(hex: 0x555555))
                        }
                        .accessibilityHidden(true)
                        Spacer()
                        Button("\(ing.cost)g") { shopMsg = model.buyIngredient(ing.id); refreshed() }
                            .font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0xcc88ff))
                            .padding(.vertical, 4).padding(.horizontal, 10)
                            .background(Color(hex: 0x1a001a)).overlay(Rectangle().stroke(Color(hex: 0xcc88ff)))
                            .accessibilityLabel("Buy \(ing.name) for \(ing.cost) gold. You have \(stock[ing.id] ?? 0). \(ing.desc)")
                    }
                    .padding(6).background(Color(hex: 0x0a000a)).overlay(Rectangle().stroke(Color(hex: 0x2a002a)))
                }
                message(shopMsg, Color(hex: 0xcc88ff))
            }
        }
    }

    // MARK: Elixir Vendor tab

    private var vendorTab: some View {
        let daily = ElixirVendor.daily()
        let bought = ElixirVendor.boughtToday(game.store)
        let spares = ElixirVendor.spares(model.run)
        return VStack(alignment: .leading, spacing: 14) {
            note("The vendor buys spare elixirs and sells one special elixir a day.")
            section("🌟 TODAY'S ELIXIR") {
                HStack(spacing: 8) {
                    Text(daily.icon).font(.system(size: 22)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(daily.name).font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xffcc66))
                        Text(daily.desc).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x666666))
                    }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x0a000a)).overlay(Rectangle().stroke(Color(hex: 0x443300)))
                .accessibilityElement(children: .combine)
                Button(bought ? "✓ Bought Today" : "🛒 Buy — \(ElixirVendor.buyPrice)g") { vendorMsg = model.buyDailyElixir(); refreshed() }
                    .font(Theme.cinzel(9.9)).foregroundStyle(bought ? Color(hex: 0x444444) : Color(hex: 0xffcc66))
                    .frame(maxWidth: .infinity).padding(8)
                    .background(bought ? Color(hex: 0x080808) : Color(hex: 0x1a1000))
                    .overlay(Rectangle().stroke(bought ? Color(hex: 0x333333) : Color(hex: 0xffcc66)))
                    .disabled(bought)
                    .accessibilityLabel(bought ? "Already bought today's elixir. Come back tomorrow."
                                               : "Buy today's elixir, \(daily.name), for \(ElixirVendor.buyPrice) gold")
                message(vendorMsg, Color(hex: 0xffcc66))
            }
            section("💰 SELL ELIXIRS — \(ElixirVendor.sellPrice)g EACH") {
                if spares.isEmpty {
                    Text("No spare elixirs to sell. Find them on dungeon floors.").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x444444))
                }
                ForEach(spares.indices, id: \.self) { i in
                    let e = spares[i]
                    HStack(spacing: 8) {
                        Text(e.icon).font(.system(size: 17)).accessibilityHidden(true)
                        Text("\(e.name) ×\(e.count)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xffcc66))
                            .accessibilityHidden(true)
                        Spacer()
                        Button("Sell") { model.sellElixir(e.name); refreshed() }
                            .font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0xffcc66))
                            .padding(.vertical, 4).padding(.horizontal, 10)
                            .background(Color(hex: 0x1a1000)).overlay(Rectangle().stroke(Color(hex: 0xffcc66)))
                            .accessibilityLabel("Sell \(e.name) for \(ElixirVendor.sellPrice) gold. You have \(e.count).")
                    }
                    .padding(6).background(Color(hex: 0x0a000a)).overlay(Rectangle().stroke(Color(hex: 0x2a002a)))
                }
            }
        }
    }

    // MARK: Dream (#dream-modal)

    private func dreamModal(_ d: Home.Dream) -> some View {
        let color = Color(hex: d.type == "buff" ? 0xffdd44 : d.type == "lore" ? 0xaa88ff : 0xcc4444)
        return ZStack {
            Color(red: 0, green: 0, blue: 12 / 255).opacity(0.97).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 16) {
                Text(d.type == "buff" ? "✦ DREAM — BUFF" : d.type == "lore" ? "✦ DREAM — LORE" : "✦ DREAM — DARK")
                    .font(Theme.cinzel(8.8)).tracking(3.5).foregroundStyle(color.opacity(0.7))
                Text(d.icon).font(.system(size: 40)).accessibilityHidden(true)
                Text(d.title).font(Theme.decorative(16)).foregroundStyle(color).accessibilityAddTraits(.isHeader)
                Text(d.story).font(Theme.cinzel(12).italic()).foregroundStyle(Color(hex: 0xc0b090))
                    .multilineTextAlignment(.center).lineSpacing(8)
                Text(d.buff).font(Theme.cinzel(10.9)).foregroundStyle(color)
                    .padding(.vertical, 10).padding(.horizontal, 16).overlay(Rectangle().stroke(color)).opacity(0.85)
                Button("WAKE UP") { model.dream = nil; refreshed() }
                    .font(Theme.cinzel(11.2)).tracking(2.2).foregroundStyle(Color(hex: 0x888888))
                    .padding(.vertical, 12).padding(.horizontal, 28).overlay(Rectangle().stroke(Color(hex: 0x444444)))
                    .accessibilityLabel("Wake up and close the dream")
            }
            .frame(maxWidth: 380)
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Pieces

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Color(hex: 0xcc9944))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x080604)).overlay(Rectangle().stroke(Color(hex: 0x221a0a)))
    }

    private func note(_ t: String) -> some View {
        Text(t).font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x888888)).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func message(_ t: String, _ c: Color) -> some View {
        if !t.isEmpty { Text(t).font(Theme.cinzel(9.9)).foregroundStyle(c) }
    }

    private func comingSoon(_ what: String) -> some View {
        Text("\(what.isEmpty ? "This" : what) isn't in the Swift version yet. Coming soon.")
            .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x666666))
            .frame(maxWidth: .infinity).padding(.vertical, 20)
    }
}
