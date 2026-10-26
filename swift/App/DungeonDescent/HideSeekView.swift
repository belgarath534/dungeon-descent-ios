import SwiftUI
import DungeonCore

/// The web version's #screen-hideseek (single player). The Darkness
/// Swallower is heard, not seen: its growl moves left and right with where
/// it is and gets louder as it closes in, so headphones help.
@MainActor
struct HideSeekView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var game: GameModel
    @StateObject private var mp = HideSeekMultiplayer()
    @State private var mpMode = false
    @State private var codeDraft = ""
    @State private var pickedName: String?
    @State private var hs: HideAndSeek?
    @State private var dice = SystemDice()
    @State private var desc = "You stand still, listening."
    @State private var event = ""
    @State private var ended: HideAndSeek.Outcome?
    @State private var locked = false
    @State private var lockID = 0

    var body: some View {
        WebScreen {
            ScreenHeader(title: "🕯️ Hide and Seek", backHint: "Leave Hide and Seek and return to main menu")
            if mpMode { multiplayer } else if let ended { endPanel(ended) } else if let hs { play(hs) } else { intro }
        }
        .onDisappear {
            if mpMode { mp.leave() }
            Sound.stopLoop()
            Sound.track("menu")
        }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Something is in here with you. Find the way out before it finds you first. BETA.")
                .font(Theme.crimson(15, italic: true)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Button("▶ Single Player", action: start)
                    .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                    .accessibilityLabel("Begin Hide and Seek alone")
                Button("👥 Multiplayer") {
                    Sound.sfx("sfx-select")
                    hs = nil
                    ended = nil
                    mpMode = true
                    if let first = game.characters.first, pickedName == nil { mp.myName = first.name }
                    Feedback.announce("Hide and Seek multiplayer. Up to five players. Create a room or join one with a code.")
                }
                .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                .accessibilityLabel("Play Hide and Seek with friends, up to five players")
            }
        }
    }

    /// hsStart
    private func start() {
        var d = dice
        hs = HideAndSeek(dice: &d)
        dice = d
        ended = nil
        desc = "You stand still, listening."
        event = ""
        locked = false
        Sound.track("hideseek-explore")
        Sound.sfx("sfx-select")
        Feedback.announce("Hide and Seek begins. Something is in here with you — the Darkness Swallower. Find the way out before it finds you. Use North, South, East, or West to move, or Hide to try to lose it. Use headphones — you can hear which direction it is in.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let h = hs, h.active else { return }
            Sound.startLoop("monster-growl.mp3", volume: h.volume, pan: h.pan)
        }
    }

    // MARK: Playing

    private func play(_ h: HideAndSeek) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Move \(h.moves)").font(Theme.cinzel(9.9)).tracking(1.5).foregroundStyle(.white.opacity(0.4))
                Spacer()
                if h.items > 0 {
                    Text("🫥 \(h.items)").font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x88cc88))
                        .padding(.vertical, 3).padding(.horizontal, 9).overlay(Rectangle().stroke(Color(hex: 0x446633)))
                        .accessibilityLabel("\(h.items) hiding \(h.items == 1 ? "spot" : "spots") found")
                }
                Text("\(h.distance) \(h.distance == 1 ? "room" : "rooms") away").font(Theme.cinzel(9.9))
                    .foregroundStyle(Color(hex: h.chasing ? 0xff8888 : 0xcc8888))
                    .padding(.vertical, 3).padding(.horizontal, 9)
                    .overlay(Rectangle().stroke(Color(hex: h.chasing ? 0xcc3333 : 0x663333)))
                    .accessibilityLabel("It is \(h.distance) \(h.distance == 1 ? "room" : "rooms") away")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(desc).font(Theme.crimson(16, italic: true)).foregroundStyle(Theme.textPrimary)
                if !event.isEmpty {
                    Text(event).font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0xe0a0a0))
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current room. \(desc) \(event)")

            VStack(spacing: 8) {
                moveButton("▲ North", "Move north", .north)
                HStack(spacing: 8) {
                    moveButton("◄ West", "Move west", .west)
                    moveButton("East ►", "Move east", .east)
                }
                moveButton("▼ South", "Move south", .south)
                Button("🫥 Hide", action: hide)
                    .buttonStyle(DungeonButtonStyle(kind: .action))
                    .foregroundStyle(Color(hex: 0xbb88ee))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Hide and try to lose the thing following you")
            }
        }
    }

    private func moveButton(_ title: String, _ label: String, _ dir: HideAndSeek.Direction) -> some View {
        Button(title) { move(dir) }
            .buttonStyle(DungeonButtonStyle(kind: .compass))
            .frame(maxWidth: .infinity)
            .disabled(locked)
            .accessibilityLabel(label)
    }

    private func refreshSound(_ h: HideAndSeek, wasChasing: Bool) {
        Sound.moveLoop(volume: h.volume, pan: h.pan)
        if h.chasing != wasChasing { Sound.track(h.chasing ? "hideseek-chase" : "hideseek-explore") }
    }

    /// hsMove
    private func move(_ dir: HideAndSeek.Direction) {
        guard var h = hs, h.active, !locked else { return }
        let wasChasing = h.chasing
        var d = dice
        let s = h.move(dir, dice: &d)
        dice = d
        hs = h
        if s.outcome == .wall { Feedback.announce(s.spoken); return }
        Sound.sfx("sfx-footstep")
        desc = s.desc
        event = s.event
        switch s.outcome {
        case .caught: caught(); return
        case .escaped: escaped(); return
        default: break
        }
        refreshSound(h, wasChasing: wasChasing)
        Feedback.announce(s.spoken)
        // While it's far off, a listening beat: you hear its footstep before moving again.
        if !h.chasing {
            locked = true
            lockID += 1
            let id = lockID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                guard let h = hs, h.active else { return }
                Sound.placed("monster-footstep.mp3", volume: h.volume, pan: h.pan)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if id == lockID { locked = false }
            }
        }
    }

    /// hsHide
    private func hide() {
        guard var h = hs, h.active else { return }
        let wasChasing = h.chasing
        var d = dice
        let s = h.hide(dice: &d)
        dice = d
        hs = h
        Sound.sfx("sfx-select")
        event = s.event
        if s.outcome == .caught { caught(); return }
        refreshSound(h, wasChasing: wasChasing)
        Feedback.announce(s.spoken)
    }

    // MARK: The end

    private func caught() {
        ended = .caught
        Sound.stopLoop()
        Sound.sfx("sfx-death")
        Feedback.warning()
        Sound.track("menu")
        Feedback.announce("Caught. It found you. Try again, or return to the menu.")
    }

    private func escaped() {
        ended = .escaped
        Sound.stopLoop()
        Sound.sfx("sfx-confirm")
        Feedback.success()
        Sound.track("menu")
        Feedback.announce("You escaped. You made it out alive.")
    }

    private func endPanel(_ o: HideAndSeek.Outcome) -> some View {
        VStack(spacing: 10) {
            Text(o == .caught ? "Caught" : "Escaped").font(Theme.decorative(17.6)).foregroundStyle(Theme.gold)
                .accessibilityAddTraits(.isHeader)
            Text(o == .caught ? "It found you. Try again — the way out is different every time."
                 : "You made it out. It is still in there, waiting for the next one.")
                .font(Theme.cinzel(12)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center).lineSpacing(5)
                .padding(.bottom, 8)
            Button("↻ Try Again", action: start)
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .accessibilityLabel("Play Hide and Seek again")
            Button("← Menu") { router.goTo(.menu) }
                .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                .accessibilityLabel("Return to main menu")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Multiplayer (hs-mp-lobby, the shared run, hs-mp-end-results)

    @ViewBuilder
    private var multiplayer: some View {
        switch mp.stage {
        case .lobby: mpLobby
        case .room: mpRoom
        case .playing: mpPlay
        case .ended: mpEnd
        }
        if !mp.status.isEmpty && mp.stage != .playing {
            Text(mp.status).font(Theme.cinzel(10.9)).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }

    private var mpLobby: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Up to 5 players. Everyone shares hiding spots and can rescue each other if caught — but the Darkness Swallower only needs to catch everyone once.")
                .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
            if !game.characters.isEmpty {
                Text("PLAY AS").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
                ForEach(game.characters, id: \.created) { ch in
                    let chosen = mp.myName == ch.name
                    Button {
                        mp.myName = ch.name
                        pickedName = ch.name
                        Sound.sfx("sfx-select")
                        Feedback.announce("\(ch.name) selected.")
                    } label: {
                        Text("\(chosen ? "✓ " : "")\(ch.name) — \(ch.race) \(ch.cls)").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(WebButtonStyle(kind: chosen ? .gold : .ghost))
                    .accessibilityLabel("Play as \(ch.name)")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            Button("🏟️ Create Room") { mp.create() }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .accessibilityLabel("Create a new Hide and Seek room and get a code to share")
            HStack(spacing: 8) {
                TextField("Room code", text: $codeDraft)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(Theme.cinzel(19)).tracking(6).multilineTextAlignment(.center).foregroundStyle(.white)
                    .padding(10).background(Color(hex: 0x0a0a14)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                    .onChange(of: codeDraft) { v in if v.count > 4 { codeDraft = String(v.prefix(4)) } }
                    .accessibilityLabel("Enter 4 character room code to join friends")
                Button("Join") { mp.join(codeDraft) }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                    .accessibilityLabel("Join room with code")
            }
            Button("← Back") {
                mp.leave()
                mpMode = false
                Sound.sfx("sfx-select")
            }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
            .accessibilityLabel("Back to Hide and Seek menu")
        }
    }

    private var mpRoom: some View {
        VStack(spacing: 10) {
            if let c = mp.code {
                Text("YOUR ROOM CODE").font(Theme.cinzel(8.8)).tracking(2.6).foregroundStyle(.white.opacity(0.3))
                Text(c).font(Theme.cinzel(28.8)).tracking(11).foregroundStyle(Color(hex: 0xe0c080))
                    .accessibilityLabel("Room code \(c.map(String.init).joined(separator: " "))")
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(mp.lobby, id: \.id) { p in
                    Text("\(p.ready ? "✓" : "…") \(p.name)\(p.id == mp.myId ? " (you)" : "")")
                        .accessibilityLabel("\(p.name)\(p.id == mp.myId ? ", you" : ""), \(p.ready ? "ready" : "not ready")")
                }
            }
            .font(Theme.cinzel(10.9)).foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(mp.readyPressed ? "⏳ Ready" : "✓ Ready") { mp.ready() }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .disabled(mp.readyPressed)
                .accessibilityLabel("Mark yourself ready")
            if mp.isHost {
                Button("▶ Start") { mp.start() }
                    .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                    .accessibilityLabel("Start the run for everyone in the room")
            }
            Button("← Back") {
                mp.leave()
                Sound.sfx("sfx-select")
            }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
            .accessibilityLabel("Leave the room")
        }
    }

    private var mpPlay: some View {
        let me = mp.me
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🫥 \(mp.items) shared hiding spot\(mp.items == 1 ? "" : "s")").foregroundStyle(Color(hex: 0x88cc88))
                Spacer()
                Text(me?.caught == true ? "caught — wait for rescue" : me?.escaped == true ? "escaped"
                     : "\(mp.distance) \(mp.distance == 1 ? "room" : "rooms") away")
                    .foregroundStyle(Color(hex: 0xcc8888))
            }
            .font(Theme.cinzel(9.9))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(mp.players) { p in
                    Text("\(p.name)\(p.id == mp.myId ? " (you)" : "") — \(p.escaped ? "🚪 escaped" : p.caught ? "⛓️ caught" : "🚶 exploring")")
                }
            }
            .font(Theme.cinzel(9.9)).foregroundStyle(.white.opacity(0.6))
            .padding(.vertical, 8).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x2a2010)))
            .accessibilityElement(children: .combine)
            Text(mp.desc).font(Theme.crimson(16, italic: true)).foregroundStyle(Theme.textPrimary)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            VStack(spacing: 8) {
                mpMove("▲ North", "Move north", .north)
                HStack(spacing: 8) {
                    mpMove("◄ West", "Move west", .west)
                    mpMove("East ►", "Move east", .east)
                }
                mpMove("▼ South", "Move south", .south)
                Button("🫥 Hide") { mp.hide() }
                    .buttonStyle(DungeonButtonStyle(kind: .action))
                    .foregroundStyle(Color(hex: 0xbb88ee))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Hide and try to lose the thing following you")
            }
            .disabled(me?.caught == true || me?.escaped == true)
            Button("← Leave") {
                mp.leave()
                mpMode = false
            }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
            .accessibilityLabel("Leave the run")
        }
    }

    private func mpMove(_ title: String, _ label: String, _ dir: HideAndSeek.Direction) -> some View {
        Button(title) { mp.move(dir) }
            .buttonStyle(DungeonButtonStyle(kind: .compass))
            .frame(maxWidth: .infinity)
            .accessibilityLabel(label)
    }

    private var mpEnd: some View {
        let escaped = mp.players.filter(\.escaped).count
        return VStack(spacing: 10) {
            Text(escaped == 0 ? "Caught" : escaped == mp.players.count ? "Escaped" : "Some Made It Out")
                .font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
            Text(escaped == 0 ? "It found everyone. Try again — the way out is different every time." : "The run is over. Here is how everyone fared:")
                .font(Theme.cinzel(12)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(mp.players) { p in
                    Text("\(p.escaped ? "🚪" : "⛓️") \(p.name)\(p.id == mp.myId ? " (you)" : "") — \(p.escaped ? "escaped" : "caught")")
                }
            }
            .font(Theme.cinzel(10.9)).foregroundStyle(.white.opacity(0.6))
            .padding(.vertical, 8).padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x2a2010)))
            Button("↻ Try Again") {
                mp.leave()
                Feedback.announce("Hide and Seek multiplayer. Create a room or join one with a code.")
            }
            .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
            .accessibilityLabel("Try again")
            Button("← Menu") {
                mp.leave()
                router.goTo(.menu)
            }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
            .accessibilityLabel("Return to main menu")
        }
    }
}
