import SwiftUI
import DungeonCore

/// #screen-siege (the fortress hub), #screen-siege-battle and #screen-siege-result.
struct SiegeView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var fortress = Siege.Fortress()
    @State private var charIndex = 0
    @State private var battle: Siege.Battle?
    @State private var log: [String] = []
    @State private var result: Siege.Battle?
    @State private var dice = SystemDice()
    private let gold = Color(hex: 0xcc9944)

    var body: some View {
        WebScreen {
            if let r = result { resultView(r) } else if let b = battle { battleView(b) } else { hub }
        }
        .onAppear { loadHub() }
    }

    private func loadHub() {
        fortress = Siege.load(game.store)
        Feedback.announce("The Siege. Your fortress is at level \(fortress.level). Base durability \(Int(fortress.durability)) percent. \(fortress.wavePoints) Wave Points. Choose your difficulty and character then begin.")
    }

    private func bar(_ value: Double, _ color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: 0x111111))
                Rectangle().fill(color).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 10).accessibilityHidden(true)
    }

    // MARK: Hub

    private var hub: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("← Menu") { Sound.track("menu"); router.goTo(.menu) }
                .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to main menu")
            Text("🏰 The Siege").font(Theme.decorative(22)).foregroundStyle(gold).accessibilityAddTraits(.isHeader)
            Text("Defend your fortress against 10 waves of enemies. Your base has durability — if it falls to zero you lose. Upgrade your base before battle. Earn Wave Points by dealing heavy damage.")
                .font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("🏰 Your Fortress").font(Theme.cinzel(12)).foregroundStyle(gold)
                row("Base Level", "\(fortress.level)")
                row("Durability", "\(Int(fortress.durability))%")
                bar(fortress.durability / 100, gold)
                row("Max Durability", "\(fortress.maxDurability)%")
                row("Wave Points", "\(fortress.wavePoints)")
                row("Stationed Minions", "\(fortress.stationed.count)")
                row("Extra Potions", "\(fortress.extraPotions)")
            }
            .padding(12).overlay(Rectangle().stroke(Color(hex: 0x443300)))
            .accessibilityElement(children: .combine)
            Text("BASE UPGRADES").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.textDim)
            ForEach(Siege.offered(fortress, minions: Home.minions(game.store)), id: \.id) { u in
                let can = game.wallet.gold >= u.gold && fortress.wavePoints >= u.wavePoints
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(u.icon) \(u.name)").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xffdd44))
                        Text(u.desc).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x666666))
                    }
                    Spacer()
                    Button("\(u.gold)g" + (u.wavePoints > 0 ? " + \(u.wavePoints) WP" : "")) { buy(u.id) }
                        .buttonStyle(WebButtonStyle(kind: can ? .gold : .ghost))
                        .accessibilityLabel("\(u.name). \(u.desc) Cost: \(u.gold) gold" + (u.wavePoints > 0 ? " and \(u.wavePoints) Wave Points." : ".") + (can ? "" : " Cannot afford."))
                }
                .padding(8).overlay(Rectangle().stroke(Color(hex: 0x222222)))
            }
            Text("DIFFICULTY").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.textDim)
            HStack(spacing: 6) {
                ForEach(Siege.Difficulty.allCases, id: \.self) { d in
                    Button(d.rawValue.capitalized) {
                        fortress.difficulty = d
                        Siege.save(fortress, store: game.store)
                        Feedback.announce("Difficulty set to \(d.rawValue). \(d.blurb)")
                    }
                    .buttonStyle(WebButtonStyle(kind: fortress.difficulty == d ? .gold : .ghost))
                    .accessibilityLabel("\(d.rawValue.capitalized) difficulty — \(d.blurb)")
                    .accessibilityAddTraits(fortress.difficulty == d ? .isSelected : [])
                }
            }
            Text("SELECT CHARACTER").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.textDim)
            if game.characters.isEmpty {
                Text("No characters available. Create a character first.").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x555555))
            }
            ForEach(Array(game.characters.enumerated()), id: \.offset) { i, c in
                Button((i == charIndex ? "► " : "") + "\(c.name) — \(c.cls) Lv.\(c.persistLevel ?? 1)") {
                    charIndex = i
                    Feedback.announce("\(c.name) selected for The Siege.")
                }
                .buttonStyle(WebButtonStyle(kind: i == charIndex ? .gold : .ghost))
                .accessibilityLabel("\(c.name), \(c.cls), level \(c.persistLevel ?? 1)")
                .accessibilityAddTraits(i == charIndex ? .isSelected : [])
            }
            Button("⚔️ Begin The Siege") { start() }
                .buttonStyle(WebButtonStyle(kind: .red)).disabled(game.characters.isEmpty)
                .accessibilityLabel("Start The Siege — begin wave 1")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Theme.textDim); Spacer(); Text(v).foregroundStyle(Color(hex: 0xffdd44)) }
            .font(Theme.cinzel(10.4))
    }

    private func buy(_ id: String) {
        guard let u = Siege.upgrades.first(where: { $0.id == id }) else { return }
        let out = Siege.buy(id, &fortress, gold: game.wallet.gold, minions: Home.minions(game.store))
        if out.ok {
            _ = game.wallet.spendGold(u.gold)
            Siege.save(fortress, store: game.store)
            Sound.sfx("sfx-purchase")
        } else {
            Sound.sfx("sfx-select")
        }
        Feedback.announce(out.message)
    }

    private func start() {
        guard game.characters.indices.contains(charIndex) else { return }
        var b = Siege.start(game.characters[charIndex], fortress: fortress)
        // Stocked potions go into this battle.
        b.fortress.extraPotions = 0
        battle = b
        log = ["Wave 1 of \(Siege.maxWaves): \(b.enemy.name) approaches!",
               "Enemy HP: \(b.enemy.hp) | ATK: \(b.enemy.atk.lowerBound)-\(b.enemy.atk.upperBound) | DEF: \(b.enemy.def)"]
        Sound.track("void-reaper")
        Feedback.announce("Wave 1. \(b.enemy.name) approaches. HP: \(b.enemy.hp). Your HP: \(b.hp). \(b.potions) potions.")
    }

    // MARK: Battle

    private func battleView(_ b: Siege.Battle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Wave \(b.wave) / \(Siege.maxWaves)")
                Spacer()
                Text("Gold: \(b.gold)")
                Spacer()
                Text("WP: \(b.fortress.wavePoints)")
            }
            .font(Theme.cinzel(10.4)).foregroundStyle(gold)
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 4) {
                Text("🏰 Base Durability: \(Int(b.fortress.durability))%" + (b.baseUnderAttack ? "  ⚠️ BASE UNDER ATTACK" : ""))
                    .font(Theme.cinzel(10.4)).foregroundStyle(b.baseUnderAttack ? Color(hex: 0xff6644) : Theme.textSecondary)
                bar(b.fortress.durability / 100, b.fortress.durability < 25 ? Color(hex: 0xcc4444) : gold)
                Text("❤️ \(b.name): \(b.hp) / \(b.maxHp)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textSecondary)
                bar(Double(b.hp) / Double(b.maxHp), Color(hex: 0x44aa44))
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 4) {
                Text("WAVE \(b.wave) ENEMY").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.textDim)
                Text(b.enemy.name).font(Theme.cinzel(13)).foregroundStyle(Color(hex: 0xff6644))
                Text("❤️ \(b.enemy.hp) / \(b.enemy.maxHp)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textSecondary)
                bar(Double(b.enemy.hp) / Double(b.enemy.maxHp), Color(hex: 0xcc3322))
            }
            .padding(10).overlay(Rectangle().stroke(Color(hex: 0x442222)))
            .accessibilityElement(children: .combine)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                Button("⚔️ Attack") { act(.attack) }.buttonStyle(WebButtonStyle(kind: .red)).accessibilityLabel("Attack the enemy")
                Button("💥 Heavy Strike") { act(.heavy) }.buttonStyle(WebButtonStyle(kind: .red))
                    .accessibilityLabel("Heavy Strike — hits harder but 30 percent chance to miss")
                Button("🧪 Potion (\(b.potions))") { drink() }.buttonStyle(WebButtonStyle(kind: .ghost))
                    .disabled(b.potions == 0).accessibilityLabel("Use a health potion to restore HP. \(b.potions) left")
                Button("👾 Minion Attack") { act(.minion) }.buttonStyle(WebButtonStyle(kind: .ghost))
                    .disabled(b.fortress.stationed.isEmpty)
                    .accessibilityLabel(b.fortress.stationed.isEmpty ? "Minion attack. No minions stationed" : "Call your stationed minions to attack. Takes your turn")
                if let g = Guns.equipped(game.store) {
                    GunButton(gun: g) {
                        var d = dice
                        let dmg = Guns.damage(g, atkBonus: 0, dice: &d)
                        dice = d
                        act(.gun(dmg))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(log.suffix(14).enumerated().reversed()), id: \.offset) { _, l in
                    Text(l).font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x999999)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10).background(Color.black.opacity(0.4))
            .accessibilityElement(children: .combine).accessibilityLabel("Combat log")
        }
    }

    private func act(_ a: Siege.Action) {
        guard var b = battle else { return }
        let s = Siege.act(&b, a, dice: &dice)
        battle = b
        guard s.acted else { Feedback.announce(s.log.joined(separator: " ")); return }
        log += s.log
        if s.enemyDied { Sound.sfx("sfx-enemy-die"); GunBelt.shared.killed() } else { Sound.sfx("sfx-attack") }
        if b.won || b.lost != nil {
            end(b)
            return
        }
        if b.baseUnderAttack { Feedback.warning() }
        Feedback.announce(s.log.joined(separator: " "))
    }

    private func drink() {
        guard var b = battle else { return }
        let msg = Siege.potion(&b)
        battle = b
        log.append(msg)
        Sound.sfx("sfx-potion")
        Feedback.announce(msg)
    }

    /// showSiegeResult: the gold home, the fortress saved, 3 trophies for a win.
    private func end(_ b: Siege.Battle) {
        let f = Siege.finish(b)
        Siege.save(f, store: game.store)
        fortress = f
        game.wallet.addGold(b.gold)
        if b.won {
            let t = game.achievements.trophies + 3
            game.store.setItem("dd_trophies", String(t))
            _ = game.achievements.check()
            Sound.sfx("sfx-victory")
            Feedback.announce("Victory! All 10 waves defeated. The Siege is complete! \(b.gold) gold and 3 trophies.")
        } else {
            Sound.sfx("sfx-hurt")
            Feedback.announce(b.lost == "base" ? "Your fortress has been destroyed! Durability reached zero. The siege is lost. \(b.gold) gold earned."
                              : "You have fallen. The siege is lost. Your fortress survives. \(b.gold) gold earned.")
        }
        battle = nil
        result = b
        Sound.track("menu")
    }

    private func resultView(_ b: Siege.Battle) -> some View {
        VStack(spacing: 12) {
            Text(b.won ? "🏆" : b.lost == "base" ? "💥" : "💀").font(.system(size: 48)).accessibilityHidden(true)
            Text(b.won ? "The Siege: Victory!" : b.lost == "base" ? "Fortress Destroyed" : "You Have Fallen")
                .font(Theme.decorative(20)).foregroundStyle(b.won ? Color(hex: 0xffdd44) : Color(hex: 0xcc4444)).accessibilityAddTraits(.isHeader)
            Text(b.won ? "You defended your fortress through all 10 waves. The enemies have been repelled. Your base stands strong."
                 : b.lost == "base" ? "Your fortress durability reached zero. The enemies broke through. Upgrade your base and try again."
                 : "You fought valiantly but were overwhelmed. Your fortress survives. Upgrade and return stronger.")
                .font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            Text("+\(b.gold) gold earned" + (b.won ? "\n+3 trophies awarded" : "") + "\n\(b.fortress.wavePoints) Wave Points total")
                .font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0x44ff88)).multilineTextAlignment(.center)
            Button("🏰 Return to Fortress") { result = nil; loadHub() }.buttonStyle(WebButtonStyle(kind: .gold))
                .accessibilityLabel("Return to fortress")
        }
        .frame(maxWidth: .infinity)
    }
}
