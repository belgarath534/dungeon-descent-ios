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
                Button("\(Prestige.label(ch)) — \(ch.cls) (Lv \(ch.persistLevel ?? 1))") {
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
                .accessibilityLabel("Host a co-op room in \(dungeons[dungeonIndex])")
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
        Text("Room code: \(model.code ?? "")").font(Theme.cinzel(18)).foregroundStyle(teal)
            .accessibilityLabel("Room code: \((model.code ?? "").map(String.init).joined(separator: " "))")
        Text("\(model.dungeon) · up to \(Coop.maxPlayers) players").font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
        header("THE PARTY")
        ForEach(model.party, id: \.id) { p in
            Text("\(p.ready || (model.isHost && p.id == model.myId) ? "✓" : "…") \(p.name) — \(p.cls), Lv \(p.level), \(p.maxHp) HP\(p.id == model.myId ? " (you)" : "")")
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
        Text("Floor \(model.floor) of \(Coop.floors) · \(model.dungeon)").font(Theme.cinzel(12)).foregroundStyle(Theme.gold)
        if let f = model.foe {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(f.icon) \(f.name)\(f.boss ? " — BOSS" : "")").font(Theme.cinzel(14)).foregroundStyle(Color(hex: 0xe08080))
                bar(Double(f.hp) / Double(f.maxHp), Color(hex: 0xcc3333))
                Text("\(f.hp) / \(f.maxHp) HP").font(Theme.cinzel(11)).foregroundStyle(Theme.textSecondary)
            }
            .padding(10).overlay(Rectangle().stroke(Color(hex: 0x5a2020)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(f.name)\(f.boss ? ", the boss" : ""). \(f.hp) of \(f.maxHp) HP.")
        }
        header("THE PARTY")
        ForEach(model.party, id: \.id) { p in
            VStack(alignment: .leading, spacing: 2) {
                Text("\(p.name)\(p.id == model.myId ? " (you)" : "")\(p.alive ? "" : " — DOWN")").font(Theme.cinzel(12))
                    .foregroundStyle(p.alive ? Theme.ashLight : Color(hex: 0x885555))
                bar(Double(p.hp) / Double(p.maxHp), Color(hex: 0x44cc44))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(p.name)\(p.id == model.myId ? ", you" : ""). " + (p.alive ? "\(p.hp) of \(p.maxHp) HP. \(p.potions) potions." : "Down until the next floor."))
        }
        if let m = model.me, m.alive {
            if let a = model.myAction {
                Text("You chose \(a.label.dropFirst(2)). Waiting for \(model.waitingOn.isEmpty ? "the round" : model.waitingOn.joined(separator: ", ")).")
                    .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textDim)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Coop.Action.allCases, id: \.self) { a in
                        Button(a == .potion ? "\(a.label) (\(m.potions))" : a.label) { model.act(a) }
                            .buttonStyle(WebButtonStyle(kind: a == .attack || a == .heavy ? .red : .ghost))
                            .accessibilityLabel(actionLabel(a, m))
                    }
                }
            }
        } else {
            Text("You're down. You get back up on the next floor.").font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textDim)
        }
        header("WHAT HAPPENED")
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(model.log.prefix(12).enumerated()), id: \.offset) { _, l in
                Text(l).font(Theme.crimson(13)).foregroundStyle(Theme.textSecondary)
            }
        }
        Button("Leave the Run") { model.leave() }.buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
    }

    private func actionLabel(_ a: Coop.Action, _ m: Coop.Player) -> String {
        switch a {
        case .attack: return "Attack, \(m.atkLo) to \(m.atkHi) damage"
        case .heavy: return "Heavy strike, much harder but can miss"
        case .defend: return "Defend: strike for half and take half"
        case .potion: return "Potion, heal 40 percent. \(m.potions) left."
        }
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
