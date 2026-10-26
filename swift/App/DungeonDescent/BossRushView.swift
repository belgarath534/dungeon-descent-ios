import SwiftUI
import DungeonCore

/// "Boss Rush", the web version's #screen-bossrush: pick a champion, then
/// nine bosses back to back.
@MainActor
struct BossRushView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var picked = 0
    @State private var br: BossRush?
    @State private var log: [String] = []
    @State private var dice = SystemDice()
    @State private var busy = false

    private static let purple = Color(hex: 0x9a30c0), purpleDark = Color(hex: 0x4a0a7a), lilac = Color(hex: 0xc060f0)

    var body: some View {
        WebScreen {
            ScreenHeader(title: "Boss Rush")
            if let b = br {
                if b.done { end(b) } else { active(b) }
            } else {
                pre
            }
        }
        .onAppear {
            if game.characters.isEmpty {
                Feedback.announce("Boss Rush. No characters available. Create a character first.")
            } else {
                Feedback.announce("Boss Rush. Nine bosses back to back. Defeat 3 for 1 Mystery Coin, 6 for 3, all 9 for 6. Select a character and press Begin.")
            }
        }
        .onDisappear { Sound.track("menu") }
    }

    // MARK: Before (br-pre)

    private var pre: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("⚔ Nine Bosses. No Mercy.").font(Theme.cinzel(14)).foregroundStyle(Theme.gold)
                Text("Face every boss from every dungeon back to back. A small healing window between each fight. Defeat 3 for a Mystery Coin. Defeat 6 for 3 coins. Defeat all 9 for 6 coins. It has never been done.")
                    .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
            }
            .padding(.vertical, 22).padding(.horizontal, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            .overlay(alignment: .leading) { Rectangle().fill(Theme.goldDim).frame(width: 3) }
            Text("Choose Your Champion").font(Theme.cinzel(12)).tracking(2).foregroundStyle(Theme.goldDim)
            if game.characters.isEmpty {
                Text("Create a character first.").font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textDim)
            } else {
                ForEach(Array(game.characters.enumerated()), id: \.element.created) { i, ch in
                    Button {
                        picked = i
                        Feedback.announce("\(ch.name) selected for Boss Rush.")
                    } label: {
                        HStack(spacing: 18) {
                            Text(CharacterListView.classIcons[ch.cls] ?? "⚔️").font(.system(size: 29))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(ch.name).font(Theme.cinzel(16, weight: .semibold)).foregroundStyle(Theme.ashLight)
                                    Text("\(ch.race) \(ch.cls)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.goldDim)
                                        .padding(.horizontal, 7).padding(.vertical, 1).overlay(Rectangle().stroke(Theme.borderDim))
                                    Text("Lv \(ch.persistLevel ?? 1)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xffaa00))
                                        .padding(.horizontal, 7).padding(.vertical, 1)
                                        .background(Color(hex: 0x1a1000)).overlay(Rectangle().stroke(Color(hex: 0xffaa00)))
                                }
                                Text(ch.prof).font(Theme.crimson(12.8, italic: true)).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14).padding(.horizontal, 20)
                        .background(Theme.bgPanel)
                        .overlay(Rectangle().stroke(picked == i ? Self.purple : Theme.borderDim))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(ch.name), \(ch.race) \(ch.cls), Level \(ch.persistLevel ?? 1). Press to select.")
                    .accessibilityAddTraits(picked == i ? [.isButton, .isSelected] : .isButton)
                }
                Button("⚔ Begin Boss Rush") { begin() }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Begin Boss Rush")
            }
        }
    }

    private func begin() {
        guard game.characters.indices.contains(picked) else { return }
        let ch = game.characters[picked]
        let upgrades = Set(game.jsonObject("dd_coin_upgrades").compactMap { k, v -> String? in
            if case .bool(true) = v { return k }
            if case .number(let n) = v, n != 0 { return k }
            return nil
        })
        let inv = game.globalInventory
        let b = BossRush(character: ch, weapon: inv.equippedWeapon, armor: inv.equippedArmor, upgrades: upgrades)
        br = b
        log = ["Boss 1 of 9: \(b.boss.name) emerges!"]
        playBossTrack(b)
        Feedback.announce("Boss Rush begins! 9 bosses await. First boss: \(b.boss.name). Boss 1 of 9: \(b.boss.name). HP: \(b.boss.hp). Fight!")
    }

    private func playBossTrack(_ b: BossRush) {
        Sound.track(b.boss.dungeon == "ashbound" ? "ash-boss" : b.boss.dungeon == "frosthold" ? "frost-boss" : "boss")
    }

    // MARK: Fighting (br-active)

    private func active(_ b: BossRush) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Boss \(b.bossIndex + 1) of 9").font(Theme.decorative(17)).foregroundStyle(Self.lilac)
                Spacer()
                HStack(spacing: 10) {
                    Text("HP: \(b.hp)/\(b.maxHp)").foregroundStyle(Color(hex: 0xd4a0a0))
                    Text("SP: \(b.sp)/\(b.maxSp)").foregroundStyle(Color(hex: 0x7090c0))
                    Text("Coins: \(b.coinsEarned)").foregroundStyle(Theme.gold)
                }
                .font(Theme.cinzel(11.5))
            }
            .padding(.vertical, 14).padding(.horizontal, 20)
            .background(Color(hex: 0x0a0510)).overlay(Rectangle().stroke(Self.purpleDark))
            .overlay(alignment: .top) { Rectangle().fill(Self.purple).frame(height: 2) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Boss \(b.bossIndex + 1) of 9. HP \(b.hp) of \(b.maxHp). SP \(b.sp) of \(b.maxSp). \(b.coinsEarned) coins. \(b.potions) potions.")

            VStack(alignment: .leading, spacing: 4) {
                Text("Your Health").font(Theme.cinzel(9.9)).tracking(2).textCase(.uppercase).foregroundStyle(Theme.textDim)
                Bar(value: Double(b.hp) / Double(max(b.maxHp, 1)), colors: [Color(hex: 0x8b2020), Color(hex: 0xc03030)],
                    track: .black.opacity(0.3), height: 8)
                Text("HP: \(b.hp)/\(b.maxHp)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.blood)
            }
            .padding(.vertical, 10).padding(.horizontal, 18)
            .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your health: \(b.hp) of \(b.maxHp)")

            HStack(spacing: 6) {
                ForEach(0..<BossRush.bosses.count, id: \.self) { i in
                    Rectangle().fill(i < b.bossIndex ? Self.purple : i == b.bossIndex ? Self.lilac : Self.purpleDark.opacity(0.2))
                        .frame(width: 28, height: 10)
                        .overlay(Rectangle().stroke(Self.purpleDark))
                        .shadow(color: i == b.bossIndex ? Self.lilac.opacity(0.5) : .clear, radius: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Boss progress: \(b.bossIndex) of 9 defeated.")

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text(b.boss.icon).font(.system(size: 32)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(b.boss.name).font(Theme.cinzel(14)).foregroundStyle(Color(hex: 0xe0c0f0))
                        Bar(value: Double(b.bossHp) / Double(max(b.boss.hp, 1)), colors: [Self.purple, Self.purple],
                            track: .black.opacity(0.3), height: 6)
                        Text("HP: \(b.bossHp)/\(b.boss.hp)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xa070c0))
                    }
                }
                .padding(.vertical, 12).padding(.horizontal, 16)
                .background(Self.purpleDark.opacity(0.15)).overlay(Rectangle().stroke(Self.purple.opacity(0.3)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Current boss: \(b.boss.name). HP \(b.bossHp) of \(b.boss.hp).")

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.suffix(4).enumerated()), id: \.offset) { _, l in
                        Text(l).font(Theme.crimson(12.8, italic: true)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.4)).overlay(Rectangle().stroke(Self.purple.opacity(0.15)))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Combat log")

                FlowRow(spacing: 8) {
                    action("⚔ Attack", "Attack") { fight(.attack) }
                    action("💥 Heavy", "Heavy strike") { fight(.heavy) }
                    action("🛡 Defend", "Defend") { fight(.defend) }
                    action("🧪 Potion (\(b.potions))", "Use potion. \(b.potions) left.") { fight(.potion) }
                    ForEach(Array(b.skills.enumerated()), id: \.offset) { i, s in
                        let can = b.sp >= s.spCost
                        Button("\(s.icon) \(s.name) (\(s.spCost)SP)") { skill(i) }
                            .buttonStyle(BossRushButtonStyle())
                            .disabled(!can || busy)
                            .accessibilityLabel("\(s.name). Costs \(s.spCost) SP.\(can ? "" : " Not enough SP.")")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Combat actions")
                Text("SP: \(b.sp)/\(b.maxSp)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x7090c0))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 18).padding(.horizontal, 20)
            .background(Color(hex: 0x0a0510)).overlay(Rectangle().stroke(Self.purpleDark))
        }
    }

    private func action(_ t: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(t, action: run).buttonStyle(BossRushButtonStyle()).disabled(busy).accessibilityLabel(label)
    }

    private func fight(_ a: BossRush.Action) {
        guard var b = br, !busy else { return }
        Sound.sfx("sfx-select")
        let before = b.bossIndex
        let t = b.fight(a, dice: &dice)
        apply(t, &b, from: before)
    }

    private func skill(_ i: Int) {
        guard var b = br, !busy else { return }
        let before = b.bossIndex
        let t = b.useSkill(i, dice: &dice)
        apply(t, &b, from: before)
    }

    /// Plays a turn's sounds, adds its log and reads it out, then handles a
    /// fallen boss or the end of the rush.
    private func apply(_ t: BossRush.Turn, _ b: inout BossRush, from before: Int) {
        log.append(contentsOf: t.log)
        t.sounds.forEach { Sound.sfx($0) }
        if t.coins > 0 { game.addMysteryCoins(t.coins) }
        if let name = t.bossDefeated { game.recordBestiaryKill(name) }
        if !t.acted {
            Feedback.announce(t.spoken.joined(separator: " "))
            br = b
            return
        }
        if t.bossDefeated != nil { Feedback.hit(heavy: true) } else if b.hp < (br?.hp ?? b.hp) { Feedback.hit() }
        br = b
        if b.done {
            finish(b)
            return
        }
        if b.bossIndex != before { playBossTrack(b) }
        Feedback.announce(t.spoken.joined(separator: " "))
    }

    private func finish(_ b: BossRush) {
        let secs = Int(Date().timeIntervalSince1970 - b.startedAt)
        let timeStr = "\(secs / 60)m \(secs % 60)s"
        if b.won {
            Sound.track("raid-victory")
            let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            BossRushScore.save(BossRushScore(bosses: 9, time: secs, timeStr: timeStr, cls: b.cls,
                                             date: "\(c.year ?? 2026)-\(c.month ?? 1)-\(c.day ?? 1)"), store: game.store)
            game.achievements.markOnce("bossRushComplete")
            HighScore.add("boss_rush", 2000, store: game.store)
            game.achievements.check()
            Feedback.announce("INCREDIBLE! You defeated all 9 bosses! Boss Rush complete! You earned \(b.coinsEarned) Mystery Coins total!")
        } else {
            if game.characters.indices.contains(picked) {
                let ch = game.characters[picked]
                let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                game.addToGraveyard(.object([
                    "name": .string(ch.name), "cls": .string(ch.cls), "race": .string(ch.race),
                    "level": .number(Double(ch.persistLevel ?? 1)), "dungeon": .string("Boss Rush"),
                    "difficulty": .string("Boss Rush"), "killedBy": .string(b.boss.name),
                    "topFloor": .number(Double(b.bossIndex + 1)),
                    "date": .string("\(c.month ?? 1)/\(c.day ?? 1)/\(c.year ?? 2026)"),
                ]))
                game.postDeath(.init(name: ch.name, cls: ch.cls, dungeon: "Boss Rush", killedBy: b.boss.name,
                                     floor: b.bossIndex + 1, kills: b.bossIndex, gold: 0))
            }
            Feedback.announce("Defeated on boss \(b.bossIndex + 1). You earned \(b.coinsEarned) Mystery Coins. Well fought.")
        }
    }

    // MARK: The end (br-end)

    private func end(_ b: BossRush) -> some View {
        let secs = Int(Date().timeIntervalSince1970 - b.startedAt)
        let scores = BossRushScore.load(game.store)
        return VStack(spacing: 12) {
            Text(b.won ? "👑" : "💀").font(.system(size: 52)).accessibilityHidden(true)
            Text(b.won ? "All Nine Defeated" : "Overwhelmed").font(Theme.decorative(24))
                .foregroundStyle(b.won ? Theme.gold : Theme.bloodBright)
                .accessibilityAddTraits(.isHeader)
            Text(b.won ? "You did the impossible. All nine bosses. No one will believe you."
                 : "You fell on boss \(b.bossIndex + 1) of 9. You already earned your coins though.")
                .font(Theme.crimson(15, italic: true)).foregroundStyle(Theme.textSecondary)
            VStack(spacing: 0) {
                if b.won {
                    row("Bosses Defeated", "9 of 9")
                    row("Time", "\(secs / 60)m \(secs % 60)s")
                    row("Total Coins Earned", "\(b.coinsEarned) Mystery Coins")
                    row("Achievement", "Boss Rush Legend")
                } else {
                    row("Bosses Defeated", "\(b.bossIndex) of 9")
                    row("Mystery Coins Earned", "\(b.coinsEarned)")
                    row("Last Boss", b.boss.name)
                }
            }
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: 340)
            .background(Theme.bgDeep).overlay(Rectangle().stroke(Theme.borderDim))
            .overlay(alignment: .leading) { Rectangle().fill(Theme.goldDim).frame(width: 3) }
            if b.won && !scores.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RUN SAVED TO LEADERBOARD").font(Theme.cinzel(11.2)).foregroundStyle(Theme.goldDim)
                    Text("PERSONAL BEST RUNS").font(Theme.cinzel(11.5)).tracking(2.3).foregroundStyle(Theme.goldDim).padding(.top, 8)
                    ForEach(Array(scores.prefix(5).enumerated()), id: \.offset) { i, s in
                        HStack {
                            Text("\(i + 1). \(s.cls)").foregroundStyle(Theme.goldDim)
                            Spacer()
                            Text("\(s.bosses)/9 bosses")
                            Spacer()
                            Text(s.timeStr).foregroundStyle(Theme.textDim)
                        }
                        .font(Theme.crimson(12))
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: 340)
            }
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

/// .bossrush-btn
struct BossRushButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .font(Theme.cinzel(10.9)).tracking(1.1).textCase(.uppercase)
            .foregroundStyle(down ? Color(hex: 0xe0c0f0) : Color(hex: 0xc0a0e0))
            .padding(.vertical, 9).padding(.horizontal, 14).frame(minHeight: 44)
            .background(Color(red: 74 / 255, green: 10 / 255, blue: 122 / 255).opacity(down ? 0.35 : 0.15))
            .overlay(Rectangle().stroke(down ? Color(hex: 0x9a30c0) : Color(hex: 0x4a0a7a)))
            .opacity(enabled ? 1 : 0.3)
    }
}
