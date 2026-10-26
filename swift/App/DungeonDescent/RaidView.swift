import SwiftUI
import DungeonCore

/// "Daily Raid", the web version's #screen-raid: five waves for Mystery
/// Coins, once a day.
@MainActor
struct RaidView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var picked = 0
    @State private var hard = false
    @State private var raid: Raid?
    @State private var log: [String] = []
    @State private var dice = SystemDice()
    @State private var result: (tier: Int, coins: Int)?

    private var save: RaidSave { RaidSave(store: game.store) }

    var body: some View {
        WebScreen {
            ScreenHeader(title: "Daily Raid")
            if let r = raid {
                if r.done { end(r) } else { active(r) }
            } else {
                pre
            }
        }
        .onAppear {
            if save.doneToday() {
                Feedback.announce("Raid already completed today. You have \(game.mysteryCoins) Mystery Coins.")
            } else {
                Feedback.announce("Daily raid available. Select a character and press Begin Raid.")
            }
        }
        .onDisappear { Sound.track("menu") }
    }

    // MARK: Before (raid-pre)

    private var pre: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Survive five waves of enemies. Complete the raid without dying to earn gold and a Mystery Coin.")
                .font(Theme.crimson(15, italic: true)).foregroundStyle(Theme.textSecondary)
            if save.doneToday() {
                Text("You have already completed today's raid.\nCome back tomorrow.\n\nMystery Coins: \(game.mysteryCoins)")
                    .font(Theme.cinzel(12)).foregroundStyle(Theme.ash).multilineTextAlignment(.center)
                    .padding(16).frame(maxWidth: .infinity)
                    .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            } else {
                Text("Mystery Coins: \(game.mysteryCoins)").font(Theme.cinzel(11.5)).tracking(1.2).foregroundStyle(Theme.goldDim)
            }
            Text("Choose Your Champion").font(Theme.cinzel(12)).tracking(2).foregroundStyle(Theme.goldDim)
            if game.characters.isEmpty {
                Text("Create a character first to enter the raid.").font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textDim)
            }
            ForEach(Array(game.characters.enumerated()), id: \.element.created) { i, ch in
                Button {
                    picked = i
                    Feedback.announce("\(ch.name) selected for raid.")
                } label: {
                    HStack(spacing: 18) {
                        Text(CharacterListView.classIcons[ch.cls] ?? "⚔️").font(.system(size: 29))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(ch.name).font(Theme.cinzel(16, weight: .semibold)).foregroundStyle(Theme.ashLight)
                                Text("Lv \(ch.persistLevel ?? 1)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xffaa00))
                                    .padding(.horizontal, 7).padding(.vertical, 1)
                                    .background(Color(hex: 0x1a1000)).overlay(Rectangle().stroke(Color(hex: 0xffaa00)))
                            }
                            Text("\(ch.race) \(ch.cls) · \(ch.prof) · \(ch.difficulty)").font(Theme.crimson(12.8, italic: true))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14).padding(.horizontal, 20)
                    .background(Theme.bgPanel)
                    .overlay(Rectangle().stroke(picked == i ? Theme.gold : Theme.borderDim))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ch.name), \(ch.race) \(ch.cls), Level \(ch.persistLevel ?? 1), \(ch.difficulty). Press to select for raid.")
                .accessibilityAddTraits(picked == i ? [.isButton, .isSelected] : .isButton)
            }
            Text("Raid Difficulty").font(Theme.cinzel(12)).tracking(2).foregroundStyle(Theme.goldDim).padding(.top, 6)
            HStack(spacing: 10) {
                Button("⚔ Normal") { hard = false; Feedback.announce("Normal difficulty selected.") }
                    .buttonStyle(WebButtonStyle(kind: hard ? .ghost : .gold))
                    .accessibilityLabel("Normal difficulty, 5 to 7 enemies per wave")
                    .accessibilityAddTraits(hard ? [] : .isSelected)
                Button("💀 Hard (+50% gold)") { hard = true; Feedback.announce("Hard difficulty selected.") }
                    .buttonStyle(WebButtonStyle(kind: hard ? .gold : .ghost))
                    .accessibilityLabel("Hard difficulty, 5 to 10 enemies per wave, bonus gold reward")
                    .accessibilityAddTraits(hard ? .isSelected : [])
            }
            if !save.doneToday() && !game.characters.isEmpty {
                Button("⚔ Begin Raid") { begin() }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .accessibilityLabel("Begin today's raid")
            }
        }
    }

    private func begin() {
        guard game.characters.indices.contains(picked) else { return }
        let upgrades = Set(game.jsonObject("dd_coin_upgrades").compactMap { k, v -> String? in
            if case .bool(true) = v { return k }
            if case .number(let n) = v, n != 0 { return k }
            return nil
        })
        let inv = game.globalInventory
        var d = dice
        let r = Raid(character: game.characters[picked], weapon: inv.equippedWeapon, armor: inv.equippedArmor,
                     upgrades: upgrades, hard: hard, dice: &d)
        dice = d
        raid = r
        log = ["Wave 1 begins! \(r.enemies.count) enemies surge forward."]
        Sound.track("raid")
        Feedback.announce("Wave 1 of 5. \(r.enemies.count) enemies in this wave. Currently facing: \(r.enemies[0].name). Use attack, heavy strike, defend, or potion to fight.")
    }

    // MARK: Fighting (raid-active)

    private func active(_ r: Raid) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Wave \(r.wave) of 5").font(Theme.decorative(17)).foregroundStyle(Theme.bloodBright)
                Spacer()
                HStack(spacing: 12) {
                    Text("\(r.remaining) remaining").tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.gold)
                    Text("HP: \(r.hp)/\(r.maxHp)").foregroundStyle(Color(hex: 0xe05555))
                    Text("Gold: \(r.gold)").foregroundStyle(Theme.gold)
                    Text("Potions: \(r.potions)")
                }
                .font(Theme.cinzel(11.2))
            }
            .padding(.vertical, 12).padding(.horizontal, 18)
            .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            .overlay(alignment: .top) { Rectangle().fill(Theme.bloodBright).frame(height: 2) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Wave \(r.wave) of 5. \(r.remaining) enemies remaining. HP \(r.hp) of \(r.maxHp). \(r.gold) gold. \(r.potions) potions. SP \(r.sp) of \(r.maxSp).")

            VStack(alignment: .leading, spacing: 4) {
                Text("Your Health").font(Theme.cinzel(9.9)).tracking(2).textCase(.uppercase).foregroundStyle(Theme.textDim)
                Bar(value: Double(r.hp) / Double(max(r.maxHp, 1)), colors: [Color(hex: 0x8b2020), Color(hex: 0xc03030)],
                    track: Color(red: 60 / 255, green: 20 / 255, blue: 20 / 255).opacity(0.5), height: 7)
                Text("HP: \(r.hp) / \(r.maxHp)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xe05555))
            }
            .padding(.vertical, 10).padding(.horizontal, 18)
            .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your health: \(r.hp) of \(r.maxHp)")

            VStack(alignment: .leading, spacing: 10) {
                Text("Wave \(r.wave) of 5 — \(r.enemies.count) enemies").font(Theme.cinzel(9.9)).tracking(3).textCase(.uppercase)
                    .foregroundStyle(Theme.blood)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 7)], spacing: 7) {
                    ForEach(Array(r.enemies.enumerated()), id: \.offset) { _, e in
                        VStack(spacing: 2) {
                            Text(e.icon).font(.system(size: 20))
                            Text((e.alive ? "" : "✓ ") + e.name).font(Theme.cinzel(8.8)).foregroundStyle(Color(hex: 0xd4a0a0))
                                .lineLimit(2).multilineTextAlignment(.center)
                            Bar(value: Double(e.hp) / Double(max(e.maxHp, 1)), colors: [Theme.bloodBright, Theme.bloodBright],
                                track: Theme.blood.opacity(0.2), height: 4)
                        }
                        .padding(.vertical, 7).padding(.horizontal, 8)
                        .background(Theme.blood.opacity(0.1)).overlay(Rectangle().stroke(Theme.blood.opacity(0.25)))
                        .opacity(e.alive ? 1 : 0.18)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(e.alive ? "\(e.name), HP \(e.hp) of \(e.maxHp)" : "\(e.name), defeated")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Enemies this wave")
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.suffix(4).enumerated()), id: \.offset) { _, l in
                        Text(l).font(Theme.crimson(12.8, italic: true)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.4)).overlay(Rectangle().stroke(Theme.blood.opacity(0.15)))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Combat log")
                FlowRow(spacing: 8) {
                    action("⚔ Attack", "Attack current enemy") { fight(.attack) }
                    action("💥 Heavy", "Heavy strike, powerful but may miss") { fight(.heavy) }
                    action("🛡 Defend", "Defend and reduce damage this turn") { fight(.defend) }
                    action("🧪 Potion", "Use a health potion. \(r.potions) left.") { fight(.potion) }
                    ForEach(Array(r.skills.enumerated()), id: \.offset) { i, s in
                        let can = r.sp >= s.spCost
                        Button("\(s.icon) \(s.name) (\(s.spCost)SP)") { skill(i) }
                            .buttonStyle(DungeonButtonStyle(kind: .combat))
                            .disabled(!can)
                            .accessibilityLabel("\(s.name). \(s.desc) Costs \(s.spCost) SP.\(can ? "" : " Not enough SP.")")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Combat actions")
                Text("SP: \(r.sp)/\(r.maxSp)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x7090c0)).accessibilityHidden(true)
            }
            .padding(.vertical, 18).padding(.horizontal, 20)
            .background(Color(hex: 0x120a0a)).overlay(Rectangle().stroke(Theme.blood))
        }
    }

    private func action(_ t: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(t, action: run).buttonStyle(DungeonButtonStyle(kind: .combat)).accessibilityLabel(label)
    }

    private func fight(_ a: Raid.Action) {
        guard var r = raid else { return }
        Sound.sfx("sfx-select")
        var d = dice
        let t = r.fight(a, dice: &d)
        dice = d
        apply(t, r)
    }

    private func skill(_ i: Int) {
        guard var r = raid else { return }
        var d = dice
        let t = r.useSkill(i, dice: &d)
        dice = d
        apply(t, r)
    }

    private func apply(_ t: Raid.Turn, _ r: Raid) {
        let hpBefore = raid?.hp ?? r.hp
        raid = r
        log.append(contentsOf: t.log)
        t.sounds.forEach { Sound.sfx($0) }
        t.kills.forEach { game.recordBestiaryKill($0) }
        if r.hp < hpBefore { Feedback.hit() }
        if r.done {
            finish(r)
        } else {
            Feedback.announce(t.spoken.joined(separator: " "))
        }
    }

    private func finish(_ r: Raid) {
        if r.won {
            Sound.track("raid-victory")
            Sound.sfx("sfx-victory")
            Feedback.success()
            let tier = save.recordWin(gold: r.gold)
            game.addMysteryCoins(tier)
            game.achievements.trackGlobal("raidsWon")
            game.achievements.increment("raidsComplete")
            game.achievements.check()
            result = (tier, tier)
            Feedback.announce("Raid complete! You earned \(r.gold) gold and \(tier) Mystery Coin\(tier == 1 ? "" : "s"). Total coins: \(game.mysteryCoins). Press Main Menu to return.")
        } else {
            if game.characters.indices.contains(picked) {
                let ch = game.characters[picked]
                let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                game.addToGraveyard(.object([
                    "name": .string(ch.name), "cls": .string(ch.cls), "race": .string(ch.race),
                    "level": .number(Double(ch.persistLevel ?? 1)), "dungeon": .string("Daily Raid"),
                    "difficulty": .string("Raid"), "killedBy": .string("Wave \(r.wave) horde"),
                    "topFloor": .number(Double(r.wave)),
                    "date": .string("\(c.month ?? 1)/\(c.day ?? 1)/\(c.year ?? 2026)"),
                ]))
                game.postDeath(.init(name: ch.name, cls: ch.cls, dungeon: "Daily Raid", killedBy: "Wave \(r.wave) horde",
                                     floor: r.wave, kills: 0, gold: r.gold))
            }
            Feedback.announce("Defeated on wave \(r.wave). Come back tomorrow to try again.")
        }
    }

    // MARK: The end (raid-end)

    private func end(_ r: Raid) -> some View {
        let tier = result?.tier ?? 1
        let names = ["", "Standard", "Veteran", "Nightmare"]
        return VStack(spacing: 12) {
            Text(r.won ? "👑" : "💀").font(.system(size: 56)).accessibilityHidden(true)
            Text(r.won ? "Raid Complete!" : "Overwhelmed").font(Theme.decorative(24))
                .foregroundStyle(r.won ? Theme.gold : Theme.bloodBright)
                .accessibilityAddTraits(.isHeader)
            Text(r.won ? "You survived all five waves. The horde has been repelled — for now."
                 : "The horde was too great. Come back tomorrow and try again.")
                .font(Theme.crimson(15, italic: true)).foregroundStyle(Theme.textSecondary)
            VStack(spacing: 0) {
                if r.won {
                    row("Raid Tier", "Tier \(tier) — \(names[min(tier, 3)])")
                    row("Gold Earned", "\(r.gold)g")
                    row("Mystery Coins", "\(tier) (Tier bonus)")
                    row("Total Mystery Coins", "\(game.mysteryCoins)")
                    row("Total Raids Won", "\(save.totalWon)")
                    row("Waves Survived", "5 of 5")
                } else {
                    row("Wave Reached", "\(r.wave) of 5")
                    row("Gold Earned", "\(r.gold)g (lost)")
                    row("Mystery Coin", "Not earned")
                    row("Try Again", "Tomorrow")
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: 340)
            .background(Theme.bgDeep).overlay(Rectangle().stroke(Theme.borderDim))
            .overlay(alignment: .leading) { Rectangle().fill(Theme.goldDim).frame(width: 3) }
            Button("← Main Menu") { router.goTo(.menu) }
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Return to main menu")
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Theme.cinzel(10.9)).foregroundStyle(Theme.textDim)
            Spacer()
            Text(v).font(Theme.cinzel(12.5)).foregroundStyle(Theme.ashLight)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
