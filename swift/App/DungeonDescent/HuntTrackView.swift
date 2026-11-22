import SwiftUI
import AVFoundation
import DungeonCore

/// 12.0: tracking one beast by sound (Tracking in DungeonCore). The narrator
/// says every line; the beast's call comes from where it really is.
@MainActor
final class TrackModel: ObservableObject {
    static let shared = TrackModel()

    @Published private(set) var hunt: Tracking.Hunt?
    @Published private(set) var log: [String] = []
    @Published var sneak = true
    /// What the finished hunt paid, for the end screen.
    @Published private(set) var result: String?
    private var dice = SystemDice()
    private weak var game: GameModel?

    func begin(_ preyId: String, character ch: PlayerCharacter, bounty: Bool, game: GameModel) {
        self.game = game
        HuntModel.shared.stop()
        let h = Tracking.start(preyId, character: ch, bounty: bounty, dice: &dice)
        hunt = h
        log = []
        result = nil
        sneak = true
        Sound.stopMusic()
        Sound.ambient("hunt-forest")
        SpatialAudio.shared.setRoom(dungeon: "The Whispering Forest")
        Narrator.shared.stop()
        say(["intro_\(preyId)"])
        // Its first call, from where it is.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in self?.call() }
    }

    func leave() {
        hunt = nil
        Narrator.shared.stop()
        Sound.ambient(nil)
        Sound.track("menu")
    }

    // MARK: Actions

    func move(_ d: Compass) {
        guard var h = hunt else { return }
        let ids = Tracking.move(&h, d, sneak: sneak, dice: &dice)
        hunt = h
        if ids.first != "tree" { SpatialAudio.shared.footsteps(d) }
        after(ids)
    }

    func listen() {
        guard var h = hunt else { return }
        let ids = Tracking.listen(&h, dice: &dice)
        call()
        hunt = h
        after(ids, delay: 1.2)
    }

    func search() {
        guard var h = hunt else { return }
        let ids = Tracking.search(&h, dice: &dice)
        hunt = h
        after(ids)
    }

    func ambush() { found { Tracking.ambush(&$0, dice: &self.dice) } }
    func trap() {
        Sound.sfx("sfx-trap")
        found { Tracking.trap(&$0, dice: &self.dice) }
    }
    func face() { found { Tracking.face(&$0) } }

    private func found(_ f: (inout Tracking.Hunt) -> [String]) {
        guard var h = hunt else { return }
        let ids = f(&h)
        hunt = h
        after(ids)
    }

    func strike(_ s: Tracking.Strike) {
        guard var h = hunt else { return }
        let ids = Tracking.strike(&h, s, dice: &dice)
        hunt = h
        switch s {
        case .attack, .defend: Sound.sfx("sfx-attack")
        case .heavy: Sound.sfx(ids.contains("miss") ? "sfx-heavy-miss" : "sfx-heavy-hit")
        case .bandage: Sound.sfx("sfx-potion")
        }
        if ids.contains(where: { $0.hasPrefix("its_hit") }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Sound.sfx("sfx-hurt") }
        }
        after(ids)
    }

    // MARK: Sound and words

    /// The beast's call from where it is: its sound, louder when it's close.
    func call() {
        guard let h = hunt, h.phase == .tracking || h.phase == .found else { return }
        let d = max(1, Double(h.distance))
        let k = Float(min(1.0, 1.6 / d)) / Float(d) * 2.2
        let p = AVAudio3DPoint(x: Float(h.dx) * k, y: 0, z: Float(h.dy) * k)
        SpatialAudio.shared.sound("hunt-call-\(h.prey.call.rawValue).mp3", at: p, volume: Float(max(0.25, 1.1 - d * 0.12)))
    }

    private func after(_ ids: [String], delay: Double = 0) {
        guard let h = hunt else { return }
        if ids.contains("heard_charge") || ids.contains(where: { $0.hasPrefix("found_") }) {
            SpatialAudio.shared.sound("hunt-call-\(h.prey.call.rawValue).mp3", at: AVAudio3DPoint(x: 0, y: 0, z: -1), volume: 1)
        }
        if ids.contains("legend_flee") { Sound.stopMusic() }
        if h.phase == .fight, game != nil, ids.contains("fight") || ids.contains("ambush") || ids.contains("heard_charge") || ids.contains("trap_ok") || ids.contains("ambush_seen") {
            Sound.track(h.prey.legendary ? "boss" : "battle")
        }
        var all = ids
        switch h.phase {
        case .won: finish(&all)
        case .lost:
            Sound.stopMusic(); Sound.sfx("sfx-death")
            result = Narrator.text("lost")
        case .cold:
            Sound.stopMusic()
            result = Narrator.text("cold")
        default: break
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.say(all) }
        } else {
            say(all)
        }
    }

    private func finish(_ ids: inout [String]) {
        guard let h = hunt, let game else { return }
        Sound.stopMusic()
        Sound.sfx("sfx-victory")
        guard let got = Tracking.collect(h, store: game.store, wallet: game.wallet) else { return }
        game.pass(.kill(elite: h.prey.legendary, boss: false))
        if got.rankUp != nil { ids.append("rank_up"); Sound.sfx("sfx-levelup") }
        game.refresh()
        result = Narrator.text("win_\(h.preyId)")
            + (h.bounty ? " " + Narrator.text("bounty_done") : "")
            + " +\(got.reward.xp) XP." + (got.rankUp.map { " 🏹 \($0.name)!" } ?? "")
    }

    private func say(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        log.insert(contentsOf: ids.map(Narrator.text).reversed(), at: 0)
        if log.count > 60 { log.removeLast(log.count - 60) }
        Narrator.shared.say(ids: ids)
    }
}

/// The tracking screen.
struct HuntTrackView: View {
    @ObservedObject var model: TrackModel
    private let green = Color(hex: 0x44aa44)

    var body: some View {
        if let h = model.hunt {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(h.prey.icon) \(h.prey.name)\(h.bounty ? " · Bounty" : "")\(h.prey.legendary ? " · Legend" : "")" as String)
                    .font(Theme.decorative(19)).foregroundStyle(h.prey.legendary ? Color(hex: 0xffcc44) : green)
                    .accessibilityAddTraits(.isHeader)
                status(h)
                switch h.phase {
                case .tracking: tracking(h)
                case .found: foundIt
                case .fight: fight(h)
                case .won, .lost, .cold: end
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.log.prefix(10).enumerated()), id: \.offset) { _, line in
                        Text(line).font(Theme.crimson(14)).foregroundStyle(Color(hex: 0x88aa88))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10).background(Color(hex: 0x020502)).overlay(Rectangle().stroke(Color(hex: 0x0a1a0a)))
                .accessibilityElement(children: .contain).accessibilityLabel("What the narrator said, newest first")
                if h.phase == .tracking || h.phase == .found {
                    Button("🏳 Give Up the Hunt") { model.leave() }
                        .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func status(_ h: Tracking.Hunt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("❤️ \(h.hp) / \(h.maxHp) HP · 🩹 \(h.bandages)" as String).font(Theme.cinzel(12)).foregroundStyle(Theme.ashLight)
            if h.phase == .fight || h.preyHp < h.preyMax {
                Text("\(h.prey.icon) \(h.preyHp) / \(h.preyMax) HP" as String).font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xe08080))
            }
            if h.phase == .tracking {
                Text("⏳ \(Tracking.maxTurns - h.turns) turns before the trail goes cold" as String).font(Theme.cinzel(10)).foregroundStyle(Theme.textDim)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(("Your HP \(h.hp) of \(h.maxHp), \(h.bandages) bandages." as String)
            + (h.phase == .fight || h.preyHp < h.preyMax ? " \(h.prey.name): \(h.preyHp) of \(h.preyMax) HP." : "")
            + (h.phase == .tracking ? " \(Tracking.maxTurns - h.turns) turns left." : "") as String)
    }

    @ViewBuilder private func tracking(_ h: Tracking.Hunt) -> some View {
        Button(model.sneak ? "🤫 Sneaking (quiet, slower)" : "🚶 Walking (fast, loud)") {
            model.sneak.toggle()
            Feedback.announce(model.sneak ? "Sneaking. Quiet, but the beast moves more." : "Walking. Fast, but loud. It may hear you.")
        }
        .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
        .accessibilityHint("Switches between sneaking and walking.")
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                dir("▲ North", .north)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                dir("◄ West", .west)
                Button("👂 Listen") { model.listen() }.buttonStyle(DungeonButtonStyle(kind: .compassAccent))
                    .accessibilityHint("Stand still and listen. Its call comes from where it is. Best with headphones.")
                dir("East ►", .east)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                dir("▼ South", .south)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .frame(maxWidth: 280).frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain).accessibilityLabel("Directions")
        Button("🐾 Search for Tracks") { model.search() }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
    }

    private func dir(_ t: String, _ d: Compass) -> some View {
        Button(t) { model.move(d) }.buttonStyle(DungeonButtonStyle(kind: .compass))
            .accessibilityLabel("\(model.sneak ? "Sneak" : "Walk") \(d.rawValue)")
    }

    @ViewBuilder private var foundIt: some View {
        Button("🗡 Ambush") { model.ambush() }.buttonStyle(WebButtonStyle(kind: .red)).frame(maxWidth: .infinity)
            .accessibilityHint("Strike from hiding for huge damage, if it hasn't noticed you.")
        Button("🪤 Set a Trap") { model.trap() }.buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
            .accessibilityHint("Catch it for two turns. It might slip away.")
        Button("⚔ Face It") { model.face() }.buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
    }

    @ViewBuilder private func fight(_ h: Tracking.Hunt) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            Button("⚔ Attack") { model.strike(.attack) }.buttonStyle(WebButtonStyle(kind: .red))
                .accessibilityLabel("Attack, \(h.atkLo) to \(h.atkHi) damage" as String)
            Button("🔨 Heavy") { model.strike(.heavy) }.buttonStyle(WebButtonStyle(kind: .red))
                .accessibilityLabel("Heavy strike, much harder but can miss")
            Button("🛡 Defend") { model.strike(.defend) }.buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Defend: strike for half and take a quarter")
            Button("🩹 Bandage (\(h.bandages))" as String) { model.strike(.bandage) }.buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Bandage, heals a third of your HP. \(h.bandages) left." as String)
        }
    }

    @ViewBuilder private var end: some View {
        if let r = model.result { Text(r).font(Theme.crimson(16)).foregroundStyle(Theme.textSecondary) }
        Button("🌲 Back to the Hunting Grounds") { model.leave() }
            .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
    }
}
