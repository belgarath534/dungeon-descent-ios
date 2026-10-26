import SwiftUI
import DungeonCore

/// The web version's #screen-dungeon: top bar, daily quest, XP and SP,
/// room tracker, the room, then either combat or navigation, with the
/// inventory below. The shop, level up, skill choice, floor complete, flee,
/// pause, stats and run log open over it like the web overlays.
@MainActor
struct DungeonView: View {
    @StateObject private var model: RunModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var game: GameModel

    @State private var showInventory = false
    @State private var showStats = false
    @State private var showRunLog = false
    @State private var askingFlee = false
    @State private var paused = false
    @State private var showSettings = false
    @State private var choosingPath = false
    @State private var invTab = "all"
    @State private var invSearch = ""
    @State private var openDetails: Set<String> = []

    init(game: GameModel, characterIndex: Int, resume: Bool) {
        _model = StateObject(wrappedValue: RunModel(game: game, characterIndex: characterIndex, resume: resume))
    }

    private var run: Run { model.run }
    private var fighting: Bool { model.phase == .fighting }

    var body: some View {
        ZStack {
            WebBackground()
            ScrollView {
                VStack(spacing: 12) {
                    topBar
                    dailyQuest
                    xpRow
                    roomTracker
                    if fighting, let e = run.enemy, e.isBoss { bossPhaseBar(e) }
                    roomSection
                    if fighting { combatSection } else { navSection }
                    if showInventory { inventorySection }
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 60)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            overlays
        }
        .foregroundStyle(Theme.textPrimary)
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        switch model.phase {
        case .shopping: ShopOverlay(model: model)
        case .floorCleared where model.levelUp == nil && run.skillChoices.isEmpty: floorComplete
        case .victory:
            RunSummaryView(model: model, victory: true, choosingPath: $choosingPath)
        case .defeat:
            if model.showingDeathCinematic {
                DeathCinematic(model: model)
            } else {
                RunSummaryView(model: model, victory: false, choosingPath: $choosingPath)
            }
        default: EmptyView()
        }
        if model.phase != .victory && model.phase != .defeat {
            if let lvl = model.levelUp {
                LevelUpOverlay(model: model, level: lvl)
            } else if !run.skillChoices.isEmpty {
                SkillChoiceOverlay(model: model)
            }
        }
        if model.gambling { GambleOverlay(model: model) }
        if model.showingHome { HomeOverlay(model: model) }
        if askingFlee { fleeOverlay }
        if paused { pauseOverlay }
        if showStats {
            StatsOverlay(run: run, deaths: game.characters.first { $0.name == run.name }?.deaths ?? []) { showStats = false }
        }
        if showRunLog { runLogOverlay }
        if choosingPath { ngPlusChoice }
        if showSettings { WebSettingsView { showSettings = false } }
    }

    // MARK: Top bar (.dg-topbar)

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 6) {
                smallButton("⏸", label: "Pause game") { openPause() }
                smallButton("💬", label: "Open global chat") { notYet("Global chat") }
                VStack(alignment: .leading, spacing: 1) {
                    Text(run.name).font(Theme.cinzel(13.6, weight: .semibold)).foregroundStyle(Theme.ashLight)
                    Text("\(run.race) \(run.cls) · \(run.dungeon == "The Ashbound Wastes" ? "Ashbound Wastes" : run.dungeon)")
                        .font(Theme.crimson(11.5, italic: true)).foregroundStyle(Theme.textDim)
                }
                .lineLimit(2).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 0) {
                Text("\(run.floor)").font(Theme.decorative(22)).foregroundStyle(Theme.gold)
                    .shadow(color: Theme.gold.opacity(0.3), radius: 6)
                Text("Floor").font(Theme.cinzel(8.8)).tracking(2.6).textCase(.uppercase).foregroundStyle(Theme.goldDim)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Floor \(run.floor)")
            VStack(alignment: .trailing, spacing: 3) {
                FlowRow(spacing: 10) {
                    Text("❤️×\(run.lives)")
                    Text("💪\(run.hp)/\(run.maxHp)")
                    Text("💰\(run.gold)g")
                }
                if run.hardcore {
                    Text("💀 HC").font(Theme.cinzel(8.8)).tracking(0.9).foregroundStyle(Color(hex: 0xcc0000))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: 0x0a0000)).overlay(Rectangle().stroke(Color(hex: 0xcc0000)))
                        .accessibilityLabel("Hardcore Mode active")
                }
            }
            .font(Theme.cinzel(11.2)).foregroundStyle(Theme.ashLight)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Lives: \(run.lives). Health: \(run.hp) of \(run.maxHp). Gold: \(run.gold) gold.\(run.hardcore ? " HARDCORE MODE ACTIVE." : "")")
        }
        .padding(.vertical, 10).padding(.horizontal, 16)
        .background(Theme.bgPanel)
        .overlay(Rectangle().stroke(Theme.borderDim))
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderGlow).frame(height: 2) }
    }

    private func smallButton(_ t: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 15)).frame(minWidth: 36, minHeight: 36)
                .background(Theme.bgStone).overlay(Rectangle().stroke(Theme.borderDim))
        }
        .accessibilityLabel(label)
    }

    // MARK: Daily quest, XP and room tracker

    private var dailyQuest: some View {
        let dq = game.dailyQuests
        let q = dq.quest
        let done = dq.isComplete
        let pct = min(1, Double(dq.progress) / Double(max(q.target, 1)))
        return HStack(spacing: 8) {
            Text("Daily").font(Theme.cinzel(9.6)).tracking(1.4).textCase(.uppercase).foregroundStyle(Theme.goldDim)
            Text(done ? "\(q.desc) ✦ Complete!" : "\(q.desc) (\(dq.progress)/\(q.target))")
                .font(Theme.cinzel(10.4)).foregroundStyle(done ? Color(hex: 0x7aaa7a) : Theme.ash)
                .frame(maxWidth: .infinity, alignment: .leading)
            Bar(value: done ? 1 : pct, colors: [Theme.goldDim, Theme.gold], track: Theme.gold.opacity(0.1), height: 4)
                .frame(width: 60)
        }
        .padding(.vertical, 6).padding(.horizontal, 12)
        .background(Theme.bgDeep).overlay(Rectangle().stroke(Theme.borderDim))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily quest: \(q.desc). Progress: \(dq.progress) of \(q.target)\(done ? ". Complete!" : ".")")
    }

    private var xpRow: some View {
        let needed = Progression.xpNeeded(atLevel: run.level)
        return FlowRow(spacing: 10) {
            Text("Lv \(run.level)").font(Theme.decorative(13.6)).foregroundStyle(Theme.gold)
            HStack(spacing: 6) {
                Text("XP").font(Theme.cinzel(9.6)).tracking(1.4).foregroundStyle(Theme.textDim)
                Bar(value: Double(run.xp) / Double(max(needed, 1)), colors: [Theme.goldDim, Theme.gold],
                    track: Theme.gold.opacity(0.1), height: 6).frame(width: 90)
                Text("\(run.xp)/\(needed)").font(Theme.cinzel(9.9)).foregroundStyle(Theme.goldDim)
            }
            HStack(spacing: 6) {
                Text("SP").font(Theme.cinzel(9.6)).tracking(1.4).foregroundStyle(Color(hex: 0x7090c0))
                Bar(value: Double(run.sp) / Double(max(run.maxSp, 1)), colors: [Color(hex: 0x3060a0), Color(hex: 0x6090d0)],
                    track: Color(red: 80 / 255, green: 120 / 255, blue: 200 / 255).opacity(0.15), height: 5).frame(width: 70)
                Text("\(run.sp)/\(run.maxSp)").font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x7090c0))
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgDeep).overlay(Rectangle().stroke(Theme.borderDim))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(run.level). XP \(run.xp) of \(needed). SP \(run.sp) of \(run.maxSp).")
    }

    private var roomTracker: some View {
        let left = max(0, run.floorRoomsNeeded - run.roomsOnFloor)
        let bossFloor = run.floor == 10 && run.difficulty != .endless
        let right = bossFloor ? "⚠ Boss Floor" : left <= 2 ? "Next floor soon" : "\(left) rooms on this floor"
        let color = bossFloor ? Color(hex: 0xcc4444) : left <= 2 ? Color(hex: 0xcc9944) : Color(hex: 0x555555)
        return HStack {
            Text("Room \(run.roomsOnFloor + 1) · Floor \(run.floor)").foregroundStyle(Color(hex: 0x888888))
            Spacer()
            Text(right).foregroundStyle(color)
        }
        .font(Theme.cinzel(10.4))
        .padding(.vertical, 6).padding(.horizontal, 12)
        .background(Color(hex: 0x080808)).overlay(Rectangle().stroke(Color(hex: 0x1a1a1a)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Room \(run.roomsOnFloor + 1), floor \(run.floor). \(right).")
    }

    private func bossPhaseBar(_ e: Enemy) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Phase \(run.bossPhase) of 3").font(Theme.cinzel(10.4)).tracking(2).textCase(.uppercase)
                .foregroundStyle(Theme.bloodBright)
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { i in
                    Rectangle().fill(i <= run.bossPhase ? Theme.bloodBright : Theme.bloodBright.opacity(0.2))
                        .frame(width: 24, height: 8)
                        .overlay(Rectangle().stroke(Theme.blood))
                }
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x1a0808)).overlay(Rectangle().stroke(Theme.bloodBright))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Boss phase \(run.bossPhase) of 3")
    }

    // MARK: The room (.dg-room)

    private var roomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(model.roomTitle.isEmpty ? "Chamber" : model.roomTitle)
                    .font(Theme.cinzel(12)).tracking(3.6).textCase(.uppercase).foregroundStyle(Theme.goldDim)
                Text("Floor \(run.floor) · Room \(run.roomsOnFloor)").font(Theme.cinzel(9.6)).foregroundStyle(Theme.textDim)
                if run.searched { Text("🔍 Searched").font(Theme.cinzel(9.6)).foregroundStyle(Theme.textDim) }
            }
            .accessibilityElement(children: .combine)
            Text(model.roomText.isEmpty ? "You stand at the entrance." : model.roomText)
                .font(Theme.crimson(16, italic: true)).foregroundStyle(Theme.textSecondary).lineSpacing(5)
            if model.phase == .event, let ev = model.pendingEvent {
                eventBox(text: "\(ev.title) — \(ev.text)", tone: "") {
                    FlowRow(spacing: 8) {
                        ForEach(Array(ev.choices.enumerated()), id: \.offset) { i, label in
                            Button(label) { model.chooseEvent(i) }
                                .buttonStyle(DungeonButtonStyle(kind: .action))
                        }
                    }
                    .padding(.top, 8)
                }
            } else if !model.eventText.isEmpty {
                eventBox(text: model.eventText, tone: model.eventTone) { EmptyView() }
            }
        }
        .padding(.vertical, 22).padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Room description")
    }

    private func eventBox<Extra: View>(text: String, tone: String, @ViewBuilder extra: () -> Extra) -> some View {
        let (border, bg, fg): (Color, Color, Color) = tone == "danger"
            ? (Theme.blood, Theme.blood.opacity(0.06), Color(hex: 0xd4a0a0))
            : tone == "good" ? (Color(hex: 0x4a8a4a), Color(hex: 0x4a8a4a).opacity(0.06), Color(hex: 0xa0d4a0))
            : (Theme.borderGlow, Theme.gold.opacity(0.04), Theme.ashLight)
        return VStack(alignment: .leading, spacing: 0) {
            Text(text).font(Theme.crimson(14)).foregroundStyle(fg).lineSpacing(4)
            extra()
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .overlay(alignment: .leading) { Rectangle().fill(border).frame(width: 2) }
    }

    // MARK: Combat (.dg-combat)

    private var combatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let e = run.enemy {
                Text("⚔ \(e.name)").font(Theme.decorative(14.4)).foregroundStyle(Theme.bloodBright)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 14) {
                    Text(e.icon).font(.system(size: 29)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.name).font(Theme.cinzel(14)).foregroundStyle(Color(hex: 0xd4a0a0))
                        Bar(value: Double(e.hp) / Double(max(e.maxHp, 1)), colors: [Theme.bloodBright, Theme.bloodBright],
                            track: .black.opacity(0.3), height: 6)
                        Text("HP: \(e.hp)/\(e.maxHp)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.blood)
                            .accessibilityLabel("\(e.name) health: \(e.hp) of \(e.maxHp)")
                        if !enemyStatus(e).isEmpty {
                            Text(enemyStatus(e)).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0xcc8866))
                                .accessibilityLabel("Enemy status effects: \(enemyStatus(e))")
                        }
                    }
                }
                .padding(.vertical, 10).padding(.horizontal, 14)
                .background(Theme.blood.opacity(0.08)).overlay(Rectangle().stroke(Theme.blood.opacity(0.2)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Health").font(Theme.cinzel(9.9)).tracking(2).textCase(.uppercase).foregroundStyle(Theme.textDim)
                    .accessibilityHidden(true)
                Bar(value: Double(run.hp) / Double(max(run.maxHp, 1)), colors: [Color(hex: 0x8b2020), Color(hex: 0xc03030)],
                    track: .black.opacity(0.3), height: 6)
                Text("HP: \(run.hp) / \(run.maxHp)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.blood)
                    .accessibilityLabel("Your health: \(run.hp) of \(run.maxHp)")
            }
            combatLog
            FlowRow(spacing: 8) {
                Button("⚔ Attack") { model.act(.attack) }.buttonStyle(DungeonButtonStyle(kind: .combat))
                    .accessibilityLabel("Attack")
                Button("💥 Heavy") { model.act(.heavy) }.buttonStyle(DungeonButtonStyle(kind: .combat))
                    .accessibilityLabel("Heavy strike, powerful but can miss")
                Button("🛡 Defend") { model.act(.defend) }.buttonStyle(DungeonButtonStyle(kind: .combat))
                    .accessibilityLabel("Defend, reduces incoming damage")
                Button("🧪 Potion") { drinkPotion() }.buttonStyle(DungeonButtonStyle(kind: .combat))
                    .accessibilityLabel("Use a health potion")
                if model.canSoulTrap {
                    Button("🪤 Soul Trap") { model.soulTrap() }.buttonStyle(DungeonButtonStyle(kind: .combat))
                        .accessibilityLabel("Use Soul Trap to capture this enemy as a minion")
                }
                if run.enemy?.isBoss != true {
                    Button("🏃 Flee") { model.act(.flee) }.buttonStyle(DungeonButtonStyle(kind: .combat))
                        .accessibilityLabel("Attempt to flee combat")
                }
                Button("🔍 Examine") { examine() }.buttonStyle(DungeonButtonStyle(kind: .combat))
                    .accessibilityLabel("Examine enemy to learn their weakness and abilities")
                Button("🎒 Inventory") { toggleInventory() }.buttonStyle(DungeonButtonStyle(kind: .combat))
                    .accessibilityLabel("Open inventory during combat")
                ForEach(model.skills, id: \.effect) { s in
                    let cost = model.skillCost(s)
                    Button("\(s.icon) \(s.name) (\(cost))") { model.useSkill(s.effect) }
                        .buttonStyle(DungeonButtonStyle(kind: .skill))
                        .disabled(cost > run.sp)
                        .accessibilityLabel("\(s.name). \(s.desc) Costs \(cost) SP.\(cost > run.sp ? " Not enough SP." : "")")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Combat actions")
        }
        .padding(.vertical, 18).padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x120a0a))
        .overlay(Rectangle().stroke(Theme.blood))
        .overlay(alignment: .top) { Rectangle().fill(Theme.bloodBright).frame(height: 2) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Combat")
    }

    private var combatLog: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.log.prefix(4).reversed())) { line in
                Text(line.text).font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.3)).overlay(Rectangle().stroke(Theme.blood.opacity(0.15)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Combat log")
    }

    private func enemyStatus(_ e: Enemy) -> String {
        var c: [String] = []
        if e.cursedTurns > 0 { c.append("Cursed (\(e.cursedTurns))") }
        if e.stunTurns > 0 { c.append("Stunned") }
        if e.dotTurns > 0 { c.append("Burning \(e.dotDamage)/turn (\(e.dotTurns))") }
        return c.joined(separator: " · ")
    }

    private func drinkPotion() {
        if let i = run.inventory.firstIndex(where: { $0.type == "potion" }) {
            model.useItem(at: i)
        } else {
            model.setEvent("You reach for a potion — your satchel is empty.")
            Feedback.announce("No potions available.")
        }
    }

    private func examine() {
        guard let e = run.enemy else { Feedback.announce("No enemy to examine."); return }
        var lines = ["\(e.name).", "Health: \(max(0, e.hp)) of \(e.maxHp).",
                     "Attacks for \(e.currentAtk.lowerBound) to \(e.currentAtk.upperBound) damage."]
        if let d = e.desc, !d.isEmpty { lines.append(RunModel.sentence(d)) }
        if e.isBoss { lines.append("Boss. Phase \(run.bossPhase) of 3.") }
        if e.isElite { lines.append("Elite enemy.") }
        Sound.sfx("sfx-select")
        Feedback.announce(lines.joined(separator: " "))
    }

    // MARK: Navigation (.dg-nav)

    private var navSection: some View {
        VStack(spacing: 10) {
            Text("Navigate the Crypt").font(Theme.cinzel(9.6)).tracking(3.4).textCase(.uppercase).foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    compass("▲ North", "Move north") { model.move("north") }
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
                GridRow {
                    compass("◄ West", "Move west") { model.move("west") }
                    Button("🔍 Search") { model.search() }
                        .buttonStyle(DungeonButtonStyle(kind: .compassAccent))
                        .accessibilityLabel("Search this room")
                    compass("East ►", "Move east") { model.move("east") }
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    compass("▼ South", "Move south") { model.move("south") }
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }
            .frame(maxWidth: 260)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Directions")
            FlowRow(spacing: 8) {
                act("🎒 Inventory", "Toggle inventory") { toggleInventory() }
                act("📊 Stats", "View character stats") { showStats = true; Feedback.announce(statsSpoken) }
                act("📖 Skills", "Open skill book, view and reorder your unlocked skills") { showSkillBook() }
                act("⚙ Settings", "Open settings, adjust music and sound effects") { showSettings = true }
                act("📜 Run Log", "Open run log, see everything that happened this run") { showRunLog = true }
                act("💾 Save", "Save your progress right now") { model.manualSave() }
                act("⚒ Blacksmith", "Open blacksmith — upgrade your equipped weapon or armor") { notYet("The Blacksmith") }
                act("✨ Arcane Shop", "Open Arcane Shop — buy spell scrolls") { notYet("The Arcane Shop") }
                act("📖 Spell Book", "Open Spell Book — view your learned spells") { notYet("The Spell Book") }
                Button("🚪 Flee Dungeon") { askFlee() }
                    .buttonStyle(DungeonButtonStyle(kind: .red))
                    .accessibilityLabel("Flee the dungeon and return to character select")
                act("🏠 Home", "Go home — rest, store gold, upgrade skills") { model.openHome() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dungeon actions")
        }
        .padding(.vertical, 16).padding(.horizontal, 18)
        .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
    }

    private func compass(_ t: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(t, action: action).buttonStyle(DungeonButtonStyle(kind: .compass)).accessibilityLabel(label)
    }

    private func act(_ t: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(t, action: action).buttonStyle(DungeonButtonStyle(kind: .action)).accessibilityLabel(label)
    }

    private func showSkillBook() {
        let s = model.skills
        Sound.sfx("sfx-select")
        Feedback.announce(s.isEmpty ? "Skill book. No skills unlocked yet."
                          : "Skill book. \(s.count) skills. " + s.map { "\($0.name), \(model.skillCost($0)) SP" }.joined(separator: ". ") + ".")
    }

    private var statsSpoken: String {
        let all = Skills.all(for: run.cls).count
        return "\(run.name) the \(run.race) \(run.cls) on \(run.difficulty.rawValue). Level \(run.level). HP \(run.hp) of \(run.maxHp). SP \(run.sp) of \(run.maxSp). Attack \(run.atk.lowerBound + run.totalAtkBonus) to \(run.atk.upperBound + run.totalAtkBonus). Defense \(run.totalDef). Gold \(run.gold). Kills \(run.kills). Floor \(run.floor) of 10. Skills unlocked: \(model.skills.count) of \(all)."
    }

    // MARK: Inventory (.dg-inventory)

    private static let invTabs = [("all", "All"), ("favorites", "Fav"), ("weapons", "Weapons"), ("armor", "Armor"),
                                  ("potions", "Potions"), ("special", "Special"), ("equipment", "Equipment"),
                                  ("materials", "Materials")]

    private func toggleInventory() {
        Sound.sfx("sfx-select")
        withAnimation { showInventory.toggle() }
        Feedback.announce(showInventory ? "Inventory opened. \(run.inventory.count) items.\(fighting ? " Armor equipping is locked during combat." : "")"
                          : "Inventory closed.")
    }

    private var favorites: [String] {
        guard let s = game.store.getItem("dd_inv_favorites"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return v
    }

    private func toggleFavorite(_ name: String) {
        var f = favorites
        if let i = f.firstIndex(of: name) { f.remove(at: i) } else { f.append(name) }
        if let d = try? JSONEncoder().encode(f), let s = String(data: d, encoding: .utf8) { game.store.setItem("dd_inv_favorites", s) }
        model.objectWillChange.send()
        Feedback.announce(f.contains(name) ? "\(name) added to favorites." : "\(name) removed from favorites.")
    }

    private static func category(_ i: Item) -> String {
        if i.isWeapon { return "weapons" }
        if i.isArmor { return "armor" }
        if ["potion", "elixir", "sp-potion", "luck-potion", "fire-potion", "curse-potion", "swift-potion", "def-potion",
            "atk-potion", "cursed", "heal"].contains(i.type) { return "potions" }
        if i.type == "material" { return "materials" }
        if ["relic", "mask"].contains(i.type) { return "equipment" }
        return "special"
    }

    private var inventorySection: some View {
        let favs = favorites
        // Stack by name, like renderInv; gear is never stacked.
        var stacks: [(item: Item, count: Int, index: Int)] = []
        for (i, item) in run.inventory.enumerated() {
            let fav = favs.contains(item.name)
            let tabOK = invTab == "all" || (invTab == "favorites" ? fav : Self.category(item) == invTab)
            let q = invSearch.lowercased()
            let searchOK = q.isEmpty || item.name.lowercased().contains(q) || item.desc.lowercased().contains(q)
            guard tabOK && searchOK else { continue }
            if !item.isWeapon && !item.isArmor, let s = stacks.firstIndex(where: { $0.item.name == item.name }) {
                stacks[s].count += 1
            } else {
                stacks.append((item, 1, i))
            }
        }
        stacks.sort { (favs.contains($0.item.name) ? 0 : 1) < (favs.contains($1.item.name) ? 0 : 1) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🎒 Inventory").font(Theme.cinzel(9.9)).tracking(3).textCase(.uppercase).foregroundStyle(Theme.goldDim)
                Spacer()
                Button("Close ✕") { toggleInventory() }
                    .font(Theme.cinzel(10.4)).foregroundStyle(Theme.ash)
                    .padding(.vertical, 6).padding(.horizontal, 10).overlay(Rectangle().stroke(Theme.borderDim))
                    .accessibilityLabel("Close inventory")
            }
            HStack(spacing: 6) {
                TextField("", text: $invSearch, prompt: Text("Search items...").foregroundColor(Theme.textDim))
                    .font(Theme.cinzel(11)).padding(8).background(Color(hex: 0x080808)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                    .accessibilityLabel("Search inventory items")
                Button("x") { invSearch = "" }.font(Theme.cinzel(11)).padding(8).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                    .accessibilityLabel("Clear search")
                Button("Sort") { sortInventory() }.font(Theme.cinzel(11)).padding(8).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                    .accessibilityLabel("Auto sort inventory by type")
            }
            .foregroundStyle(Theme.ash)
            FlowRow(spacing: 4) {
                ForEach(Self.invTabs.indices, id: \.self) { n in
                    let (id, label) = Self.invTabs[n]
                    let sel = invTab == id
                    Button(label) { invTab = id; Feedback.announce("\(label) tab.") }
                        .font(Theme.cinzel(9.3)).tracking(0.5)
                        .foregroundStyle(sel ? Color(hex: 0xcc9944) : Color(hex: 0x555555))
                        .padding(.vertical, 5).padding(.horizontal, 8).frame(minHeight: 32)
                        .background(sel ? Color(hex: 0x1a1000) : Color(hex: 0x080808))
                        .overlay(Rectangle().stroke(sel ? Color(hex: 0xcc9944) : Color(hex: 0x333333)))
                        .accessibilityLabel("\(label) tab")
                        .accessibilityAddTraits(sel ? .isSelected : [])
                }
            }
            if (invTab == "all" || invTab == "weapons") && (run.equippedWeapon != nil || run.equippedArmor != nil) {
                Text("EQUIPPED").font(Theme.cinzel(9.6)).tracking(3).foregroundStyle(Theme.goldDim)
                if let w = run.equippedWeapon {
                    equippedRow("\(w.icon) \(w.name) · ATK \(w.weaponAttack.lowerBound)-\(w.weaponAttack.upperBound)", Theme.gold,
                                Color(hex: 0x1a1200), Theme.goldDim,
                                label: "Equipped weapon: \(w.name). Attack \(w.weaponAttack.lowerBound) to \(w.weaponAttack.upperBound). Press Unequip to remove.") {
                        model.unequipWeapon()
                    }
                }
                if let a = run.equippedArmor {
                    equippedRow("\(a.icon) \(a.name) · DEF +\(a.armorDefense)", Color(hex: 0x88aaff), Color(hex: 0x0a1220), Color(hex: 0x333344),
                                label: "Equipped armor: \(a.name). Defense plus \(a.armorDefense). Press Unequip to remove.") {
                        model.unequipArmor()
                    }
                }
                Text("INVENTORY").font(Theme.cinzel(9.6)).tracking(3).foregroundStyle(Theme.goldDim)
            }
            if !invSearch.isEmpty {
                Text("\(stacks.count) item\(stacks.count == 1 ? "" : "s") found for \"\(invSearch)\"")
                    .font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x666666))
            }
            if run.inventory.isEmpty {
                Text("Your satchel is empty.").font(Theme.crimson(12.8, italic: true)).foregroundStyle(Theme.textDim)
            } else if stacks.isEmpty {
                Text("Nothing in this category.").font(Theme.crimson(12.8, italic: true)).foregroundStyle(Theme.textDim)
            }
            ForEach(Array(stacks.enumerated()), id: \.offset) { _, s in
                itemRow(s.item, count: s.count, index: s.index, fav: favs.contains(s.item.name))
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 18)
        .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inventory")
    }

    private func equippedRow(_ text: String, _ color: Color, _ bg: Color, _ border: Color, label: String,
                             unequip: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(text).font(Theme.cinzel(11.5)).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(label)
            Button("Unequip", action: unequip).buttonStyle(SmallGhostStyle())
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(bg).overlay(Rectangle().stroke(border))
    }

    private func itemRow(_ item: Item, count: Int, index: Int, fav: Bool) -> some View {
        let usable = !item.isWeapon && !item.isArmor && !["relic", "material", "ring", "phoenix"].contains(item.type)
        let stat = item.isWeapon ? " Attack \(item.weaponAttack.lowerBound) to \(item.weaponAttack.upperBound)"
            : item.isArmor ? " Defense plus \(item.armorDefense)" : ""
        let shown = "\(item.icon) \(item.name)\(item.raritySymbol.map { " " + $0 } ?? "")\(count > 1 ? " (x\(count))" : "")"
            + (item.isWeapon ? " ATK \(item.weaponAttack.lowerBound)-\(item.weaponAttack.upperBound)" : item.isArmor ? " DEF +\(item.armorDefense)" : "")
        let key = "\(index)-\(item.name)"
        let action = item.isWeapon || item.isArmor ? " Press Equip to equip." : usable ? " Press Use to consume one." : " Press Drop to discard."
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(shown).font(Theme.cinzel(11.5)).foregroundStyle(item.rarityColor.flatMap(webColor) ?? Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("\(item.name)\(stat)\(count > 1 ? " You have \(count)." : ""). \(item.desc)\(action)")
                if !item.desc.isEmpty {
                    Button(openDetails.contains(key) ? "▲" : "?") {
                        if openDetails.contains(key) { openDetails.remove(key) } else {
                            openDetails.insert(key)
                            Feedback.announce("\(item.name). \(item.desc)")
                        }
                    }
                    .buttonStyle(SmallGhostStyle(color: Color(hex: 0x666666)))
                    .accessibilityLabel("Details for \(item.name): \(item.desc)")
                }
                if item.isWeapon || item.isArmor {
                    Button("Equip") { model.useItem(at: index) }.buttonStyle(SmallGhostStyle(color: Theme.goldDim))
                        .accessibilityLabel("Equip \(item.name)")
                } else if usable {
                    Button("Use") { model.useItem(at: index) }.buttonStyle(SmallGoldStyle())
                        .accessibilityLabel("Use \(item.name)")
                } else if item.type == "relic" {
                    Text("Passive").font(Theme.cinzel(10.4)).foregroundStyle(Theme.ash).opacity(0.6)
                        .accessibilityLabel("\(item.name) — passive relic, always active")
                } else {
                    Button("Drop") { model.drop(at: index) }.buttonStyle(SmallGhostStyle())
                        .accessibilityLabel("Drop \(item.name)")
                }
                Button(fav ? "★" : "☆") { toggleFavorite(item.name) }
                    .font(.system(size: 12)).foregroundStyle(fav ? Color(hex: 0xffcc00) : Color(hex: 0x444444))
                    .padding(.vertical, 3).padding(.horizontal, 7).overlay(Rectangle().stroke(Color(hex: 0x2a2a2a)))
                    .accessibilityLabel(fav ? "Remove from favorites: \(item.name)" : "Add to favorites: \(item.name)")
            }
            if openDetails.contains(key) {
                Text(item.desc).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x888888)).lineSpacing(4)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x050505)).overlay(Rectangle().stroke(Color(hex: 0x222222)))
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(Theme.bgStone).overlay(Rectangle().stroke(Theme.borderDim))
    }

    private func sortInventory() {
        model.sortInventory(favorites: favorites)
        Feedback.announce("Inventory sorted. Favorites first, then weapons, armor, potions, and materials.")
    }

    // MARK: Floor complete, flee, pause, run log, NG+ choice

    private var floorComplete: some View {
        let f = model.floorSummary
        let gold = max(0, run.gold - f.goldStart)
        return ZStack {
            Color.black.opacity(0.94).ignoresSafeArea().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("FLOOR \(run.floor) COMPLETE").font(Theme.cinzel(9.6)).tracking(3.8).foregroundStyle(Color(hex: 0x446688))
                    .padding(.bottom, 6)
                Text(model.roomTitle.isEmpty ? "Floor \(run.floor)" : model.roomTitle).font(Theme.cinzel(16)).foregroundStyle(Color(hex: 0x88aacc))
                    .padding(.bottom, 16)
                VStack(alignment: .leading, spacing: 6) {
                    statLine("⚔️ Enemies killed: ", "\(f.kills)", Color(hex: 0xe0c080))
                    statLine("💥 Damage dealt: ", "\(f.damageDealt)", Color(hex: 0xe0c080))
                    statLine("🏆 Best hit: ", "\(f.bestHit)", Color(hex: 0xe0c080))
                    statLine("❤️ Damage taken: ", "\(f.damageTaken)", Color(hex: 0xcc4444))
                    statLine("💊 HP healed: ", "\(f.hpHealed)", Color(hex: 0x44cc44))
                    statLine("💰 Gold earned: ", "\(gold)", Color(hex: 0xe0c080))
                }
                .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x666666))
                .padding(.bottom, 20)
                VStack(spacing: 10) {
                    Button { model.descend() } label: {
                        Text("⬇ Descend to Floor \(run.floor + 1)").font(Theme.cinzel(12.5)).foregroundStyle(Color(hex: 0x88aacc))
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Color(hex: 0x0a0a12)).overlay(Rectangle().stroke(Color(hex: 0x446688), lineWidth: 2))
                    }
                    .accessibilityLabel("Descend to floor \(run.floor + 1)")
                    if model.canWander {
                        Button { model.wander() } label: {
                            Text("🗺 Wander This Floor").font(Theme.cinzel(12.5)).foregroundStyle(Color(hex: 0x888888))
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x443a10)))
                        }
                        .accessibilityLabel("Wander this floor, explore 3 more rooms")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 380)
            .background(Color(hex: 0x08080a)).overlay(Rectangle().stroke(Color(hex: 0x444466)))
            .padding(20)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityLabel("Floor \(run.floor) complete")
        }
    }

    private func statLine(_ k: String, _ v: String, _ c: Color) -> some View {
        (Text(k) + Text(v).foregroundColor(c)).accessibilityElement(children: .combine)
    }

    private func askFlee() {
        askingFlee = true
        Feedback.announce("Flee dungeon? Press Flee to escape or Keep Fighting to continue. Your progress to floor \(run.floor) will be saved.")
    }

    private var fleeOverlay: some View {
        WebOverlay(danger: true) {
            OverlayTitle(text: "Flee the Dungeon?", red: true)
            OverlayText(text: "\(run.name) is on floor \(run.floor). Your progress will be saved and you can return later.")
            HStack(spacing: 10) {
                Button("Flee") {
                    askingFlee = false
                    model.fleeDungeon()
                    router.goTo(.menu)
                    Feedback.announce("You fled the dungeon. Progress saved at floor \(run.floor).")
                }
                .buttonStyle(WebButtonStyle(kind: .red))
                Button("Keep Fighting") { askingFlee = false }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
            }
        }
    }

    private func openPause() {
        if fighting { Feedback.announce("Cannot pause during combat. Finish the fight first."); return }
        paused = true
        Feedback.announce("Game paused. \(run.name). Floor \(run.floor). Options: Resume, Save, Settings, Quests, Main Menu.")
    }

    private var pauseOverlay: some View {
        WebOverlay {
            OverlayTitle(text: "⏸ Paused")
            VStack(spacing: 2) {
                Text(run.name).font(Theme.cinzel(14)).foregroundStyle(Color(hex: 0xe0c080))
                Text("Floor \(run.floor) · \(run.dungeon) · \(run.hp) HP").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x888888))
            }
            .accessibilityElement(children: .combine)
            VStack(spacing: 8) {
                Button("▶ Resume") { paused = false; Feedback.announce("Resumed.") }
                    .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                Button("💾 Save") { model.manualSave() }.buttonStyle(WebButtonStyle(kind: .ghost))
                Button("⚙ Settings") { paused = false; showSettings = true }.buttonStyle(WebButtonStyle(kind: .ghost))
                Button("📜 Quests") { paused = false; model.fleeDungeon(); router.goTo(.quests) }.buttonStyle(WebButtonStyle(kind: .ghost))
                Button("🏠 Main Menu") {
                    paused = false
                    model.fleeDungeon()
                    router.goTo(.menu)
                    Feedback.announce("Returned to main menu. Progress saved.")
                }
                .buttonStyle(WebButtonStyle(kind: .ghost))
            }
        }
    }

    private var runLogOverlay: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text("📜 Run Log").font(Theme.decorative(16)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.log) { line in
                            Text(line.text).font(Theme.crimson(13)).foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Button("← Close") { showRunLog = false }.buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                    .accessibilityLabel("Close run log")
            }
            .padding(20)
            .frame(maxWidth: 500, maxHeight: 600)
            .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Theme.borderDim))
            .padding(16)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { Feedback.announce("Run log. \(model.log.count) entries, newest first.") }
    }

    private var ngPlusChoice: some View {
        WebOverlay {
            OverlayTitle(text: "⬆ Your Journey Continues")
            OverlayText(text: "The dungeon has been conquered. What will you do?")
            VStack(spacing: 10) {
                if model.canContinueJourney {
                    Button {
                        choosingPath = false
                        model.continueJourney()
                    } label: {
                        VStack(spacing: 3) {
                            Text("➡ Continue Journey")
                            Text("Descend deeper — face the next dungeon").font(Theme.crimson(11, italic: true)).textCase(nil)
                        }
                    }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                    .accessibilityLabel("Continue Journey — move to the next dungeon with your current character")
                }
                Button {
                    choosingPath = false
                    model.startNewGamePlus()
                } label: {
                    VStack(spacing: 3) {
                        Text("🔄 New Game+")
                        Text("Replay this dungeon — harder enemies await").font(Theme.crimson(11, italic: true)).textCase(nil)
                    }
                }
                .buttonStyle(WebButtonStyle(kind: .gold))
                .accessibilityLabel("New Game Plus — replay this dungeon with harder enemies, keep your character")
                Button("Decide Later") { choosingPath = false }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Decide later and return to the end screen")
            }
        }
    }

    private func notYet(_ what: String) {
        Sound.sfx("sfx-select")
        Feedback.announce("\(what) isn't in the Swift version yet. Coming soon.")
    }
}

// MARK: - Pieces

/// A thin rounded progress bar like .dg-hp-bar and .dg-xp-bar.
struct Bar: View {
    let value: Double
    let colors: [Color]
    let track: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: value)
        .accessibilityHidden(true)
    }
}

/// .dg-btn, .dg-btn.accent, .dg-act-btn, .dg-act-btn.red, .dg-combat-btn and .dg-skill-btn
struct DungeonButtonStyle: ButtonStyle {
    enum Kind { case compass, compassAccent, action, red, combat, skill }
    let kind: Kind
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        let (fg, bg, border): (Color, Color, Color) = {
            switch kind {
            case .compass: return (down ? Theme.goldBright : Theme.ash, down ? Color(hex: 0x231c12) : Theme.bgStone, down ? Theme.goldDim : Theme.borderDim)
            case .compassAccent: return (down ? Theme.goldBright : Theme.goldDim, down ? Color(hex: 0x231c12) : Theme.bgStone, Theme.borderGlow)
            case .action: return (down ? Theme.gold : Theme.ash, Theme.bgStone, down ? Theme.goldDim : Theme.borderDim)
            case .red: return (down ? Color(hex: 0xe0a0a0) : Color(hex: 0xc08080), down ? Theme.blood.opacity(0.15) : Theme.bgStone, Theme.blood)
            case .combat: return (down ? Color(hex: 0xf0c0c0) : Color(hex: 0xd4a0a0), Theme.blood.opacity(down ? 0.25 : 0.1), down ? Theme.bloodBright : Theme.blood)
            case .skill: return (down ? Color(hex: 0xc0b0f0) : Color(hex: 0xa090e0),
                                 Color(red: 80 / 255, green: 60 / 255, blue: 160 / 255).opacity(down ? 0.3 : 0.15),
                                 down ? Color(hex: 0x7060c0) : Color(hex: 0x4a3890))
            }
        }()
        configuration.label
            .font(Theme.cinzel(10.9))
            .tracking(kind == .combat || kind == .skill ? 1.1 : 0.9)
            .textCase(.uppercase)
            .foregroundStyle(fg)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .padding(.horizontal, kind == .compass || kind == .compassAccent ? 6 : kind == .skill ? 14 : 16)
            .frame(maxWidth: kind == .compass || kind == .compassAccent ? .infinity : nil, minHeight: 44)
            .background(bg)
            .overlay(Rectangle().stroke(border))
            .opacity(enabled ? 1 : (kind == .skill ? 0.3 : 0.35))
    }
}

struct SmallGhostStyle: ButtonStyle {
    var color: Color = Theme.ash
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.cinzel(10)).tracking(1.5).textCase(.uppercase)
            .foregroundStyle(configuration.isPressed ? Theme.textPrimary : color)
            .padding(.vertical, 3).padding(.horizontal, 8).frame(minHeight: 32)
            .overlay(Rectangle().stroke(configuration.isPressed ? Theme.ash : Theme.borderDim))
    }
}

struct SmallGoldStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.cinzel(10.4, weight: .bold)).tracking(1.5).textCase(.uppercase)
            .foregroundStyle(Theme.bgVoid)
            .padding(.vertical, 3).padding(.horizontal, 10).frame(minHeight: 32)
            .background(configuration.isPressed ? Theme.goldBright : Theme.gold)
    }
}
