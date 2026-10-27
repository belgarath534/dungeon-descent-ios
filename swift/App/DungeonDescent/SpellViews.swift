import SwiftUI
import DungeonCore

private func rarityColor(_ r: String) -> Color {
    r == "legendary" ? Color(hex: 0xffdd44) : r == "rare" ? Color(hex: 0xaa66ff) : Color(hex: 0x888888)
}

/// #as-items: every scroll and the Spell Book, bought with one tap.
struct ArcaneShopList: View {
    let gold: Int
    let status: String
    let learned: [String]
    let buy: (SpellEntry) -> String
    let openBook: () -> Void
    @State private var bought: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💰 \(gold) gold").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xffdd44))
            Text(status).font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0xaa66ff))
            Button("📖 View Spell Book", action: openBook)
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Open Spell Book — view your learned spells")
            ForEach(Spells.shop, id: \.id) { item in
                let known = item.spellId.map(learned.contains) ?? false
                let done = known || bought.contains(item.id)
                Button {
                    let msg = buy(item)
                    if !msg.hasPrefix("Not enough") && !msg.hasPrefix("You already") { bought.insert(item.id) }
                    Feedback.announce(msg)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text(item.icon).font(.system(size: 22)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.name)  [\(item.rarity.uppercased())]").font(Theme.cinzel(11.5)).foregroundStyle(rarityColor(item.rarity))
                            Text(item.desc).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x888888))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(known ? "✅ Known" : bought.contains(item.id) ? "✅ Bought" : "\(item.cost)g")
                            .font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xffdd44))
                    }
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(Color(hex: 0x0a0010))
                    .overlay(Rectangle().stroke(rarityColor(item.rarity)))
                    .opacity(done || gold < item.cost ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(known)
                .accessibilityLabel("\(item.name). \(item.desc) Cost \(item.cost) gold." + (known ? " Already learned." : "") + (gold < item.cost ? " Cannot afford." : ""))
            }
        }
    }
}

/// #spellbook-list
struct SpellBookList: View {
    let cls: String
    let hasBook: Bool
    let learned: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let n = learned.count
            Text(hasBook && !cls.isEmpty ? "📖 \(cls) · \(Int((Spells.learnChance(cls) * 100).rounded()))% learn chance · \(n) spell\(n == 1 ? "" : "s") learned"
                 : "\(cls) · No Spell Book owned · \(n) spell\(n == 1 ? "" : "s") learned")
                .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xaa66ff))
            if learned.isEmpty {
                Text("No spells learned yet.\n\nVisit the Arcane Shop to buy spell scrolls.")
                    .font(Theme.cinzel(11)).foregroundStyle(Theme.textDim).frame(maxWidth: .infinity).padding(.vertical, 30)
            }
            ForEach(learned, id: \.self) { id in
                if let s = Spells.entry(id) {
                    let powerful = Spells.powerful.contains(id)
                    HStack(alignment: .top, spacing: 12) {
                        Text(s.icon).font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(s.name)  [\(s.rarity.uppercased())]").font(Theme.cinzel(11.5)).foregroundStyle(rarityColor(s.rarity))
                            Text(s.desc).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x888888))
                            Text(powerful ? "⚡ Powerful — 6 turn cooldown" : "· 3 turn cooldown").font(Theme.cinzel(8.8)).foregroundStyle(Color(hex: 0x555555))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14).background(Color(hex: 0x0a0010)).overlay(Rectangle().stroke(rarityColor(s.rarity)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(s.name). \(s.desc) \(s.rarity). \(powerful ? "6-turn cooldown" : "3-turn cooldown").")
                }
            }
        }
    }
}

/// From the main menu: pick a character, then shop or read their book.
/// Gold is your saved gold; scrolls go to your saved items.
struct MenuSpellsScreen: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State var showingBook: Bool
    @State private var index = 0
    @State private var dice = SystemDice()
    @State private var tick = 0

    var body: some View {
        ZStack {
            WebBackground()
            WebScreen {
                Button("← Back") { Sound.sfx("sfx-select"); router.goTo(.menu) }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to main menu")
                Text(showingBook ? "📖 Spell Book" : "✨ Arcane Shop").font(Theme.decorative(22)).foregroundStyle(Color(hex: 0xcc88ff))
                    .accessibilityAddTraits(.isHeader)
                if game.characters.isEmpty {
                    Text("Create a character first.").font(Theme.cinzel(12)).foregroundStyle(Theme.textDim)
                } else {
                    Text("Character").font(Theme.cinzel(10)).foregroundStyle(Theme.goldDim)
                    ForEach(Array(game.characters.enumerated()), id: \.offset) { i, ch in
                        Button("\(ch.name) — \(ch.cls)") {
                            index = i
                            Feedback.announce("\(ch.name) selected.")
                        }
                        .buttonStyle(WebButtonStyle(kind: i == index ? .gold : .ghost))
                        .accessibilityAddTraits(i == index ? .isSelected : [])
                    }
                    let ch = game.characters[min(index, game.characters.count - 1)]
                    if showingBook {
                        Button("✨ Arcane Shop") { showingBook = false; Feedback.announce("Arcane Shop. \(Spells.shop.count) items. You have \(game.wallet.gold) gold.") }
                            .buttonStyle(WebButtonStyle(kind: .ghost))
                        SpellBookList(cls: ch.cls, hasBook: Spells.hasBook(ch), learned: Spells.learned(ch))
                    } else {
                        ArcaneShopList(gold: game.wallet.gold, status: status(ch), learned: Spells.learned(ch), buy: { buy($0) },
                                       openBook: { showingBook = true; Feedback.announce("Spell Book. \(Spells.learned(ch).count) spells learned.") })
                            .id(tick)
                    }
                }
            }
        }
        .onAppear {
            let ch = game.characters.first
            Feedback.announce(showingBook ? "Spell Book. \(ch.map { Spells.learned($0).count } ?? 0) spells learned."
                              : "Arcane Shop. \(Spells.shop.count) items. You have \(game.wallet.gold) gold.")
        }
    }

    private func status(_ ch: PlayerCharacter) -> String {
        Spells.hasBook(ch) ? "📖 Spell Book owned · \(Int((Spells.learnChance(ch.cls) * 100).rounded()))% learn chance as \(ch.cls)"
            : "No Spell Book — buy one to learn spells permanently"
    }

    private func buy(_ entry: SpellEntry) -> String {
        guard game.characters.indices.contains(index) else { return "" }
        var ch = game.characters[index]
        let (res, item) = Spells.buy(entry, character: &ch, gold: game.wallet.gold, subclass: nil, dice: &dice)
        switch res {
        case .tooPoor: Sound.sfx("sfx-select"); return "Not enough gold. Need \(entry.cost) gold."
        case .alreadyHaveBook: return "You already have a Spell Book."
        case .alreadyKnown: return "You already know \(entry.name)."
        default: break
        }
        _ = game.wallet.spendGold(entry.cost)
        if let item { game.globalInventory.add(item) }
        let saved = ch
        game.updateCharacter(index) { $0.extra["spellBook"] = saved.extra["spellBook"]; $0.extra["learnedSpells"] = saved.extra["learnedSpells"] }
        Sound.sfx("sfx-purchase")
        tick += 1
        switch res {
        case .book: return "Spell Book acquired."
        case .learned: return "\(entry.name) learned permanently! It is now in your spell book."
        case .failedToLearn: return "Failed to learn \(entry.name). The scroll dissolved."
        default: return "\(entry.name) added to your items. One time use in combat."
        }
    }
}

/// The Arcane Shop and Spell Book opened during a run.
struct RunSpellsOverlay: View {
    @ObservedObject var model: RunModel
    @State var showingBook: Bool
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button("← Back", action: close).buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to the dungeon")
                    Text(showingBook ? "📖 Spell Book" : "✨ Arcane Shop").font(Theme.decorative(22)).foregroundStyle(Color(hex: 0xcc88ff))
                        .accessibilityAddTraits(.isHeader)
                    let ch = model.character
                    if showingBook {
                        Button("✨ Arcane Shop") { showingBook = false }.buttonStyle(WebButtonStyle(kind: .ghost))
                        SpellBookList(cls: ch.cls, hasBook: Spells.hasBook(ch), learned: model.run.learnedSpells)
                    } else {
                        ArcaneShopList(gold: model.run.gold,
                                       status: Spells.hasBook(ch) ? "📖 Spell Book owned · \(Int((Spells.learnChance(ch.cls) * 100).rounded()))% learn chance as \(ch.cls)"
                                                                 : "No Spell Book — buy one to learn spells permanently",
                                       learned: model.run.learnedSpells, buy: { model.buySpell($0) },
                                       openBook: { showingBook = true; Feedback.announce("Spell Book. \(model.run.learnedSpells.count) spells learned.") })
                    }
                }
                .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            Feedback.announce(showingBook ? "Spell Book. \(model.run.learnedSpells.count) spells learned."
                              : "Arcane Shop. \(Spells.shop.count) items. You have \(model.run.gold) gold.")
        }
    }
}

/// #combat-spell-panel: choose a spell to cast.
struct CastSpellOverlay: View {
    @ObservedObject var model: RunModel
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 8) {
                    Text("✨ CAST A SPELL").font(Theme.cinzel(9.6)).tracking(3).foregroundStyle(Color(hex: 0xaa66ff))
                        .accessibilityAddTraits(.isHeader)
                    ForEach(model.run.learnedSpells, id: \.self) { id in
                        if let s = Spells.entry(id) {
                            let powerful = Spells.powerful.contains(id)
                            Button {
                                close()
                                model.castSpell(id)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(s.icon).font(.system(size: 22)).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.name + (powerful ? "  [POWERFUL — 6 turns]" : "  [3 turns]")).font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xcc88ff))
                                        Text(s.desc).font(Theme.cinzel(9.3)).foregroundStyle(Color(hex: 0x666666))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .multilineTextAlignment(.leading)
                                .padding(12).background(Color(hex: 0x0a0010)).overlay(Rectangle().stroke(Color(hex: 0xaa66ff)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cast \(s.name). \(s.desc)" + (powerful ? " Powerful, 6 turn cooldown." : " 3 turn cooldown."))
                        }
                    }
                    Button("Cancel", action: close).buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Cancel spell casting")
                }
                .padding(20).frame(maxWidth: 400).frame(maxWidth: .infinity)
            }
        }
        .accessibilityAddTraits(.isModal)
        .onAppear { Feedback.announce("Spell casting. \(model.run.learnedSpells.count) spells available. Choose one to cast.") }
    }
}
