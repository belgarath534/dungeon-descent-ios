import SwiftUI
import DungeonCore

@MainActor
struct RunView: View {
    @StateObject private var model: RunModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingInventory = false

    init(game: GameModel, characterIndex: Int, resume: Bool) {
        _model = StateObject(wrappedValue: RunModel(game: game, characterIndex: characterIndex, resume: resume))
    }

    var body: some View {
        let run = model.run
        List {
            Section {
                StatusRow(run: run)
            }

            if !model.roomTitle.isEmpty || !model.roomText.isEmpty {
                Section(model.roomTitle.isEmpty ? "Room" : model.roomTitle) {
                    if !model.roomText.isEmpty {
                        Text(model.roomText).font(.callout).italic()
                    }
                }
            }

            if let e = run.enemy {
                Section("Enemy") {
                    EnemyRow(enemy: e, bossPhase: run.bossPhase)
                }
            }

            Section("Actions") { actions }

            if model.phase == .fighting && !model.skills.isEmpty {
                Section("Skills · \(run.sp) of \(run.maxSp) SP") {
                    ForEach(model.skills, id: \.effect) { s in
                        let cost = model.skillCost(s)
                        Button {
                            model.useSkill(s.effect)
                        } label: {
                            OptionRow(title: "\(s.icon) \(s.name) · \(cost) SP", detail: s.desc)
                        }
                        .disabled(cost > run.sp)
                        .accessibilityLabel("\(s.name). \(s.tier) skill. \(s.desc) Costs \(cost) SP.")
                        .accessibilityHint(cost > run.sp ? "Not enough SP. You need \(cost - run.sp) more." : "")
                    }
                }
            }

            if !run.skillChoices.isEmpty {
                Section {
                    ForEach(run.skillChoices, id: \.self) { effect in
                        if let s = Skills.skill(effect, cls: run.cls) {
                            Button {
                                model.pickSkill(effect)
                            } label: {
                                OptionRow(title: "\(s.icon) \(s.name) · \(s.tier) · \(s.spCost) SP", detail: s.desc)
                            }
                            .accessibilityLabel("\(s.name). \(s.tier). \(s.desc) Costs \(s.spCost) SP.")
                            .accessibilityHint("Learns this skill. The others are gone.")
                        }
                    }
                } header: {
                    Text("Choose a new skill")
                } footer: {
                    Text("Pick one. The others won't be offered again this run.")
                }
            }

            if model.phase == .shopping {
                Section {
                    ForEach(model.shop) { entry in
                        Button {
                            model.buy(entry.id)
                        } label: {
                            ShopRow(entry: entry, price: model.price(entry), gold: run.gold)
                        }
                        .disabled(entry.sold)
                    }
                    Button("Refresh stock for \(Inventory.refreshCost) gold") { model.refreshShop() }
                    Button("Leave the merchant") { model.leaveShop() }
                } header: {
                    Text("The Wandering Merchant · \(run.gold) gold")
                } footer: {
                    if model.hour >= 20 || model.hour < 8 {
                        Text("Night discount: 25% off.")
                    }
                }
            }

            if run.levelPoints > 0 {
                Section("Level points: \(run.levelPoints)") {
                    ForEach(Progression.Stat.allCases, id: \.self) { stat in
                        Button {
                            model.spend(stat)
                        } label: {
                            OptionRow(title: stat.label, detail: stat.summary)
                        }
                        .accessibilityHint("Spends 1 level point.")
                    }
                }
            }

            Section("Log") {
                ForEach(model.log.prefix(40)) { line in
                    Text(line.text).font(.callout)
                }
            }
        }
        .navigationTitle(run.dungeon)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingInventory = true
                } label: {
                    Label("Inventory, \(run.inventory.count) items", systemImage: "bag")
                }
            }
        }
        .sheet(isPresented: $showingInventory) {
            NavigationStack { InventoryView(model: model) }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch model.phase {
        case .exploring:
            Button(model.bossRoomNext ? "Face the boss" : "Explore the next room") { model.enterRoom() }
            searchButton
        case .fighting:
            Button("Attack") { model.act(.attack) }
                .accessibilityHint("\(Int(((0.10 + model.run.critBonus) * 100).rounded()))% chance of a critical hit.")
            Button("Heavy strike") { model.act(.heavy) }
                .accessibilityHint("70% more damage, but misses 30% of the time.")
            Button("Defend") { model.act(.defend) }
                .accessibilityHint("Half damage, and blocks 4 more on the counter-attack.")
            if model.run.enemy?.isBoss != true {
                Button("Flee") { model.act(.flee) }
                    .accessibilityHint(fleeHint)
            }
            Button("Use an item") { showingInventory = true }
        case .floorCleared:
            Button("Descend to floor \(model.run.floor + 1)") { model.descend() }
            if model.canWander {
                Button("Wander: explore 3 more rooms") { model.wander() }
            }
            searchButton
        case .shopping:
            Text("Buy what you need below, then leave the merchant to keep exploring.")
                .font(.footnote)
        case .event:
            if let ev = model.pendingEvent {
                Text(ev.text).font(.callout)
                ForEach(Array(ev.choices.enumerated()), id: \.offset) { i, label in
                    Button(label) { model.chooseEvent(i) }
                }
            }
        case .victory:
            Text("Victory! You have conquered \(model.run.dungeon).").font(.headline)
            if model.canContinueJourney {
                Button("Continue Journey: the next dungeon, keeping your level") { model.continueJourney() }
            }
            Button("New Game+: this dungeon again, with stronger enemies") { model.startNewGamePlus() }
            Button("Return to characters") { dismiss() }
        case .defeat:
            Text(model.characterGone ? "\(model.run.name) is gone forever." : "Defeated. All lives lost.").font(.headline)
            Button("Return to characters") { dismiss() }
        }
    }

    private var searchButton: some View {
        Button(model.run.searched ? "Search the room (already searched)" : "Search the room") { model.search() }
            .disabled(model.run.searched || model.run.roomsOnFloor == 0)
            .accessibilityHint(model.run.prof == "Thief" ? "50% chance to find something. Traps are possible." : "35% chance to find something. Traps are possible.")
    }

    private var fleeHint: String {
        let r = model.run
        if r.swiftTurns > 0 || r.runeSpeed { return "Guaranteed to succeed." }
        let pct = Int((((r.hasFleeRing ? 0.75 : 0.45) + r.fleeBonus) * 100).rounded())
        return "\(min(pct, 100))% chance. If it fails, the enemy attacks."
    }
}

struct StatusRow: View {
    let run: Run

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(run.name) · Level \(run.level)").font(.headline)
            ProgressView(value: Double(run.hp), total: Double(max(run.maxHp, 1)))
                .tint(.green)
            HStack {
                Text("HP \(run.hp)/\(run.maxHp)")
                Spacer()
                Text("Lives \(run.lives)")
                Spacer()
                Text("Floor \(run.floor)")
                Spacer()
                Text("\(run.gold)g")
            }
            .font(.subheadline)
            Text("SP \(run.sp)/\(run.maxSp) · XP \(run.xp)/\(Progression.xpNeeded(atLevel: run.level)) · ATK \(run.atk.lowerBound + run.totalAtkBonus)–\(run.atk.upperBound + run.totalAtkBonus) · DEF \(run.totalDef)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !effects.isEmpty {
                Text(effects.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Theme.gold)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var effects: [String] {
        var e: [String] = []
        if run.tempAtkTurns > 0 { e.append("+\(run.tempAtk) attack, \(run.tempAtkTurns) turns") }
        if run.tempDefTurns > 0 { e.append("+\(run.tempDef) defense, \(run.tempDefTurns) turns") }
        if run.swiftTurns > 0 { e.append("flee guaranteed, \(run.swiftTurns) turns") }
        if run.luckKills > 0 { e.append("double gold, \(run.luckKills) kills") }
        if run.poisonTurns > 0 { e.append("poisoned, \(run.poisonTurns) turns") }
        if run.frozen { e.append("frozen") }
        let f = run.fight
        if f.shield > 0 { e.append("shield \(f.shield)") }
        if f.dodges > 0 { e.append("dodge next \(f.dodges == 1 ? "attack" : "\(f.dodges) attacks")") }
        if f.reduceTurns > 0 { e.append("\(Int(f.reduce * 100))% less damage, \(f.reduceTurns) turns") }
        if f.buffTurns > 0 { e.append("skill boost, \(f.buffTurns) turns") }
        if f.empowerCount > 0 { e.append("next \(f.empowerCount == 1 ? "attack" : "\(f.empowerCount) attacks") ×\(f.empower)") }
        if f.unstoppableTurns > 0 { e.append("cannot die, \(f.unstoppableTurns) turns") }
        if f.regenTurns > 0 { e.append("regenerating \(f.regen)") }
        if run.resurrection { e.append("resurrection ready") }
        if run.freeSkills > 0 { e.append("\(run.freeSkills) free skills") }
        return e
    }

    private var spoken: String {
        var s = "\(run.name), level \(run.level). \(run.hp) of \(run.maxHp) HP. \(run.lives) \(run.lives == 1 ? "life" : "lives"). "
        s += "Floor \(run.floor), room \(run.roomsOnFloor) of \(run.floorRoomsNeeded). \(run.gold) gold. "
        s += "Attack \(run.atk.lowerBound + run.totalAtkBonus) to \(run.atk.upperBound + run.totalAtkBonus), defense \(run.totalDef). "
        s += "\(run.sp) of \(run.maxSp) SP. \(run.xp) of \(Progression.xpNeeded(atLevel: run.level)) XP."
        if !effects.isEmpty { s += " " + effects.joined(separator: ". ") + "." }
        return s
    }
}

struct EnemyRow: View {
    let enemy: Enemy
    let bossPhase: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(enemy.icon) \(enemy.name)\(enemy.isBoss ? " (Boss, phase \(bossPhase))" : "")").font(.headline)
            ProgressView(value: Double(enemy.hp), total: Double(max(enemy.maxHp, 1)))
                .tint(Theme.blood)
            Text("\(enemy.hp) of \(enemy.maxHp) HP · hits for \(enemy.currentAtk.lowerBound)–\(enemy.currentAtk.upperBound)\(conditions.isEmpty ? "" : " · " + conditions.joined(separator: ", "))")
                .font(.subheadline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(enemy.name)\(enemy.isBoss ? ", boss, phase \(bossPhase)" : ""). \(enemy.hp) of \(enemy.maxHp) HP. Hits for \(enemy.currentAtk.lowerBound) to \(enemy.currentAtk.upperBound).\(conditions.isEmpty ? "" : " " + conditions.joined(separator: ". ") + ".")")
    }

    private var conditions: [String] {
        var c: [String] = []
        if enemy.cursedTurns > 0 { c.append("cursed \(enemy.cursedTurns) turns") }
        if enemy.stunTurns > 0 { c.append("stunned") }
        if enemy.dotTurns > 0 { c.append("taking \(enemy.dotDamage) per turn for \(enemy.dotTurns) turns") }
        return c
    }
}

struct ShopRow: View {
    let entry: Inventory.ShopItem
    let price: Int
    let gold: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(entry.item.icon) \(entry.item.name)")
                Spacer()
                Text(entry.sold ? "Sold" : "\(price)g")
                    .foregroundStyle(entry.sold ? Color.secondary : (gold >= price ? Theme.gold : Theme.blood))
            }
            Text(entry.item.desc).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.item.name). \(entry.item.desc) \(entry.sold ? "Sold." : "\(price) gold.")\(!entry.sold && gold < price ? " Not enough gold." : "")")
        .accessibilityHint(entry.sold ? "" : "Buys this item.")
    }
}

@MainActor
struct InventoryView: View {
    @ObservedObject var model: RunModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let run = model.run
        List {
            Section("Equipped") {
                if let w = run.equippedWeapon {
                    Button {
                        model.unequipWeapon()
                    } label: {
                        OptionRow(title: "\(w.icon) \(w.name)", detail: "Weapon · attack \(w.weaponAttack.lowerBound)–\(w.weaponAttack.upperBound)")
                    }
                    .accessibilityHint("Unequips this weapon.")
                } else {
                    Text("No weapon").foregroundStyle(.secondary)
                }
                if let a = run.equippedArmor {
                    Button {
                        model.unequipArmor()
                    } label: {
                        OptionRow(title: "\(a.icon) \(a.name)", detail: "Armor · +\(a.armorDefense) defense")
                    }
                    .accessibilityHint("Unequips this armor.")
                } else {
                    Text("No armor").foregroundStyle(.secondary)
                }
            }

            Section("Bag") {
                if run.inventory.isEmpty {
                    Text("Your bag is empty.").foregroundStyle(.secondary)
                }
                ForEach(Array(run.inventory.enumerated()), id: \.offset) { index, item in
                    Button {
                        model.useItem(at: index)
                        if model.phase == .fighting || model.phase == .victory { dismiss() }
                    } label: {
                        OptionRow(title: "\(item.icon) \(item.name)", detail: detail(item))
                    }
                    .accessibilityHint(item.isWeapon || item.isArmor ? "Equips this." : "Uses this.")
                }
            }
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func detail(_ item: Item) -> String {
        if item.isWeapon { return "Weapon · attack \(item.weaponAttack.lowerBound)–\(item.weaponAttack.upperBound). \(item.desc)" }
        if item.isArmor { return "Armor · +\(item.armorDefense) defense. \(item.desc)" }
        return item.desc
    }
}
