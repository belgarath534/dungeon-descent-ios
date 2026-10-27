import SwiftUI
import DungeonCore

/// The Mine's trip: digging (with the web version's 1.5-second swing),
/// fights, and the summary when you surface.
@MainActor
final class MineModel: ObservableObject {
    enum Stage { case choose, mining, summary }

    @Published var stage: Stage = .choose
    @Published var run: MineRun?
    @Published var log: [String] = []
    @Published var fightLog: [String] = []
    @Published var digging = false
    @Published var haul: Mine.Haul?
    @Published var choosingSkill = false
    @Published var confirmLeave = false

    let game: GameModel
    private var dice = SystemDice()

    init(game: GameModel) { self.game = game }

    private func add(_ line: String) {
        log.append(line)
        if log.count > 120 { log.removeFirst(log.count - 120) }
    }

    // MARK: Trip

    func start(_ index: Int) {
        guard game.characters.indices.contains(index) else { return }
        let ch = game.characters[index]
        run = Mine.start(ch)
        log = []
        fightLog = []
        haul = nil
        stage = .mining
        add("⛏ \(ch.name) enters the mine at depth 1.")
        Sound.ambient("mine")
        Sound.track("mine-explore")
        Feedback.announce("\(ch.name) enters the mine. Mine for resources, descend for better loot, surface to collect. Watch your hands — you can only carry 15 items.")
    }

    func dig() {
        guard let m = run, !digging else { return }
        if m.inCombat { Feedback.announce("Finish the fight first!"); return }
        if m.handsFull {
            add("🎒 Hands full! You cannot carry more.")
            Feedback.announce("Your hands are full. Surface\(m.hasChest ? " or use the chest" : "").")
            return
        }
        digging = true
        Sound.sfx("sfx-search")
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, var m = self.run else { return }
            self.digging = false
            let out = Mine.dig(&m, dice: &self.dice)
            self.run = m
            switch out {
            case .handsFull:
                Feedback.announce("Your hands are full.")
            case .empty(let msg):
                self.add("🪨 " + msg)
                Feedback.announce(msg)
            case .found(let items):
                items.forEach { self.add("\($0.icon) Found: \($0.name)!") }
                Sound.sfx("sfx-loot")
                Feedback.success()
                Feedback.announce(items.map { "Found \($0.name)!" }.joined(separator: " ") + (m.handsFull ? " Your hands are full." : ""))
            case .enemy(let e):
                self.enemyAppears(e)
            }
        }
    }

    private func enemyAppears(_ e: MineFoe) {
        fightLog = []
        add("⚠️ A \(e.name) blocks your path!")
        if let s = e.special { fightLog.append("👁 " + s) }
        Sound.track("mine-combat")
        Sound.sfx("sfx-enemy-undead")
        Feedback.warning()
        Feedback.announce("Enemy encountered in the mine! \(e.name). HP: \(e.hp). " + (e.special.map { $0 + " " } ?? "") + "Attack or flee.")
    }

    func descend() {
        guard var m = run, !m.inCombat else { Feedback.announce("Finish the fight first!"); return }
        let boss = Mine.descend(&m)
        run = m
        game.achievements.setMax("mineMaxDepth", Double(m.depth))
        _ = game.achievements.check()
        Sound.sfx("sfx-stairs")
        if let boss {
            fightLog = ["💀 \(boss.name.uppercased()) blocks your path!"]
            if let lore = boss.lore { fightLog.append("📖 \"\(lore)\"") }
            add("⚠️ Something stirs in the darkness below. A presence. Old. Heavy. Wrong.")
            Sound.track("mine-combat")
            Feedback.warning()
            Feedback.announce("You feel something wrong at depth \(m.depth). Milestone boss! \(boss.name). HP: \(boss.hp). \(boss.lore ?? "")")
            return
        }
        add("⬇ Descending to depth \(m.depth)...")
        Feedback.announce("Descending to depth \(m.depth). Enemies are stronger. Loot is rarer and better. HP \(m.hp) of \(m.maxHp).")
    }

    func stash() {
        guard var m = run, m.hasChest else { return }
        let n = Mine.stash(&m)
        run = m
        add("📦 Stored \(n) item\(n == 1 ? "" : "s") in the chest. Hands free!")
        Sound.sfx("sfx-confirm")
        Feedback.announce("Stored \(n) items in the mine chest. Your hands are free.")
    }

    // MARK: Fighting

    func act(_ a: Mine.Action) {
        guard var m = run, m.inCombat else { return }
        let t = Mine.act(&m, a, dice: &dice)
        run = m
        resolve(t, sound: a == .heavy ? "sfx-heavy-hit" : a == .attack ? "sfx-attack" : a == .potion ? "sfx-potion" : "sfx-select")
    }

    func skill(_ effect: String) {
        choosingSkill = false
        guard var m = run, m.inCombat else { return }
        let t = Mine.useSkill(&m, effect, dice: &dice)
        run = m
        resolve(t, sound: "sfx-crit")
    }

    var equippedGun: Gun? { Guns.equipped(game.store) }

    func shoot(_ g: Gun) {
        guard var m = run, m.inCombat else { return }
        let t = Mine.shoot(&m, g, dice: &dice)
        run = m
        if t.enemyDied { GunBelt.shared.killed() }
        resolve(t, sound: "sfx-attack")
    }

    private func resolve(_ t: Mine.Turn, sound: String) {
        fightLog += t.log
        if !t.acted {
            Feedback.announce(t.log.joined(separator: " "))
            return
        }
        Sound.sfx(sound)
        if t.fled {
            t.log.forEach(add)
            Sound.track("mine-explore")
            Feedback.announce(t.log.joined(separator: " "))
            return
        }
        if t.enemyDied, let e = t.defeated {
            game.wallet.addGold(t.gold)
            _ = game.recordBestiaryKill(e.name)
            add("💀 You defeated \(e.name). +\(t.gold) gold.")
            t.loot.forEach { add("\($0.icon) \($0.name)") }
            Sound.sfx("sfx-enemy-die")
            Sound.track("mine-explore")
            Feedback.success()
            Feedback.announce(t.log.joined(separator: " "))
            return
        }
        if t.playerDied {
            Sound.sfx("sfx-hurt")
            Feedback.warning()
            Feedback.announce(t.log.joined(separator: " ") + " Surfacing with chest items only.")
            surface(defeated: true)
            return
        }
        Feedback.announce(t.log.joined(separator: " "))
    }

    // MARK: Leaving

    /// mineSurface: everything in hand and chest comes home with you.
    func surface(defeated: Bool = false) {
        guard let m = run else { return }
        if m.inCombat && !defeated { Feedback.announce("Finish the fight first!"); return }
        let h = Mine.surface(m, defeated: defeated)
        if h.gold > 0 { game.wallet.addGold(h.gold) }
        if h.diamonds > 0 { game.wallet.addDiamonds(h.diamonds) }
        if h.coins > 0 { game.addMysteryCoins(h.coins) }
        h.potions.forEach { game.globalInventory.add($0) }
        Mine.storeParts(h, store: game.store)
        game.achievements.setMax("mineMaxDepth", Double(m.depth))
        _ = game.achievements.check()
        haul = h
        run = nil
        stage = .summary
        Sound.ambient(nil)
        Sound.track("menu")
        var said = (defeated ? "Defeated in the mine. " : "Surfaced from the mine. ") + "Depth reached: \(h.depth). "
        if h.gold > 0 { said += "\(h.gold) gold. " }
        if h.diamonds > 0 { said += "\(h.diamonds) diamonds. " }
        if h.coins > 0 { said += "\(h.coins) Mystery Coins. " }
        if !h.potions.isEmpty { said += "\(h.potions.count) potions saved to your items. " }
        for (p, n) in h.parts.sorted(by: { $0.key < $1.key }) { said += "\(Mine.partNames[p] ?? p): \(n). " }
        if h.herbs > 0 { said += "\(h.herbs) alchemy herbs. " }
        if h.isEmpty { said += "Nothing found this run." }
        Feedback.announce(said)
    }

    /// mineExit: leaving without surfacing loses what you carry, and the
    /// chest too, so it asks first. (The web version only asked about your hands.)
    var leaveLoses: Int { (run?.hand.count ?? 0) + (run?.chest.count ?? 0) }
}

struct MineView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @StateObject private var holder = Holder()

    @MainActor final class Holder: ObservableObject { @Published var model: MineModel? }

    var body: some View {
        ZStack {
            WebBackground()
            if let m = holder.model { MineScreens(model: m) }
        }
        .onAppear { if holder.model == nil { holder.model = MineModel(game: game) } }
    }
}

private struct MineScreens: View {
    @ObservedObject var model: MineModel
    @EnvironmentObject var router: Router
    private let gold = Color(hex: 0xc8a832)

    var body: some View {
        WebScreen {
            switch model.stage {
            case .choose: choose
            case .mining: if let m = model.run { mining(m) }
            case .summary: if let h = model.haul { summary(h) }
            }
        }
        .alert("⚠ Leave the Mine?", isPresented: $model.confirmLeave) {
            Button("Leave (lose items)", role: .destructive) {
                model.run = nil
                Sound.ambient(nil)
                Sound.track("menu")
                router.goTo(.menu)
            }
            Button("Stay in mine", role: .cancel) {}
        } message: {
            Text("You still have \(model.leaveLoses) item\(model.leaveLoses == 1 ? "" : "s") in your hands and chest. Leave now and lose them, or surface first to keep them.")
        }
    }

    private func menu() {
        if model.run != nil && model.leaveLoses > 0 {
            model.confirmLeave = true
            return
        }
        model.run = nil
        Sound.ambient(nil)
        Sound.track("menu")
        router.goTo(.menu)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("⛏ The Mine").font(Theme.decorative(24)).foregroundStyle(gold).accessibilityAddTraits(.isHeader)
            Text("DIG DEEP. FIND RICHES. SURVIVE.").font(Theme.cinzel(9.6)).tracking(3).foregroundStyle(Color(hex: 0x8b6914))
        }
        .frame(maxWidth: .infinity)
    }

    private var status: some View {
        HStack(spacing: 14) {
            Text("💰 \(model.game.wallet.gold)g")
            Text("💎 \(model.game.wallet.diamonds)")
            Text("🪙 \(model.game.mysteryCoins)")
            Spacer()
            Text("⛏ Depth: \(model.run?.depth ?? 1)")
        }
        .font(Theme.cinzel(11)).foregroundStyle(gold)
        .padding(10).background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x443300)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Choose

    private var choose: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("← Menu") { menu() }.buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to menu")
            header
            status
            Text("Choose a character to send into the mine:").font(Theme.cinzel(11)).foregroundStyle(Theme.textSecondary)
            if model.game.characters.isEmpty {
                Text("No characters yet. Create one first from the main menu.").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x555555))
            }
            ForEach(Array(model.game.characters.enumerated()), id: \.offset) { i, ch in
                Button("⚔ \(ch.name) — \(ch.cls) · \(ch.race)") { model.start(i) }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Send \(ch.name) the \(ch.cls) into the mine")
            }
        }
    }

    // MARK: Mining

    private func bar(_ value: Double, _ color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: 0x1a1000))
                Rectangle().fill(color).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func mining(_ m: MineRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("← Menu") { menu() }.buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to menu")
            header
            status
            VStack(alignment: .leading, spacing: 4) {
                Text("🎒 Hands: \(m.hand.count) / \(Mine.maxCarry) items").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textSecondary)
                bar(Double(m.hand.count) / Double(Mine.maxCarry), m.handsFull ? Color(hex: 0xcc2222) : m.hand.count * 10 >= Mine.maxCarry * 7 ? Color(hex: 0xcc8800) : gold)
                Text("❤️ HP: \(m.hp) / \(m.maxHp)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textSecondary)
                bar(Double(m.hp) / Double(max(1, m.maxHp)), m.hp * 4 < m.maxHp ? Color(hex: 0xcc2222) : m.hp * 2 < m.maxHp ? Color(hex: 0xcc8800) : Color(hex: 0x44cc44))
            }
            .accessibilityElement(children: .combine)
            if let e = m.enemy { combat(m, e) } else { digArea(m) }
            VStack(alignment: .leading, spacing: 4) {
                Text("IN YOUR HANDS").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Color(hex: 0x8b6914))
                Text(handText(m.hand)).font(Theme.cinzel(10.4)).foregroundStyle(Theme.textSecondary)
                if !m.chest.isEmpty {
                    Text("IN THE CHEST").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Color(hex: 0x8b6914)).padding(.top, 6)
                    Text(handText(m.chest)).font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
                }
            }
            .padding(10).background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x332200)))
            .accessibilityElement(children: .combine)
        }
    }

    private func handText(_ items: [MineItem]) -> String {
        guard !items.isEmpty else { return "Nothing yet. Start mining!" }
        var order: [String] = []
        var count: [String: Int] = [:]
        var icon: [String: String] = [:]
        for it in items {
            if count[it.name] == nil { order.append(it.name) }
            count[it.name, default: 0] += 1
            icon[it.name] = it.icon
        }
        return order.map { "\(icon[$0] ?? "") \($0)" + (count[$0]! > 1 ? " ×\(count[$0]!)" : "") }.joined(separator: ", ")
    }

    private func digArea(_ m: MineRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(m.atmosphere).font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Button(model.digging ? "⛏ Mining..." : "⛏ Mine") { model.dig() }
                    .buttonStyle(WebButtonStyle(kind: .gold)).disabled(model.digging)
                    .accessibilityLabel("Mine for resources")
                Button("⬇ Deeper") { model.descend() }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).disabled(model.digging)
                    .accessibilityLabel("Descend deeper into the mine")
            }
            HStack(spacing: 8) {
                Button("⬆ Surface") { model.surface() }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).disabled(model.digging)
                    .accessibilityLabel("Surface and collect your items")
                if m.hasChest {
                    Button("📦 Chest") { model.stash() }
                        .buttonStyle(WebButtonStyle(kind: .ghost))
                        .accessibilityLabel("Store everything in your hands in the mine chest")
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(model.log.suffix(14).enumerated().reversed()), id: \.offset) { _, line in
                    Text(line).font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x888888))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Mine log")
        }
    }

    private func combat(_ m: MineRun, _ e: MineFoe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(e.icon) \(e.name)").font(Theme.cinzel(14)).foregroundStyle(Color(hex: 0xcc4444)).accessibilityAddTraits(.isHeader)
            Text("\(e.name) HP: \(e.hp)/\(e.maxHp)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textSecondary)
            bar(Double(e.hp) / Double(max(1, e.maxHp)), Color(hex: 0xcc2222))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(model.fightLog.suffix(10).enumerated()), id: \.offset) { _, line in
                    Text(line).font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0xaaaaaa))
                }
            }
            .accessibilityElement(children: .combine)
            if model.choosingSkill {
                let skills = Mine.skills(m)
                ForEach(skills, id: \.effect) { s in
                    Button("\(s.icon) \(s.name) — \(s.desc)") { model.skill(s.effect) }
                        .buttonStyle(WebButtonStyle(kind: .ghost))
                        .accessibilityLabel("Use skill \(s.name). \(s.desc)")
                }
                Button("Cancel") { model.choosingSkill = false }.buttonStyle(WebButtonStyle(kind: .ghost))
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    Button("⚔ Attack") { model.act(.attack) }.buttonStyle(WebButtonStyle(kind: .gold)).accessibilityLabel("Attack enemy")
                    Button("💥 Heavy") { model.act(.heavy) }.buttonStyle(WebButtonStyle(kind: .gold))
                        .accessibilityLabel("Heavy strike, high damage but enemy hits back harder")
                    Button("🛡 Defend") { model.act(.defend) }.buttonStyle(WebButtonStyle(kind: .ghost))
                        .accessibilityLabel("Defend, reduce incoming damage this turn")
                    if let g = model.equippedGun {
                        GunButton(gun: g) { model.shoot(g) }
                    } else {
                        Button("🔫 Gun") { Feedback.announce("No gun equipped. Craft one at Home or buy one from the Blacksmith.") }
                            .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Shoot with equipped gun")
                    }
                    Button("🧪 Potion") { model.act(.potion) }.buttonStyle(WebButtonStyle(kind: .ghost))
                        .accessibilityLabel("Use a health potion from your hand. \(m.hand.filter { $0.type == "mine-potion" }.count) in hand")
                    Button("✨ Skill") {
                        if Mine.skills(m).isEmpty {
                            Feedback.announce("No skills unlocked yet.")
                        } else {
                            model.choosingSkill = true
                            Feedback.announce("Choose a skill. " + Mine.skills(m).map(\.name).joined(separator: ", "))
                        }
                    }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Use a skill")
                    Button("🏃 Flee") { model.act(.flee) }.buttonStyle(WebButtonStyle(kind: .red)).accessibilityLabel("Flee from enemy")
                }
            }
        }
        .padding(12).background(Color(hex: 0x100404)).overlay(Rectangle().stroke(Color(hex: 0x552222)))
    }

    // MARK: Summary

    private func summary(_ h: Mine.Haul) -> some View {
        VStack(spacing: 12) {
            Text(h.defeated ? "💀" : "⛏").font(.system(size: 48)).accessibilityHidden(true)
            Text(h.defeated ? "You Were Defeated" : "Surfaced Safely").font(Theme.decorative(22))
                .foregroundStyle(h.defeated ? Color(hex: 0xaa4444) : gold).accessibilityAddTraits(.isHeader)
            Text("DEPTH REACHED: \(h.depth)").font(Theme.cinzel(11)).tracking(2).foregroundStyle(Theme.textDim)
            VStack(alignment: .leading, spacing: 6) {
                if h.gold > 0 { row("💰 Gold", "+\(h.gold)") }
                if h.diamonds > 0 { row("💎 Diamonds", "+\(h.diamonds)") }
                if h.coins > 0 { row("🪙 Mystery Coins", "+\(h.coins)") }
                if !h.potions.isEmpty { row("🧪 Potions → Items", "+\(h.potions.count)") }
                ForEach(h.parts.sorted(by: { $0.key < $1.key }), id: \.key) { p, n in row("🔩 \(Mine.partNames[p] ?? p)", "+\(n)") }
                if h.herbs > 0 { row("🌿 Alchemy Herbs", "+\(h.herbs)") }
                if h.isEmpty { Text("Nothing found this run.").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x444444)) }
                if h.defeated { Text("Hand items lost on defeat.").font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x886666)) }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x443300)))
            Button("⛏ Return to Mine") { model.stage = .choose }.buttonStyle(WebButtonStyle(kind: .gold)).accessibilityLabel("Return to the mine")
            Button("← Main Menu") { router.goTo(.menu) }.buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Return to main menu")
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack { Text(name); Spacer(); Text(value).foregroundStyle(gold) }
            .font(Theme.cinzel(11.5)).foregroundStyle(Theme.textSecondary)
            .accessibilityElement(children: .combine)
    }
}
