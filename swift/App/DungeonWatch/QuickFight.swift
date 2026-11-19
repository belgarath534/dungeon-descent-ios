import SwiftUI
import WatchKit

/// 12.0 QUICK FIGHT: a watch-only game. Fight one enemy after another; turn
/// the Digital Crown (or swipe up and down with VoiceOver) to choose Attack,
/// Heavy, Defend or Potion, and tap to act. Every fifth enemy is a boss.
/// Your wrist feels every hit. How far you get is your best streak.
struct QuickFight {
    enum Action: Int, CaseIterable {
        case attack, heavy, defend, potion
        var name: String { ["Attack", "Heavy Strike", "Defend", "Potion"][rawValue] }
        var icon: String { ["⚔", "🔨", "🛡", "🧪"][rawValue] }
        var hint: String {
            ["8 to 14 damage", "20 to 28 damage, can miss", "half damage both ways", "heals 40 HP"][rawValue]
        }
    }

    struct Foe {
        var name: String
        var hp: Int
        var maxHp: Int
        var atk: ClosedRange<Int>
        var boss: Bool
    }

    static let names = ["Skeleton", "Goblin", "Giant Rat", "Cave Bat", "Bone Knight", "Ghoul", "Wraith", "Ash Imp", "Grave Hound", "Shade"]
    static let bosses = ["The Crypt Lord", "The Bone Colossus", "The Drowned King", "Mother of Spiders", "The Ash Wyrm"]

    var hp = 100
    var maxHp = 100
    var potions = 3
    var wins = 0
    var foe: Foe
    var over = false

    init() { foe = Self.foe(1) }

    static func foe(_ n: Int) -> Foe {
        let boss = n % 5 == 0
        let hp = (boss ? 60 : 28) + n * (boss ? 10 : 5)
        let lo = 4 + n, hi = 8 + n * 2
        return Foe(name: boss ? bosses[(n / 5 - 1) % bosses.count] : names.randomElement()!,
                   hp: hp, maxHp: hp, atk: (boss ? lo + 3 : lo)...(boss ? hi + 4 : hi), boss: boss)
    }

    /// One round: your move, then theirs. Returns what happened, and the haptic to play.
    mutating func act(_ a: Action) -> (String, WKHapticType) {
        guard !over else { return ("The fight is over.", .click) }
        var line = ""
        var halfTaken = false
        switch a {
        case .attack:
            let d = Int.random(in: 8...14)
            foe.hp -= d; line = "You hit \(foe.name) for \(d)."
        case .heavy:
            if Double.random(in: 0..<1) < 0.3 { line = "Your heavy strike misses!" }
            else { let d = Int.random(in: 20...28); foe.hp -= d; line = "Heavy strike! \(d) damage." }
        case .defend:
            let d = Int.random(in: 4...7)
            foe.hp -= d; halfTaken = true; line = "You defend and hit for \(d)."
        case .potion:
            if potions == 0 { return ("No potions left!", .retry) }
            potions -= 1
            let before = hp
            hp = min(maxHp, hp + 40)
            line = "Potion: +\(hp - before) HP. \(potions) left."
        }
        if foe.hp <= 0 {
            wins += 1
            let heal = maxHp * 3 / 10
            hp = min(maxHp, hp + heal)
            if foe.boss { potions += 1 }
            let beaten = foe.name
            foe = Self.foe(wins + 1)
            return ("\(line) \(beaten) is defeated! You heal \(heal). Next: \(foe.name)\(foe.boss ? ", a boss" : "").", .success)
        }
        var taken = Int.random(in: foe.atk)
        if halfTaken { taken = max(1, taken / 2) }
        hp -= taken
        if hp <= 0 {
            hp = 0; over = true
            return ("\(line) \(foe.name) hits for \(taken). You fall after \(wins) win\(wins == 1 ? "" : "s").", .failure)
        }
        return ("\(line) \(foe.name) hits back for \(taken). You have \(hp) HP.", taken >= 15 ? .directionDown : .click)
    }
}

struct QuickFightView: View {
    @State private var game = QuickFight()
    @State private var crown = 0.0
    @State private var line = "Turn the Digital Crown to choose, then tap."
    @AppStorage("dd_watch_quickfight_best") private var best = 0

    private var action: QuickFight.Action { QuickFight.Action(rawValue: Int(crown.rounded()) % 4) ?? .attack }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(game.foe.boss ? "👑 " : "")\(game.foe.name)").font(.headline).foregroundStyle(game.foe.boss ? .orange : gold)
                ProgressView(value: Double(max(0, game.foe.hp)), total: Double(game.foe.maxHp)).tint(.red)
                    .accessibilityLabel("\(game.foe.name)\(game.foe.boss ? ", boss" : "")")
                    .accessibilityValue("\(max(0, game.foe.hp)) of \(game.foe.maxHp) HP")
                ProgressView(value: Double(game.hp), total: Double(game.maxHp)) {
                    Text("You: \(game.hp) HP · 🧪 \(game.potions) · wins \(game.wins)").font(.footnote)
                }
                .tint(.green)
                .accessibilityLabel("You")
                .accessibilityValue("\(game.hp) of \(game.maxHp) HP, \(game.potions) potions, \(game.wins) wins")

                if game.over {
                    Text("Best: \(best) wins").font(.footnote)
                    Button("Fight Again") {
                        game = QuickFight()
                        say("A new fight. \(game.foe.name) appears.")
                    }
                    .tint(gold)
                } else {
                    Button { act() } label: {
                        VStack(spacing: 1) {
                            Text("\(action.icon) \(action.name)").font(.title3.bold())
                            Text(action.hint).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .tint(action == .attack || action == .heavy ? .red : .blue)
                    .accessibilityLabel("\(action.name), \(action.hint)")
                    .accessibilityHint("Swipe up or down to choose another move. Double-tap to do it.")
                    .accessibilityAdjustableAction { dir in
                        switch dir {
                        case .increment: crown = Double((Int(crown.rounded()) + 1) % 4)
                        case .decrement: crown = Double((Int(crown.rounded()) + 3) % 4)
                        @unknown default: break
                        }
                    }
                }
                Text(line).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .focusable()
        .digitalCrownRotation($crown, from: 0, through: 3, by: 1, sensitivity: .low, isContinuous: true, isHapticFeedbackEnabled: true)
        .navigationTitle("Quick Fight")
        .onAppear { say("Quick Fight. \(game.foe.name) appears. Turn the Crown or swipe up and down to choose a move, then tap.") }
    }

    private func act() {
        let (text, haptic) = game.act(action)
        WKInterfaceDevice.current().play(haptic)
        line = text
        if game.over, game.wins > best { best = game.wins; line += " A new best!" }
        say(line)
    }

    private func say(_ s: String) {
        line = s
        WatchStore.speak(s)
    }
}
