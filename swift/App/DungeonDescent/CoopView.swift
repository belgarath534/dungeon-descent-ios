import SwiftUI
import DungeonCore

/// #screen-coop: host or join a co-op run, the lobby, the fight and the end.
struct CoopView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @StateObject private var model = CoopModel()
    @State private var charIndex = 0
    @State private var dungeonIndex = 0
    @State private var joinCode = ""
    private let teal = Color(hex: 0x66ddcc)

    /// Dungeons a co-op run can go to: the first six (the rest need unlocking).
    private var dungeons: [String] { Array(GameData.dungeons.prefix(6)) }

    var body: some View {
        WebScreen {
            Button("← Menu") { model.leave(); router.goTo(.menu) }
                .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Leave co-op and go back to the main menu")
            Text("🤝 Co-op Dungeon").font(Theme.decorative(22)).foregroundStyle(teal).accessibilityAddTraits(.isHeader)
            switch model.stage {
            case .choose: choose
            case .lobby: lobby
            case .playing: fight
            case .over: over
            }
        }
        .onAppear {
            model.game = game
            Feedback.announce("Co-op Dungeon. Fight through ten floors with up to three friends, on the web or the app. Choose a character, then host a room or join one with its code.")
        }
        .onDisappear { model.stop() }
    }

    private func header(_ s: String) -> some View {
        Text(s).font(Theme.cinzel(11)).tracking(2).foregroundStyle(Theme.goldDim).accessibilityAddTraits(.isHeader).padding(.top, 6)
    }

    // MARK: Choose

    @ViewBuilder private var choose: some View {
        if game.characters.isEmpty {
            Text("Create a character first.").font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary)
        } else {
            header("YOUR CHARACTER")
            ForEach(Array(game.characters.enumerated()), id: \.offset) { i, ch in
                Button("\(Prestige.label(ch)) — \(ch.cls) (Lv \(ch.persistLevel ?? 1))" as String) {
                    charIndex = i
                    Feedback.announce("\(ch.name) selected.")
                }
                .buttonStyle(WebButtonStyle(kind: i == charIndex ? .gold : .ghost))
                .accessibilityAddTraits(i == charIndex ? .isSelected : [])
            }
            header("HOST A ROOM")
            ForEach(dungeons.indices, id: \.self) { i in
                Button(dungeons[i]) {
                    dungeonIndex = i
                    Feedback.announce("\(dungeons[i]) selected.")
                }
                .buttonStyle(WebButtonStyle(kind: i == dungeonIndex ? .gold : .ghost))
                .accessibilityAddTraits(i == dungeonIndex ? .isSelected : [])
            }
            Button("🤝 Host a Room") { model.host(game.characters[charIndex], dungeon: dungeons[dungeonIndex]) }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .accessibilityLabel("Host a co-op room in \(dungeons[dungeonIndex])" as String)
            header("JOIN A FRIEND")
            HStack {
                TextField("Room code", text: $joinCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(Theme.cinzel(14)).padding(8).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
                    .accessibilityLabel("Room code, 4 letters")
                Button("Join") { model.join(joinCode, game.characters[charIndex]) }
                    .buttonStyle(WebButtonStyle(kind: .gold)).accessibilityLabel("Join the room")
            }
            if !model.status.isEmpty { Text(model.status).font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.gold) }
        }
    }

    // MARK: Lobby

    @ViewBuilder private var lobby: some View {
        Text("Room code: \(model.code ?? "")" as String).font(Theme.cinzel(18)).foregroundStyle(teal)
            .accessibilityLabel("Room code: \((model.code ?? "").map(String.init).joined(separator: " "))" as String)
        Text("\(model.dungeon) · up to \(Coop.maxPlayers) players" as String).font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
        header("THE PARTY")
        ForEach(model.party, id: \.id) { p in
            Text("\(p.ready || (model.isHost && p.id == model.myId) ? "✓" : "…") \(p.name) — \(p.cls), Lv \(p.level), \(p.maxHp) HP\(p.id == model.myId ? " (you)" : "")" as String)
                .font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary)
        }
        if model.isHost {
            Button("⚔ Start the Run") { model.start() }.buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
        } else if !(model.me?.ready ?? false) {
            Button("✓ Ready") { model.ready() }.buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
        } else {
            Text("Waiting for the host to start.").font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textDim)
        }
        Button("Leave the Room") { model.leave() }.buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
        if !model.status.isEmpty { Text(model.status).font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.gold) }
    }

    // MARK: The fight

    @ViewBuilder private var fight: some View {
        Text("Floor \(model.floor) of \(Coop.floors) · Fight \(model.foe?.boss == true ? "BOSS" : "\(model.fight) of \(Coop.fightsPerFloor)") · \(model.dungeon)" as String).font(Theme.cinzel(12)).foregroundStyle(Theme.gold)
        if let f = model.foe {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(f.icon) \(f.name)\(f.boss ? " — BOSS, phase \(f.phase)" : "")\(f.stun > 0 ? " · stunned" : "")" as String).font(Theme.cinzel(14)).foregroundStyle(Color(hex: 0xe08080))
                bar(Double(f.hp) / Double(f.maxHp), Color(hex: 0xcc3333))
                Text("\(f.hp) / \(f.maxHp) HP" as String).font(Theme.cinzel(11)).foregroundStyle(Theme.textSecondary)
            }
            .padding(10).overlay(Rectangle().stroke(Color(hex: 0x5a2020)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(f.name)\(f.boss ? ", the boss, phase \(f.phase) of 3" : ""). \(f.hp) of \(f.maxHp) HP.\(f.stun > 0 ? " Stunned." : "")" as String)
        }
        header("THE PARTY")
        ForEach(model.party, id: \.id) { p in
            VStack(alignment: .leading, spacing: 2) {
                Text("\(p.name)\(p.id == model.myId ? " (you)" : "")\(p.alive ? "" : " — DOWN")" as String).font(Theme.cinzel(12))
                    .foregroundStyle(p.alive ? Theme.ashLight : Color(hex: 0x885555))
                bar(Double(p.hp) / Double(p.maxHp), Color(hex: 0x44cc44))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(p.name)\(p.id == model.myId ? ", you" : ""). " + (p.alive ? "\(p.hp) of \(p.maxHp) HP, \(p.sp) SP, \(p.potions) potions\(p.shield > 0 ? ", \(p.shield) shield" : "")." : "Down. A potion can revive them."))
        }
        if model.shopOpen {
            header("THE MERCHANT")
            Text("Potions are \(Coop.potionPrice) gold each, paid with your own gold. They're added when the next floor starts." as String)
                .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
            Button("🧪 Buy a Potion (\(Coop.potionPrice)g)" as String) { model.buyPotion() }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .accessibilityLabel("Buy a potion for \(Coop.potionPrice) gold. You have \(game.wallet.gold) gold\(model.bought > 0 ? ", \(model.bought) bought" : "")." as String)
        } else if let m = model.me, m.alive {
            actions(m)
        } else {
            Text("You're down. A friend can revive you with a potion, or you get back up on the next floor.")
                .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textDim)
        }
        header("WHAT HAPPENED")
        VStack(alignment: .leading, spacing: 3) {
            ForEach(model.log.prefix(12), id: \.n) { l in
                Text(l.text).font(Theme.crimson(13)).foregroundStyle(Theme.textSecondary)
            }
        }
        Button("Leave the Run") { model.leave() }.buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
    }

    /// Your buttons: the four basics, your skills, your gun, and team moves
    /// for each friend. They stay on screen after you choose (dimmed), so
    /// VoiceOver stays on the one you pressed instead of jumping away.
    @ViewBuilder private func actions(_ m: Coop.Player) -> some View {
        let friends = model.party.filter { $0.id != model.myId }
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                actionButton(.attack, "⚔ Attack", "Attack, \(m.atkLo) to \(m.atkHi) damage", .red, m)
                actionButton(.heavy, "💥 Heavy", "Heavy strike, much harder but can miss", .red, m)
            }
            HStack(spacing: 8) {
                actionButton(.defend, "🛡 Defend", "Defend: strike for half and take half", .ghost, m)
                actionButton(.potion, "🧪 Potion (\(m.potions))", "Potion, heal 40 percent. \(m.potions) left.", .ghost, m, off: m.potions <= 0)
            }
            if !m.skills.isEmpty {
                header("SKILLS · \(m.sp) of \(m.maxSp) SP")
                ForEach(m.skills, id: \.id) { sk in
                    actionButton(.skill(sk.id), "\(sk.icon) \(sk.name) (\(sk.sp) SP)", "\(sk.name), \(sk.sp) SP: \(sk.summary)", .gold, m, off: m.sp < sk.sp)
                }
            }
            if m.hasGun {
                actionButton(.gun, "🔫 \(m.gunName) (\(m.shots))", "Fire \(m.gunName), \(m.gunLo) to \(m.gunHi) damage. \(m.shots) shots left this fight.", .red, m, off: m.shots <= 0)
            }
            if !friends.isEmpty {
                header("TEAM MOVES")
                ForEach(friends, id: \.id) { f in
                    if f.alive {
                        actionButton(.protect(f.id), "🛡 Protect \(f.name)", "Protect \(f.name): take the enemy's hit for them this round, at half damage", .ghost, m)
                    } else {
                        actionButton(.revive(f.id), "💫 Revive \(f.name)", "Revive \(f.name) with one of your potions. \(m.potions) left.", .gold, m, off: m.potions <= 0)
                    }
                }
            }
        }
        if let a = model.myAction {
            Text("You chose \(model.name(of: a)). Waiting for \(model.waitingOn.isEmpty ? "the round" : model.waitingOn.joined(separator: ", "))." as String)
                .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textDim)
        }
    }

    private func actionButton(_ a: Coop.Action, _ title: String, _ label: String, _ kind: WebButtonStyle.Kind,
                              _ m: Coop.Player, off: Bool = false) -> some View {
        let chosen = model.myAction == a
        return Button(title) { model.act(a) }
            .buttonStyle(WebButtonStyle(kind: chosen ? .gold : kind))
            .frame(maxWidth: .infinity)
            .disabled(model.myAction != nil || off)
            .accessibilityLabel(chosen ? "\(label). Chosen." : label)
    }

    private func bar(_ v: Double, _ c: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: 0x111111))
                Rectangle().fill(c).frame(width: g.size.width * max(0, min(1, v)))
            }
        }
        .frame(height: 8).accessibilityHidden(true)
    }

    // MARK: The end

    @ViewBuilder private var over: some View {
        Text(model.roomStatus == "won" ? "👑 VICTORY" : "The run is over")
            .font(Theme.decorative(20)).foregroundStyle(model.roomStatus == "won" ? Color(hex: 0x44ff88) : Color(hex: 0xaa4444))
            .accessibilityAddTraits(.isHeader)
        if !model.status.isEmpty { Text(model.status).font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary) }
        Button("🤝 Play Again") { model.leave() }.buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
        Button("← Main Menu") { model.leave(); router.goTo(.menu) }.buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
    }
}
