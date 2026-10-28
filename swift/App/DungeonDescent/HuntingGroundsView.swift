import SwiftUI
import DungeonCore

/// The hunt itself (startHunt, huntTick, stopHunt). It keeps going while you
/// look around the rest of the app, like the web version.
@MainActor
final class HuntModel: ObservableObject {
    static let shared = HuntModel()

    @Published private(set) var hunter: Hunt.Hunter?
    @Published private(set) var active = false
    @Published private(set) var log: [String] = []
    @Published var charIndex = 0

    private var timer: Timer?
    private var dice = SystemDice()
    private weak var game: GameModel?

    func start(_ game: GameModel) {
        guard game.characters.indices.contains(charIndex) else { Feedback.announce("Select a character first."); return }
        self.game = game
        let h = Hunt.Hunter(game.characters[charIndex])
        hunter = h
        active = true
        log = ["🌲 \(h.name) enters the Hunting Grounds."]
        Sound.ambient("whisper")
        Feedback.announce("Hunt started. Brian will narrate. Your hunter keeps fighting while you look around.")
        // The forest's sound first, then Brian, then the first moment.
        let enter = Hunt.say("enter", dice: &dice)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.active else { return }
            self.log.append(enter)
            Brian.shared.say(enter)
        }
        schedule(after: 8)
    }

    /// stopHunt
    func stop(died: Bool = false) {
        timer?.invalidate()
        timer = nil
        guard active else { return }
        active = false
        Sound.ambient(nil)
        if !died, let h = hunter {
            log.append("📯 Hunt ended. \(h.kills) enemies slain, \(h.items) items found, \(h.gold)g earned.")
            Brian.shared.say(Hunt.say("return", dice: &dice) + " You slew \(h.kills) enemies and found \(h.items) items.")
        }
    }

    private func schedule(after seconds: Double) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard active, var h = hunter, let game else { return }
        let rank = Hunt.rank(game.store)
        let m = Hunt.tick(&h, rank: rank, dice: &dice)
        hunter = h
        log += m.log
        if log.count > 120 { log.removeFirst(log.count - 120) }
        if m.gold > 0 { game.wallet.addGold(m.gold) }
        if let item = m.item { game.globalInventory.add(item) }
        m.brian.forEach { Brian.shared.say($0) }
        if m.xp > 0, let up = Hunt.addXP(m.xp, store: game.store) {
            log.append("🏹 RANK UP! You are now a \(up.name)!")
            Sound.sfx("sfx-levelup")
            Brian.shared.say("Rank up. You are now \(up.name). \(up.desc)")
        }
        if let name = m.killed, let done = Bounties.record(.kill(name: name, elite: false, boss: false, dungeon: "Hunting Grounds"), store: game.store) {
            Bounties.complete(done, store: game.store, wallet: game.wallet)
            _ = game.achievements.check()
            log.append("📋 Bounty Complete! \(done.title). +\(done.gold) gold, +\(done.trophies) trophies.")
            Feedback.announce("Bounty complete! \(done.title). You earned \(done.gold) gold.")
        }
        if h.dead {
            Sound.sfx("sfx-death")
            stop(died: true)
            return
        }
        schedule(after: Double(dice.roll(25...45)))
    }
}

/// #screen-hunting
struct HuntingGroundsView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @ObservedObject private var hunt = HuntModel.shared
    private let green = Color(hex: 0x44aa44)

    var body: some View {
        let xp = Hunt.xp(game.store)
        let rank = Hunt.rank(xp: xp)
        let next = Hunt.next(after: rank)
        WebScreen {
            VStack(alignment: .leading, spacing: 12) {
                Button("← Leave") {
                    if hunt.active { Feedback.announce("You step away. The hunt continues without you.") }
                    router.goTo(.bounty)
                }
                .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Leave the Hunting Grounds")
                Text("🌲 Hunting Grounds").font(Theme.decorative(22)).foregroundStyle(green).accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("🏹 Bounty Rank \(rank.rank)").font(Theme.cinzel(11.2)).foregroundStyle(green)
                        Spacer()
                        Text("\(xp) / \(next.xpNeeded) XP").font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x555555))
                    }
                    Bar(value: next.xpNeeded > rank.xpNeeded ? Double(xp - rank.xpNeeded) / Double(next.xpNeeded - rank.xpNeeded) : 1,
                        colors: [green, Color(hex: 0x44ff88)], track: green.opacity(0.15), height: 4)
                    Text("\(rank.name) — \(rank.desc)").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x666666))
                }
                .padding(12).background(Color(hex: 0x030803)).overlay(Rectangle().stroke(Color(hex: 0x0a1a0a)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Bounty Rank \(rank.rank), \(rank.name). \(rank.desc) \(xp) of \(next.xpNeeded) XP.")

                VStack(spacing: 4) {
                    stat("Hunter", hunt.hunter?.name ?? (game.characters.indices.contains(hunt.charIndex) ? game.characters[hunt.charIndex].name : "None selected"))
                    stat("Status", hunt.active ? "Hunting..." : "Idle")
                    stat("HP", hunt.active ? "\(hunt.hunter?.hp ?? 0) / \(hunt.hunter?.maxHp ?? 0)" : "—")
                    stat("Enemies Slain", "\(hunt.hunter?.kills ?? 0)")
                    stat("Items Found", "\(hunt.hunter?.items ?? 0)")
                    stat("Gold Earned", "\(hunt.hunter?.gold ?? 0)g")
                }
                .padding(12).background(Color(hex: 0x030803)).overlay(Rectangle().stroke(Color(hex: 0x0a1a0a)))

                if !hunt.active {
                    Text("SELECT HUNTER").font(Theme.cinzel(10.4)).tracking(1.5).foregroundStyle(Color(hex: 0x555555))
                    if game.characters.isEmpty {
                        Text("No characters. Create one first.").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x555555))
                    }
                    ForEach(Array(game.characters.enumerated()), id: \.offset) { i, c in
                        Button((i == hunt.charIndex ? "► " : "  ") + "\(c.name) — \(c.cls) Lv.\(c.persistLevel ?? 1)") {
                            hunt.charIndex = i
                            Feedback.announce("\(c.name) selected.")
                        }
                        .buttonStyle(WebButtonStyle(kind: i == hunt.charIndex ? .gold : .ghost))
                        .accessibilityLabel("\(c.name) \(c.cls) level \(c.persistLevel ?? 1)")
                        .accessibilityAddTraits(i == hunt.charIndex ? .isSelected : [])
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(hunt.log.suffix(30).reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x88aa88))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10).background(Color(hex: 0x020502)).overlay(Rectangle().stroke(Color(hex: 0x0a1a0a)))
                .accessibilityElement(children: .contain).accessibilityLabel("Hunt log, newest first")

                if hunt.active {
                    Button("📯 Call Back Hunter") { hunt.stop() }
                        .buttonStyle(WebButtonStyle(kind: .red)).frame(maxWidth: .infinity)
                        .accessibilityLabel("Call hunter back from the forest")
                } else {
                    Button("🌲 Enter The Forest") { hunt.start(game) }
                        .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                        .disabled(game.characters.isEmpty)
                        .accessibilityLabel("Send hunter into the forest")
                }
                Text("Brian narrates your hunt. Your hunter keeps fighting while you look around the game.")
                    .font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x444444)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            Feedback.announce("The Hunting Grounds. Bounty Rank \(rank.rank). " + (hunt.active ? "Your hunter is active in the forest." : "Select a character and enter the forest."))
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(Color(hex: 0x555555))
            Spacer()
            Text(v).foregroundStyle(green)
        }
        .font(Theme.cinzel(10.9))
        .accessibilityElement(children: .combine)
    }
}
