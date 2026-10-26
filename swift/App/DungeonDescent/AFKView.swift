import SwiftUI
import DungeonCore

/// Endless Descent, the web version's AFK screens (#screen-afk-setup,
/// #screen-afk, #ov-afk-skill, #screen-afk-summary, #screen-afk-shop).
@MainActor
struct AFKView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @Environment(\.scenePhase) private var scenePhase
    let model: AFKModel

    var body: some View {
        AFKScreens(model: model)
            .onChange(of: scenePhase) { p in
                model.inForeground = p == .active
                if p == .active { model.catchUp() } else { game.saveNow() }
            }
    }
}

@MainActor
private struct AFKScreens: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @ObservedObject var model: AFKModel

    static let violet = Color(hex: 0x8888ff)

    var body: some View {
        ZStack {
            WebBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch model.phase {
                    case .setup: setup
                    case .running, .skills: running
                    case .summary: summary
                    case .shop: shop
                    }
                }
                .padding(16)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
            }
            if model.phase == .skills { skillPick }
        }
        .onAppear {
            if model.phase == .running {
                model.resume()
            } else if model.phase == .setup {
                announceSetup()
            }
        }
        .onDisappear { model.stopTimer() }
    }

    private func label(_ text: String, size: CGFloat = 9.6, tracking: CGFloat = 3, color: Color = Color(hex: 0x555555)) -> some View {
        Text(text).font(Theme.cinzel(size)).tracking(tracking).foregroundStyle(color)
    }

    private func box<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x0a0a0a))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x1a1a1a)))
    }

    // MARK: Setup (initAFKSetup)

    private func announceSetup() {
        let s = model.save
        let c = AFKSave.todaysChallenge()
        let done = s.challengeDone()
        Feedback.announce("Endless Descent. Choose your champion and begin. Your descent points: \(s.totalPoints). Daily challenge: \(c.desc)\(done ? " Completed." : " Bonus \(c.bonus) points.")")
    }

    private var setup: some View {
        let s = model.save
        let c = AFKSave.todaysChallenge()
        let done = s.challengeDone()
        return VStack(alignment: .leading, spacing: 10) {
            Button("← Menu") { router.goTo(.menu) }
                .buttonStyle(BackButtonStyle())
                .accessibilityLabel("Back to main menu")
            VStack(spacing: 6) {
                Text("⬇").font(.system(size: 24)).accessibilityHidden(true)
                Text("Endless Descent").font(Theme.decorative(17.6)).foregroundStyle(Self.violet)
                    .accessibilityAddTraits(.isHeader)
                Text("The dungeon has no end. Leave it running. See how far you fall.")
                    .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x666666)).multilineTextAlignment(.center)
                Text("It keeps descending when you leave the app. Your Lock Screen shows the run.")
                    .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x555555)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
            label("CHOOSE YOUR CHAMPION")
            if game.characters.isEmpty {
                Text("Create a character first.").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0x555555))
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(game.characters.enumerated()), id: \.element.created) { i, ch in
                let lvl = ch.persistLevel ?? 1
                Button {
                    model.picked = i
                    Sound.sfx("sfx-select")
                    Feedback.announce("\(ch.name) selected.")
                } label: {
                    Text("\(ch.name) — \(ch.cls) (Lv \(lvl))")
                        .font(Theme.cinzel(12)).foregroundStyle(model.picked == i ? Theme.gold : Theme.ashLight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .background(model.picked == i ? Color(hex: 0x1a1400) : Theme.bgPanel)
                        .overlay(Rectangle().stroke(model.picked == i ? Theme.gold : Theme.borderDim))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ch.name), \(ch.cls), Level \(lvl)")
                .accessibilityAddTraits(model.picked == i ? [.isButton, .isSelected] : .isButton)
            }
            box {
                label("DAILY CHALLENGE", tracking: 2)
                Text((done ? "✓ " : "🎯 Daily: ") + c.desc + (done ? " (done)" : " — +\(c.bonus) pts"))
                    .font(Theme.cinzel(11.2)).foregroundStyle(done ? Color(hex: 0x44ff88) : Color(hex: 0xffdd44))
            }
            box {
                label("DESCENT POINTS", tracking: 2)
                HStack {
                    Text("Available to spend").font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x888888))
                    Spacer()
                    Text(s.totalPoints.formatted()).font(Theme.decorative(16)).foregroundStyle(Color(hex: 0xaaaaff))
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.bottom, 6)
            if !game.characters.isEmpty {
                Button { model.begin() } label: { Text("⬇ Begin Endless Descent").frame(maxWidth: .infinity) }
                    .buttonStyle(MenuButtonStyle(primary: true))
                    .accessibilityLabel("Begin Endless Descent AFK mode")
            }
            Button {
                Sound.sfx("sfx-select")
                model.phase = .shop
                let s = model.save
                Feedback.announce("Descent Shop. \(s.totalPoints) descent points. \(AFKRun.shop.count) items available.")
            } label: { Text("🛒 Descent Shop").frame(maxWidth: .infinity) }
                .buttonStyle(MenuButtonStyle())
                .accessibilityLabel("Open Descent Points shop")
        }
    }

    // MARK: Running (#screen-afk)

    private var running: some View {
        let r = model.run
        let hp = r?.hp ?? 0, maxHp = max(1, r?.maxHp ?? 1)
        let pct = max(0, Int((Double(hp) / Double(maxHp) * 100).rounded()))
        let level = r?.level ?? 1
        let need = r?.xpNeeded
        return VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 4) {
                label("ENDLESS DESCENT", size: 8.8, tracking: 3.5)
                Text("\(r?.floor ?? 1)").font(Theme.decorative(32)).foregroundStyle(Self.violet)
                label("FLOOR", size: 10.4, tracking: 2)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Floor \(r?.floor ?? 1)")
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 3) {
                HStack {
                    Text("HP")
                    Spacer()
                    Text("\(hp) / \(maxHp)")
                }
                .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xaaaaaa))
                bar(Double(pct) / 100, height: 8,
                    colors: pct > 50 ? [0x228822, 0x44ff44] : pct > 25 ? [0x886622, 0xffaa44] : [0x882222, 0xff4444],
                    border: 0x222222)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Health \(hp) of \(maxHp), \(pct) percent")

            HStack(spacing: 8) {
                stat("⬆ Level", "\(level)", Color(hex: 0xffdd44), Color(hex: 0xffdd44))
                stat("⬇ Points", (r?.points ?? 0).formatted(), Self.violet, Color(hex: 0xaaaaff))
            }

            VStack(spacing: 3) {
                HStack {
                    Text("XP")
                    Spacer()
                    Text("\(r?.xp ?? 0) / \(level >= 10 || need == nil ? "MAX" : "\(need!)")")
                }
                .font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555))
                bar(level >= 10 || need == nil ? 1 : min(1, Double(r?.xp ?? 0) / Double(need!)), height: 5,
                    colors: [0x446644, 0x88ff88], border: 0x1a1a1a)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(level >= 10 || need == nil ? "Experience: max level" : "Experience \(r?.xp ?? 0) of \(need!)")

            if let report = model.awayReport {
                Text(report).font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xaaaaff))
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x0a0a1a)).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x1a1a2a)))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if (r?.log ?? []).isEmpty {
                        Text("Awaiting your descent...").foregroundStyle(Color(hex: 0x555555))
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    ForEach(Array((r?.log ?? []).enumerated()), id: \.offset) { _, line in
                        Text(line.text).foregroundStyle(Color(hex: line.color))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x0a0a0a)).frame(height: 1) }
                    }
                }
                .font(Theme.cinzel(10.9))
                .lineSpacing(4)
                .padding(10)
            }
            .frame(height: 220)
            .background(Color(hex: 0x050505))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x1a1a1a)))
            .accessibilityLabel("AFK combat log")

            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let left = model.nextFightIn
                bar(left / max(1, r?.fightSeconds ?? 15), height: 4, colors: [0x8888ff, 0x8888ff], border: 0x1a1a1a)
            }
            .accessibilityHidden(true)

            HStack(spacing: 8) {
                Button { model.usePotion() } label: { Text("🧪 Potion (\(r?.potions ?? 0))").frame(maxWidth: .infinity) }
                    .buttonStyle(MenuButtonStyle())
                    .disabled((r?.potions ?? 0) <= 0)
                    .opacity((r?.potions ?? 0) <= 0 ? 0.4 : 1)
                    .accessibilityLabel("Use health potion in AFK mode, \(r?.potions ?? 0) left")
                Button { model.endRun() } label: { Text("■ End Run").frame(maxWidth: .infinity) }
                    .buttonStyle(MenuButtonStyle(primary: true))
                    .accessibilityLabel("End AFK run and return to menu")
            }
        }
    }

    private func stat(_ name: String, _ value: String, _ nameColor: Color, _ valueColor: Color) -> some View {
        HStack {
            Text(name).font(Theme.cinzel(10.4)).foregroundStyle(nameColor)
            Spacer()
            Text(value).font(Theme.decorative(14.4)).foregroundStyle(valueColor)
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(Color(hex: 0x0a0a0a))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x1a1a2a)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name.dropFirst(2)) \(value)")
    }

    private func bar(_ fraction: Double, height: CGFloat, colors: [UInt32], border: UInt32) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Color(hex: 0x111111)
                LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * CGFloat(max(0, min(1, fraction))))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: border)))
    }

    // MARK: Skill pick (#ov-afk-skill)

    private var skillPick: some View {
        let n = model.run?.levelsGainedThisRun ?? 0
        return ZStack {
            Color.black.opacity(0.92).ignoresSafeArea().accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(n) level\(n > 1 ? "s" : "") gained. Choose \(model.skillsToChoose) skill\(model.skillsToChoose > 1 ? "s" : "").")
                        .font(Theme.decorative(14.4)).foregroundStyle(Color(hex: 0xffdd44))
                        .accessibilityAddTraits(.isHeader)
                    ForEach(model.skillChoices, id: \.effect) { sk in
                        let chosen = model.skillsChosen.contains(sk.effect)
                        Button { model.pickSkill(sk) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(sk.icon) \(sk.name)").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xffdd44))
                                Text(sk.desc).font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x888888))
                                    .multilineTextAlignment(.leading).lineSpacing(3)
                                Text("\(sk.spCost) SP · \(sk.tier)").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555))
                                    .padding(.top, 2)
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: 0x0a0a0a))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(chosen ? Color(hex: 0x44ff88) : Color(hex: 0x333333)))
                            .opacity(chosen ? 0.5 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(chosen)
                        .accessibilityLabel("\(sk.name). \(sk.desc). Cost \(sk.spCost) SP.\(chosen ? " Selected." : "")")
                    }
                }
                .padding(20)
                .frame(maxWidth: 420)
                .background(Color(hex: 0x0a0806))
                .overlay(Rectangle().stroke(Theme.goldDim))
                .padding(.horizontal, 12).padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }
            .accessibilityAddTraits(.isModal)
        }
    }

    // MARK: Summary (#screen-afk-summary)

    private var summary: some View {
        let r = model.run
        let s = model.save
        let rows: [(String, String)] = [
            ("Floor Reached", "\(r?.floor ?? 1)"),
            ("Level Reached", "\(r?.level ?? 1)"),
            ("Levels Gained This Run", "+\(r?.levelsGainedThisRun ?? 0)"),
            ("Skills Unlocked", "\(r?.skills.count ?? 0)"),
            ("Enemies Defeated", "\(r?.enemiesDefeated ?? 0)"),
            ("Bosses Defeated", "\(r?.bossesDefeated ?? 0)"),
            ("Total Damage Dealt", (r?.totalDmgDealt ?? 0).formatted()),
            ("Total Damage Taken", (r?.totalDmgTaken ?? 0).formatted()),
            ("Descent Points Earned", "+\(r?.points ?? 0)"),
            ("Total Descent Points", s.totalPoints.formatted()),
            ("Best Floor Ever", "\(s.bestFloor)"),
        ]
        return VStack(spacing: 0) {
            Text("⬇").font(.system(size: 32)).padding(.bottom, 12).accessibilityHidden(true)
            Text("The Descent Ends").font(Theme.decorative(16)).foregroundStyle(Self.violet).padding(.bottom, 16)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows.indices, id: \.self) { i in
                HStack {
                    Text(rows[i].0).foregroundStyle(Color(hex: 0x555555))
                    Spacer()
                    Text(rows[i].1).foregroundStyle(Color(hex: 0xaaaaaa))
                }
                .font(Theme.cinzel(11.2))
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x111111)).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
            .padding(.bottom, 0)
            Button {
                model.phase = .setup
                announceSetup()
            } label: { Text("⬇ Descend Again").frame(maxWidth: .infinity) }
                .buttonStyle(MenuButtonStyle(primary: true))
                .padding(.top, 24)
                .accessibilityLabel("Descend again")
            Button { router.goTo(.menu) } label: { Text("← Main Menu").frame(maxWidth: .infinity) }
                .buttonStyle(MenuButtonStyle())
                .padding(.top, 8)
                .accessibilityLabel("Return to main menu")
        }
        .padding(.top, 24)
    }

    // MARK: Shop (#screen-afk-shop)

    private var shop: some View {
        let s = model.save
        let up = s.upgrades
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("← Back") {
                    model.phase = .setup
                    announceSetup()
                }
                .buttonStyle(BackButtonStyle())
                .accessibilityLabel("Back to Endless Descent")
                Text("Descent Shop").font(Theme.decorative(17.6)).foregroundStyle(Theme.gold)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.bottom, 6)
            HStack(spacing: 10) {
                Text("⬇").font(.system(size: 19)).accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(s.totalPoints.formatted()).font(Theme.decorative(16)).foregroundStyle(Color(hex: 0xaaaaff))
                    Text("Descent Points").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555))
                }
                Spacer()
            }
            .padding(.vertical, 10).padding(.horizontal, 14)
            .background(Color(hex: 0x0a0a0a))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x1a1a2a)))
            .accessibilityElement(children: .combine)
            .padding(.bottom, 6)
            ForEach(AFKRun.shop) { item in
                let owned = up[item.id] ?? 0
                let maxed = owned >= item.max
                let afford = s.totalPoints >= item.cost
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(item.icon) \(item.name)").font(Theme.cinzel(11.5)).foregroundStyle(maxed ? Color(hex: 0xffdd44) : Color(hex: 0xaaaaaa))
                        Text(item.desc).font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x555555)).lineSpacing(3)
                        if owned > 0 && item.max > 1 {
                            Text("Owned: \(owned)\(item.max < 99 ? " / \(item.max)" : "")").font(Theme.cinzel(9.3)).foregroundStyle(Color(hex: 0x888888))
                        }
                    }
                    Spacer(minLength: 0)
                    Button(maxed ? "✓ Maxed" : "\(item.cost) pts") { model.buy(item) }
                        .font(Theme.cinzel(10.4))
                        .foregroundStyle(maxed ? Color(hex: 0x888888) : afford ? Color(hex: 0xffdd44) : Color(hex: 0x444444))
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .background(maxed ? Color(hex: 0x1a1a00) : afford ? Color(hex: 0x1a1400) : Color(hex: 0x0a0a0a))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(maxed ? Color(hex: 0x333333) : afford ? Color(hex: 0xffdd44) : Color(hex: 0x222222)))
                        .disabled(maxed || !afford)
                        .fixedSize()
                        .accessibilityLabel("\(item.name). \(item.desc). Cost: \(item.cost) points.\(maxed ? " Already maxed." : afford ? "" : " Not enough points.")")
                }
                .padding(12)
                .background(Color(hex: 0x0a0a0a))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(maxed ? Color(hex: 0x2a2a00) : Color(hex: 0x1a1a1a)))
            }
            if !model.shopMessage.isEmpty {
                Text(model.shopMessage).font(Theme.cinzel(11.2)).italic().foregroundStyle(Color(hex: 0xa0d4a0))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 8)
            }
        }
    }
}
