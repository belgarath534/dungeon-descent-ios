import SwiftUI
import DungeonCore

/// 12.1: the web version's first-time tutorial (#tutorial-overlay), eight
/// steps, for new players (no characters yet). Replay it from Settings,
/// Accessibility. VoiceOver starts on each step's heading.
@MainActor
final class Tutorial: ObservableObject {
    static let shared = Tutorial()
    static let seenKey = "dd_tutorial_seen"
    @Published var showing = false

    struct Step { let title: String; let heading: String; let lines: [String] }

    static let steps: [Step] = [
        Step(title: "Welcome", heading: "Welcome to Dungeon Descent", lines: [
            "You are about to descend into one of the darkest games ever made for screen reader users.",
            "Dungeon Descent is fully accessible. Every button, every enemy, every room description — all announced by your screen reader automatically.",
            "This quick guide will show you how everything works. You can skip it anytime.",
            "💡 Built for JAWS and VoiceOver",
            "Every action in the game is announced. Combat damage, loot found, floor descriptions — your screen reader reads it all."
        ]),
        Step(title: "Character Creation", heading: "Building Your Character", lines: [
            "Before you descend, you build your character across 10 steps.",
            "Class — 18 classes available. Warrior, Monk, Assassin, Paladin, Naturalist, Sorcerer, Necromancer, Berserker, Bard, Alchemist, BloodKnight, Druid, Warlock, DeathKnight, Ranger, Sentinel, Cleric, Wizard. Each plays completely differently.",
            "Race — 11 races. Human is balanced. Orc hits hardest. Vampire heals on every kill. Angel gains a second life. Goblin finds 25% more gold. Merfolk get bonus HP in the Sunken Archives.",
            "Profession — 11 options. Herbalist doubles potion healing. Pilgrim gets 15% bonus XP. Blacksmith gets 10% off upgrades.",
            "Starting Skill — every class now begins with their signature skill already unlocked on floor 1.",
            "💡 Tip for new players",
            "Start with Warrior class, Dwarf race, Herbalist profession on Wanderer difficulty. This gives you the most survivability for your first run."
        ]),
        Step(title: "Navigation", heading: "Moving Through the Dungeon", lines: [
            "The dungeon has 10 floors. Each floor has 5 rooms. After room 5 you reach a shop, then descend to the next floor.",
            "Use the North, South, East, West buttons to move between rooms. Direction does not matter — each move generates a new room.",
            "Use the Search button to search the current room for hidden loot. You can only search each room once.",
            "Every room can contain combat, loot, a special event, or nothing. You never know what waits ahead.",
            "💡 Special Events",
            "About 1 in 10 rooms triggers a special event — an ancient shrine, a mysterious chest, a wounded adventurer, or an inscription. These give rewards if you interact with them."
        ]),
        Step(title: "Accessibility", heading: "Features Worth Turning On", lines: [
            "Your screen reader announcements work automatically — nothing to enable there. But a few opt-in features are easy to miss.",
            "Voice Commands — in every fight, the Speak button lets you say your move: \"attack,\" \"heavy,\" \"defend,\" \"potion,\" or a skill's name.",
            "Haptic Feedback — distinct vibration patterns for hits, crits, level-ups, and danger. On by default — adjust intensity in Settings under Accessibility.",
            "3D Mode & Echo-Location — an optional spatial-audio layer for exploring rooms. Turn it on in Settings under Beta Features, then use the two-finger double tap to sonar-ping a room for walls and doors.",
            "💡 Command Center",
            "Prefer typing? The Command Center lets you play the entire game — including character creation — with text commands instead of buttons."
        ]),
        Step(title: "Combat", heading: "Fighting in the Dark", lines: [
            "Combat is turn-based. You act, then the enemy acts.",
            "Attack — reliable, always hits. 10% chance to critically hit for 1.8x damage.",
            "Heavy Strike — deals 1.7x damage but has a 30% chance to miss completely.",
            "Defend — reduces incoming damage this turn and deals a small counter hit.",
            "Potion — drinks a health potion from your inventory. Herbalists get double healing.",
            "Skills — unlock as you level up. Each class has unique powerful abilities that cost SP.",
            "Soul Trap — if you have one in your inventory, a Soul Trap button appears in combat. Use it to capture the enemy as a permanent minion instead of killing it.",
            "🗡 Try it yourself",
            "A harmless Training Shade will appear. Practice Attack, Heavy Strike, and Defend against it — it can barely scratch you, and you cannot actually die to it."
        ]),
        Step(title: "Progression", heading: "Growing Stronger", lines: [
            "You earn XP from every kill. Level up to gain HP, attack power, and skill unlocks. Every level gives 3 points to spend on stats.",
            "SP (Skill Points) power your class skills. You start with 20 SP and regenerate 2 per room entered.",
            "The shop appears between floors. Buy potions, weapons, armor, runes, scrolls, and Soul Traps with gold from kills.",
            "Complete dungeons to unlock the next. 8 dungeons — Crypt, Ashbound Wastes, Frosthold, Sunken Archives, The Hollow, Whispering Forest, The Infernal, and The Abyssal Deep.",
            "Trophies — earned from achievements. Reaching 100 trophies unlocks The Infernal Descent.",
            "💡 Minions and Forge",
            "Use a Soul Trap in combat to capture enemies as permanent minions. Collect materials from kills and craft custom weapons at the Forge inside your Home. Both are accessed from the Home screen between fights."
        ]),
        Step(title: "Blacksmith", heading: "The Blacksmith", lines: [
            "The Blacksmith appears inside dungeons and lets you do two things.",
            "Upgrade — spend gold to upgrade your currently equipped weapon or armor. Higher level gear deals more damage and has better defense.",
            "Buy Weapons — browse a selection of weapons available for purchase with gold. Your first weapon is always free — a starter blade to get you going.",
            "Weapons you buy go straight into your inventory. Open your inventory to equip them.",
            "💡 Blacksmith Profession",
            "If you pick Blacksmith as your profession during character creation, you get a 10% discount on all upgrades. Great for long runs."
        ]),
        Step(title: "Ready", heading: "You Are Ready to Descend", lines: [
            "That is everything you need to know. The rest you will learn in the dark.",
            "Check the Bestiary to track every enemy you encounter. Visit The Chronicles for lore and stories. Use Quests for daily challenges and achievements.",
            "The Blacksmith is on the main menu — upgrade weapons between runs using your global gold. The Daily Raid gives gold and Mystery Coins. The Spire lets you climb 1800 floors endlessly.",
            "Every achievement earns you gold and trophies. 100 trophies unlocks The Infernal Descent. Unlock The Abyssal Deep after that.",
            "Good luck. The dungeon has been waiting.",
            "💡 You can replay this tutorial anytime",
            "Find it in Settings under the Accessibility section whenever you need a refresher."
        ])
    ]

    /// On the first open, for someone who hasn't made a character yet.
    func showIfNew(_ game: GameModel) {
        guard game.store.getItem(Self.seenKey) == nil else { return }
        game.store.setItem(Self.seenKey, "1")
        guard game.characters.isEmpty else { return }
        showing = true
    }
}

struct TutorialOverlay: ViewModifier {
    @ObservedObject private var tutorial = Tutorial.shared
    func body(content: Content) -> some View {
        content.overlay { if tutorial.showing { TutorialView { tutorial.showing = false } } }
    }
}

struct TutorialView: View {
    let close: () -> Void
    @State private var step = 0
    @AccessibilityFocusState private var focus: Bool

    var body: some View {
        let s = Tutorial.steps[step]
        let n = Tutorial.steps.count
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(s.title) — Step \(step + 1) of \(n)" as String).font(Theme.cinzel(11)).tracking(2).foregroundStyle(Theme.goldDim)
                    Text(s.heading).font(Theme.decorative(22)).foregroundStyle(Theme.gold)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focus)
                    ForEach(Array(s.lines.enumerated()), id: \.offset) { _, l in
                        Text(l).font(l.hasPrefix("💡") ? Theme.cinzel(13) : Theme.crimson(16))
                            .foregroundStyle(l.hasPrefix("💡") ? Theme.gold : Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    AdaptiveRow(spacing: 10) {
                        if step > 0 {
                            Button("← Back") { go(step - 1) }.buttonStyle(WebButtonStyle(kind: .ghost))
                        }
                        if step < n - 1 {
                            Button("Next →") { go(step + 1) }.buttonStyle(WebButtonStyle(kind: .gold))
                            Button("Skip Tutorial") { finish("Tutorial skipped. Welcome to Dungeon Descent.") }.buttonStyle(WebButtonStyle(kind: .ghost))
                        } else {
                            Button("⚔ Start Playing") { finish("Welcome to Dungeon Descent. Press Play to make your first character.") }.buttonStyle(WebButtonStyle(kind: .gold))
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityAddTraits(.isModal)
        .onAppear { focus = true; Sound.sfx("sfx-select") }
    }

    private func go(_ i: Int) {
        step = i
        Sound.sfx("sfx-select")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = true }
    }

    private func finish(_ said: String) {
        close()
        Feedback.announce(said, after: 0.5)
    }
}
