import SwiftUI
import DungeonCore

/// #ov-blacksmith
@MainActor
struct BlacksmithView: View {
    @ObservedObject var model: BlacksmithModel
    let close: () -> Void
    @State private var tab = "upgrade"
    @State private var rarityGuide = false

    private let tabs: [(id: String, title: String, label: String)] = [
        ("upgrade", "⬆ Upgrade", "Upgrade tab"), ("shop", "⚔ Weapons", "Buy weapons tab"), ("armor", "🛡 Armor", "Buy armor tab"),
        ("sell", "💰 Sell", "Sell items tab"), ("inv", "🎒 Inventory", "Inventory tab"),
        ("reforge", "✨ Reforge", "Reforge tab — change weapon rarity"), ("guns", "🔫 Guns", "Guns tab — buy guns with diamonds"),
    ]

    private var f: Forge { model.forge }
    private var isSmith: Bool { f.prof == "Blacksmith" }

    var body: some View {
        ZStack {
            DungeonDialog(dim: 0.97, maxWidth: 520) {
                Button(model.fromMenu ? "← Back to Menu" : "← Back to Dungeon", action: close)
                    .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x888888))
                    .padding(.vertical, 6).padding(.horizontal, 10).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                    .accessibilityLabel(model.fromMenu ? "Close blacksmith and return to main menu" : "Close blacksmith")
                    .padding(.bottom, 12)
                Text("⚒ Blacksmith").font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
                Text("Forge, upgrade, and buy weapons.").font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textSecondary)
                Text("💰 Gold: \(f.gold)g").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xffdd44)).padding(.vertical, 8)
                FlowRow(spacing: 4) {
                    ForEach(tabs, id: \.id) { t in
                        Button(t.title) { select(t.id) }
                            .font(Theme.cinzel(9.9))
                            .foregroundStyle(tab == t.id ? Color(hex: 0xffaa00) : Color(hex: 0x888888))
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .background(tab == t.id ? Color(hex: 0x1a1000) : Color(hex: 0x0a0800))
                            .overlay(Rectangle().stroke(tab == t.id ? Color(hex: 0xffaa00) : Color(hex: 0x555555)))
                            .accessibilityLabel(t.label)
                            .accessibilityAddTraits(tab == t.id ? .isSelected : [])
                    }
                }
                .padding(.bottom, 14)
                Group {
                    switch tab {
                    case "upgrade": upgradeTab
                    case "shop": weaponsTab
                    case "armor": armorTab
                    case "sell": sellTab
                    case "inv": inventoryTab
                    case "reforge": reforgeTab
                    default: gunsTab
                    }
                }
                if !model.message.isEmpty {
                    Text(model.message).font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xa0d4a0))
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 12)
                }
            }
            if rarityGuide { guide }
        }
        .onAppear {
            Sound.track("blacksmith")
            Feedback.announce("Blacksmith. " + (isSmith ? "10% discount active. " : "")
                + "Upgrade to improve equipped gear. Weapons and Armor to buy gear. Gold available: \(f.gold).")
        }
    }

    private func select(_ id: String) {
        tab = id
        model.message = ""
        let said = ["upgrade": "Upgrade tab. Upgrade your equipped gear.", "shop": "Buy Weapons tab.",
                    "armor": "Armor tab. Buy armor to increase defense.", "sell": "Sell tab. Sell items from your inventory for gold.",
                    "inv": "Inventory tab. View your items and equip gear.", "reforge": "Reforge tab. Spend gold to reroll your weapon rarity.",
                    "guns": "Guns tab."]
        Feedback.announce(said[id] ?? "")
    }

    // MARK: Upgrade

    private var upgradeTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let w = f.weapon { gearCard(w, slot: .weapon) } else {
                empty("No weapon equipped. Buy a weapon from the Weapons tab and equip it from your inventory.")
            }
            if let a = f.armor { gearCard(a, slot: .armor) } else {
                empty("No armor equipped. Equip armor from your inventory first.")
            }
            if let w = f.weapon {
                let d = Blacksmith.durability(w)
                if d >= Blacksmith.maxDurability {
                    Text("✅ Weapon durability: Perfect (100/100)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x44cc44))
                } else {
                    Text("⚠ Durability: \(Blacksmith.durabilityLabel(d)) (\(d)/100)").font(Theme.cinzel(10.4))
                        .foregroundStyle(Color(hex: d >= 40 ? 0xccaa00 : d >= 20 ? 0xcc6600 : 0xcc2200))
                    let cost = Blacksmith.repairCost(w)
                    Button("🔧 Repair — \(cost)g") { model.repair() }
                        .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                        .accessibilityLabel("Repair weapon for \(cost) gold")
                }
            }
        }
    }

    private func gearCard(_ item: Item, slot: Blacksmith.Slot) -> some View {
        let lvl = item.level ?? 1
        let maxed = lvl >= Blacksmith.maxLevel
        let cost = Blacksmith.upgradeCost(level: lvl, prof: f.prof, store: model.game.store)
        let enchanter = Blacksmith.hasEnchanter(f)
        let can = !maxed && (f.gold >= cost || enchanter)
        let stat = slot == .weapon ? "ATK \(item.weaponAttack.lowerBound)-\(item.weaponAttack.upperBound)" : "DEF +\(item.armorDefense)"
        let color = slot == .weapon ? Theme.gold : Color(hex: 0x88aaff)
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(item.icon) \(item.name) — Level \(lvl)\(maxed ? "  MAX" : "")").font(Theme.cinzel(11.2)).foregroundStyle(color)
            Text("\(item.desc) \(stat)").font(Theme.crimson(12.5, italic: true)).foregroundStyle(Color(hex: 0x888888))
            HStack {
                Text(maxed ? "✦ Maximum Level Reached" : enchanter ? "🪄 Enchanter Active — Free Upgrade!"
                     : "Upgrade to Level \(lvl + 1) — \(cost)g\(isSmith ? " (10% off)" : "")")
                    .font(Theme.cinzel(10.9)).foregroundStyle(maxed ? Color(hex: 0x44ff88) : can ? Color(hex: 0xffdd44) : Color(hex: 0x666666))
                Spacer()
                if !maxed {
                    Button("⬆ Upgrade") { model.upgrade(slot) }
                        .font(Theme.cinzel(10.9)).foregroundStyle(can ? color : Color(hex: 0x444444))
                        .padding(.vertical, 6).padding(.horizontal, 14)
                        .overlay(Rectangle().stroke(can ? color : Color(hex: 0x333333)))
                        .disabled(!can)
                        .accessibilityLabel("Upgrade \(slot == .weapon ? "weapon" : "armor") to level \(lvl + 1) for \(enchanter ? "free with the Enchanter" : "\(cost) gold")")
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(slot == .weapon ? Color(hex: 0x3a2a1a) : Color(hex: 0x1a2a3a)))
        .accessibilityElement(children: .contain)
    }

    private func empty(_ t: String) -> some View {
        Text(t).font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x555555))
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).overlay(Rectangle().stroke(Color(hex: 0x1a1a1a)))
    }

    // MARK: Buying

    private var weaponsTab: some View {
        let d = Blacksmith.discount(model.game.store)
        let label = d.pct > 0 && isSmith ? " (10% Blacksmith + \(Int((d.pct * 100).rounded()))% \(d.source) discount!)"
            : isSmith ? " (10% Blacksmith discount)" : d.pct > 0 ? " (\(Int((d.pct * 100).rounded()))% \(d.source) discount!)" : ""
        return VStack(alignment: .leading, spacing: 8) {
            Text("💰 \(f.gold) gold available\(label)").font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0xffdd44))
            ForEach(Blacksmith.weapons, id: \.id) { w in
                let free = (w.cost ?? 0) == 0
                let claimed = free && Blacksmith.starterClaimed(model.game.store)
                let cost = Blacksmith.price(w, forge: f, store: model.game.store)
                let can = free ? !claimed : f.gold >= cost
                shopRow(w, extra: "(\(w.weaponAttack.lowerBound)-\(w.weaponAttack.upperBound) atk)\(free ? " [FREE]" : "")",
                        button: claimed ? "Claimed" : free ? "Claim Free" : "\(cost)g", enabled: can,
                        label: claimed ? "\(w.name) already claimed" : free ? "Claim free \(w.name)" : "Buy \(w.name) for \(cost) gold") {
                    model.buyWeapon(w)
                }
            }
        }
    }

    private var armorTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buy Armor — \(f.gold)g available").font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x888888))
            ForEach(Blacksmith.armors, id: \.id) { a in
                let owned = Blacksmith.owns(a, f)
                let cost = a.cost ?? 0
                shopRow(a, extra: "", button: owned ? "✅ Owned" : "\(cost)g", enabled: !owned && f.gold >= cost,
                        label: owned ? "\(a.name), already owned" : "Buy \(a.name) for \(cost) gold") { model.buyArmor(a) }
            }
        }
    }

    private func shopRow(_ item: Item, extra: String, button: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.icon) \(item.name)\((item.level ?? 1) > 1 ? " Lv\(item.level ?? 1)" : "") \(extra)")
                    .font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0xe0c080))
                Text(item.desc).font(Theme.crimson(12, italic: true)).foregroundStyle(Color(hex: 0x666666))
            }
            .accessibilityHidden(true)
            Spacer()
            Button(button, action: action)
                .font(Theme.cinzel(10.4)).foregroundStyle(enabled ? Color(hex: 0xffaa00) : Color(hex: 0x555555))
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(enabled ? Color(hex: 0x1a1000) : Color(hex: 0x0a0a0a))
                .overlay(Rectangle().stroke(enabled ? Color(hex: 0xffaa00) : Color(hex: 0x333333)))
                .disabled(!enabled)
                .accessibilityLabel("\(label). \(item.desc)")
        }
        .padding(12).background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x2a2010)))
    }

    // MARK: Sell and inventory

    private var sellTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if f.bag.isEmpty {
                empty("Inventory empty. Find items in dungeons or buy from the shop.")
            } else {
                Text("\(f.bag.count) items — tap to sell").font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x888888))
                ForEach(Array(f.bag.enumerated()), id: \.offset) { i, item in
                    let price = Inventory.sellPrice(item)
                    itemRow(item, button: "💰 \(price)g", label: "Sell \(item.name) for \(price) gold") { model.sell(i) }
                }
            }
        }
    }

    private var inventoryTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EQUIPPED").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
            ForEach([Blacksmith.Slot.weapon, .armor], id: \.self) { slot in
                if let item = slot == .weapon ? f.weapon : f.armor {
                    itemRow(item, button: "Unequip", label: "Unequip \(item.name)") { model.unequip(slot) }
                } else {
                    empty("No \(slot == .weapon ? "weapon" : "armor") equipped")
                }
            }
            Text("INVENTORY (\(f.bag.count) items)").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim).padding(.top, 6)
            if f.bag.isEmpty { empty("Inventory empty. Buy weapons and armor from the other tabs.") }
            ForEach(Array(f.bag.enumerated()), id: \.offset) { i, item in
                if item.isWeapon || item.isArmor {
                    itemRow(item, button: "Equip", label: "Equip \(item.name)") { model.equip(i) }
                } else {
                    itemRow(item, button: nil, label: "") {}
                }
            }
        }
    }

    private func itemRow(_ item: Item, button: String?, label: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text("\(item.icon) \(item.name)\((item.level ?? 1) > 1 ? " Lv\(item.level ?? 1)" : "")")
                .font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0xcc9944))
                .accessibilityLabel("\(item.name)\((item.level ?? 1) > 1 ? " Level \(item.level ?? 1)" : ""). \(item.desc)")
            Spacer()
            if let button {
                Button(button, action: action)
                    .font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0xffaa00))
                    .padding(.vertical, 4).padding(.horizontal, 10)
                    .background(Color(hex: 0x0a0a00)).overlay(Rectangle().stroke(Color(hex: 0xffaa00)))
                    .accessibilityLabel(label)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Color(hex: 0x0a0500)).overlay(Rectangle().stroke(Color(hex: 0x221100)))
    }

    // MARK: Reforge and guns

    private var reforgeTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("✨ Reforge").font(Theme.cinzel(12)).foregroundStyle(Theme.gold)
            Text("Spend gold to reroll your equipped weapon's rarity. Higher rarities have better stats and special effects. Results are random.")
                .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textSecondary)
            Button("📖 View All Rarity Effects") { rarityGuide = true; Feedback.announce("Rarity Effects Guide.") }
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("View every rarity effect for weapons and armor")
            if let w = f.weapon {
                let tier = Rarity.tiers[Blacksmith.rarityIndex(w)]
                Text("\(w.icon) \(w.name)").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xe0c080))
                Text("Current rarity: \(tier.symbol) \(tier.label)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x888888))
                let cost = Blacksmith.reforgeCost(w)
                Button("🎲 Reforge — \(cost)g (Random rarity)") { model.reforge() }
                    .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                    .accessibilityLabel("Reforge weapon for \(cost) gold — random new rarity")
                if let up = Blacksmith.rarityUpCost(w) {
                    let next = Rarity.tiers[Blacksmith.rarityIndex(w) + 1]
                    Button("⬆ Upgrade to \(next.label) — \(up)g") { model.raiseRarity() }
                        .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                        .accessibilityLabel("Upgrade to \(next.label) for \(up) gold")
                }
            } else {
                empty("No weapon equipped. Equip a weapon from the Inventory tab first.")
            }
        }
    }

    private var gunsTab: some View {
        GunWorkshop(mode: .buy, store: model.game.store, wallet: model.game.wallet)
    }

    private var guide: some View {
        DungeonDialog(dim: 0.97, maxWidth: 480) {
            Button("← Back to Reforge") { rarityGuide = false }.buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Close rarity guide")
            Text("📖 Rarity Effects").font(Theme.decorative(15)).foregroundStyle(Theme.gold).padding(.vertical, 8)
                .accessibilityAddTraits(.isHeader)
            Text("Every special effect a weapon or armor piece can roll, by tier. Reforging rerolls both the tier and, at Uncommon or above, a random effect from that tier.")
                .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textSecondary).padding(.bottom, 10)
            ForEach(Rarity.tiers.dropFirst(), id: \.id) { t in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(t.symbol) \(t.label)").font(Theme.cinzel(12.5)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
                    ForEach(Rarity.effects(for: t, weapon: true), id: \.id) { e in Text("⚔ \(e.name) — \(e.desc)") }
                    ForEach(Rarity.effects(for: t, weapon: false), id: \.id) { e in Text("🛡 \(e.name) — \(e.desc)") }
                }
                .font(Theme.crimson(12.5)).foregroundStyle(Color(hex: 0xdddddd))
                .padding(.bottom, 14)
            }
        }
    }
}

/// openMenuBlacksmith: the Blacksmith from the main menu, with global gold.
@MainActor
struct MenuBlacksmithScreen: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var model: BlacksmithModel?

    var body: some View {
        ZStack {
            WebBackground()
            if let model {
                BlacksmithView(model: model) {
                    Sound.track("menu")
                    router.goTo(.menu)
                }
            }
        }
        .onAppear { if model == nil { model = .menu(game) } }
    }
}
