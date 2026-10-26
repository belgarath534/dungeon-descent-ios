import SwiftUI
import DungeonCore

/// The web version's #screen-multiplayer (PVP ARENA).
@MainActor
struct PvPView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @StateObject private var arena = PvPArena()
    @State private var codeDraft = ""

    var body: some View {
        WebScreen {
            VStack(spacing: 4) {
                Text("⚔️ PVP ARENA").font(Theme.decorative(14.4)).foregroundStyle(Theme.gold)
                    .accessibilityAddTraits(.isHeader)
                Text("BETA — PLAYER VS PLAYER").font(Theme.cinzel(8.8)).tracking(2.6).foregroundStyle(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity).padding(.bottom, 12)

            if arena.stage == .lobby { lobby }

            if !arena.status.isEmpty {
                Text(arena.status).font(Theme.cinzel(11.2)).foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center).lineSpacing(6).frame(maxWidth: .infinity, minHeight: 40)
            }

            if let c = arena.code, arena.stage == .room {
                VStack(spacing: 8) {
                    Text("YOUR ROOM CODE").font(Theme.cinzel(8.8)).tracking(2.6).foregroundStyle(.white.opacity(0.3))
                    Text(c).font(Theme.decorative(44)).tracking(18).foregroundStyle(Theme.gold)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Room code \(c.map(String.init).joined(separator: " "))")
            }

            if !arena.fighters.isEmpty && arena.stage != .lobby { players }

            if arena.stage == .room {
                Button(arena.readyPressed ? "⏳ Waiting for opponent..." : "⚔️ Ready — FIGHT!") { arena.ready() }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                    .frame(maxWidth: .infinity)
                    .disabled(arena.readyPressed)
                    .accessibilityLabel("Ready to fight")
            }

            if arena.stage == .battle || arena.stage == .over { battleLog }
            if arena.stage == .battle { actions }
            if arena.stage == .over {
                Button("🔄 Rematch") { arena.rematch() }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Request a rematch")
            }

            Button("← Leave Arena") {
                arena.leave()
                Sound.track("menu")
                router.goTo(.menu)
            }
            .buttonStyle(WebButtonStyle(kind: .ghost))
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .accessibilityLabel("Leave arena and return to main menu")
        }
        .onAppear { arena.status = "Connected. Select a character to begin."; Feedback.announce(arena.status) }
        .onDisappear { if arena.stage != .lobby { arena.leave() } }
    }

    // MARK: Lobby

    private var lobby: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SELECT YOUR WARRIOR").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
            if game.characters.isEmpty {
                Text("No characters found. Create one in solo mode first.").font(Theme.cinzel(11.2)).foregroundStyle(.white.opacity(0.4))
            }
            ForEach(game.characters, id: \.created) { ch in
                let hp = GameData.classInfo(ch.cls).maxHp
                let chosen = arena.character?.created == ch.created
                Button { arena.select(ch) } label: {
                    Text("\(chosen ? "✓ " : "")\(ch.name) — \(ch.race) \(ch.cls) · Lv \(ch.persistLevel ?? 1) · HP \(hp)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(WebButtonStyle(kind: chosen ? .gold : .ghost))
                .accessibilityLabel("Select \(ch.name) for PVP battle")
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
            Button("🏟️ Create Room") { arena.create() }
                .buttonStyle(WebButtonStyle(kind: .gold))
                .frame(maxWidth: .infinity)
                .disabled(arena.character == nil)
                .accessibilityLabel("Create a new PVP room and get a code to share")
                .padding(.top, 8)
            Text("— OR —").font(Theme.cinzel(9.6)).tracking(2.6).foregroundStyle(.white.opacity(0.3)).frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                TextField("Room code", text: $codeDraft)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(Theme.cinzel(19)).tracking(6).multilineTextAlignment(.center).foregroundStyle(.white)
                    .padding(10).background(Color(hex: 0x0a0a14)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                    .onChange(of: codeDraft) { v in if v.count > 4 { codeDraft = String(v.prefix(4)) } }
                    .accessibilityLabel("Enter 4 character room code to join opponent")
                Button("Join") { arena.join(codeDraft) }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                    .disabled(arena.character == nil)
                    .accessibilityLabel("Join room with code")
            }
        }
    }

    // MARK: Battle

    private var players: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WARRIORS").font(Theme.cinzel(8.8)).tracking(2.6).foregroundStyle(.white.opacity(0.3)).padding(.bottom, 6)
            ForEach(arena.fighters) { p in
                let pct = p.maxHp > 0 ? Double(p.hp) / Double(p.maxHp) : 0
                VStack(spacing: 6) {
                    HStack {
                        Text("\(p.alive ? "⚔️" : "💀") \(p.name) · \(p.cls)\(p.isMe ? " (you)" : "")\(p.defending ? " 🛡️" : "")")
                            .foregroundStyle(Color(hex: p.alive ? (p.isMe ? 0xc8a832 : 0x88aacc) : 0xcc4444))
                        Spacer()
                        Text("\(p.hp)/\(p.maxHp) HP").foregroundStyle(Color(hex: 0x888888))
                    }
                    .font(Theme.cinzel(10.4))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Color(hex: 0x111111)
                            Color(hex: pct > 0.5 ? 0x44aa44 : pct > 0.25 ? 0xaaaa44 : 0xcc4444)
                                .frame(width: g.size.width * CGFloat(max(0, min(1, pct))))
                        }
                    }
                    .frame(height: 4).clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .overlay(Rectangle().stroke(Color(hex: p.alive ? 0x333333 : 0x662222)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(p.name) HP \(p.hp) of \(p.maxHp)\(p.isMe ? " (you)" : " (opponent)")\(p.defending ? " defending" : "")")
            }
        }
    }

    private var battleLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BATTLE LOG").font(Theme.cinzel(8.8)).tracking(2.6).foregroundStyle(.white.opacity(0.3))
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(arena.log.enumerated()), id: \.offset) { _, l in
                        Text(l).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xc0b090))
            }
            .frame(maxHeight: 160)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Text(arena.myTurn ? "⚔️ YOUR TURN" : "⏳ Opponent turn...").font(Theme.cinzel(10.4)).foregroundStyle(Theme.gold)
            Group {
                Button("⚔️ Attack") { arena.act(.attack) }.buttonStyle(WebButtonStyle(kind: .red))
                    .accessibilityLabel("Attack your opponent")
                Button("💥 Heavy Attack") { arena.act(.heavy) }.buttonStyle(WebButtonStyle(kind: .red))
                    .accessibilityLabel("Heavy attack — more damage")
                Button("✨ Skill (\(arena.mySp) SP)") { arena.act(.skill) }.buttonStyle(WebButtonStyle(kind: .gold))
                    .accessibilityLabel("Use a skill attack — costs 5 SP, you have \(arena.mySp)")
                Button("🛡️ Defend") { arena.act(.defend) }.buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Defend — reduce next incoming hit by 60%")
                Button("😤 Taunt") { arena.act(.taunt) }.buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Taunt your opponent")
            }
            .frame(maxWidth: .infinity)
            .disabled(!arena.myTurn)
            FlowRow(spacing: 6) {
                emote("GG!", "GG! Well played.", "Send GG emote")
                emote("Nice!", "Nice one!", "Send nice one emote")
                emote("Let's go!", "Let's go!", "Send lets go emote")
                emote("Defeated! 😂", "You have been defeated! 😂", "Send you have been defeated emote")
            }
        }
    }

    private func emote(_ title: String, _ text: String, _ label: String) -> some View {
        Button(title) { arena.emote(text) }
            .font(Theme.cinzel(9.6)).foregroundStyle(Theme.textSecondary)
            .padding(.vertical, 6).padding(.horizontal, 10).overlay(Rectangle().stroke(Theme.borderDim))
            .accessibilityLabel(label)
    }
}
