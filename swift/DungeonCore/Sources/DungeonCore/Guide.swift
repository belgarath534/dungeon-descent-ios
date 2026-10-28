import Foundation

/// YOUR GUIDE: the companion named at character creation, who talks to you
/// in one of four personalities (GUIDE PERSONALITY SYSTEM, COMPANION SYSTEM).
public enum Guide {
    public enum Moment: String, Sendable {
        case dungeonStart, levelUp, lowHp, bossEncounter, victory, death, achievement, hunterClose
    }

    public static let personalities = ["encouraging", "sarcastic", "mysterious", "calm"]

    /// getGuideDialogue: a random line for the moment, with {lvl} filled in.
    public static func line(_ m: Moment, personality: String, level: Int, dice: inout some Dice) -> String? {
        guard let set = lines[personality] ?? lines["encouraging"], let options = set[m.rawValue], !options.isEmpty else { return nil }
        return options[dice.roll(0...(options.count - 1))].replacingOccurrences(of: "{lvl}", with: String(level))
    }

    /// The companion's name (dd_companion_name), Mira by default.
    public static func name(_ store: GameStore) -> String {
        let n = store.getItem("dd_companion_name")?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "Mira" : n
    }

    /// GUIDE_DIALOGUE
    static let lines: [String: [String: [String]]] = [
        "encouraging": [
            "dungeonStart": [
                "I believe in you. Whatever this dungeon throws at us — we handle it together.",
                "You are stronger than you know. Let us show this dungeon what you are made of.",
                "Stay focused and stay brave. I will be right here with you every step.",
            ],
            "levelUp": [
                "YES! Level {lvl}! I knew you could do it!",
                "Look at you growing stronger. This dungeon has no idea what it is dealing with.",
                "Level {lvl}! You are incredible. Keep going!",
            ],
            "lowHp": [
                "Hey — stay with me. Use a potion. I need you alive.",
                "You are hurt. Please heal. You have come too far to fall here.",
                "Do not give up now. Heal up and keep fighting!",
            ],
            "bossEncounter": [
                "This is it! The boss! You have trained for this — go show it who you are!",
                "A boss! Yes! This is your moment. You have got this, I promise.",
                "The boss of this dungeon. You are ready. I have watched you get here — you can do this.",
            ],
            "victory": [
                "I KNEW IT! I knew you would win! That was absolutely incredible!",
                "YES! YES! You did it! I am so proud of you right now!",
                "Unstoppable. Completely unstoppable. That is what you are.",
            ],
            "death": [
                "No... not yet. Come back. I will be waiting.",
                "This is not the end. Rest and return stronger. I believe in you.",
                "Even the greatest fall sometimes. Rise again. I will be here.",
            ],
            "achievement": [
                "Achievement unlocked! I always knew you had it in you!",
                "Yes! You earned that! Celebrate this moment!",
                "Outstanding! Every achievement proves how amazing you are!",
            ],
            "hunterClose": [
                "Something is following us. Keep moving — do NOT stop!",
                "The hunter is close! Run! We can do this!",
                "We are being hunted. Stay calm and keep moving!",
            ],
        ],
        "sarcastic": [
            "dungeonStart": [
                "Oh great. Another dungeon. My favourite. Truly thrilling.",
                "Right then. Try not to die immediately this time. That would be embarrassing.",
                "Another day, another cursed dungeon. You had better make this worth my time.",
            ],
            "levelUp": [
                "Level {lvl}. Took you long enough. I was starting to worry.",
                "Oh look, you levelled up. Congratulations on doing the bare minimum.",
                "Level {lvl}! Only took forever. You are welcome for my guidance.",
            ],
            "lowHp": [
                "Oh brilliant. You are almost dead. Wonderful strategy.",
                "Use a potion before you embarrass both of us by dying here.",
                "Your health is terrible. Fix it. Please. For my sake at least.",
            ],
            "bossEncounter": [
                "A boss. Perfect. Because things were not already difficult enough.",
                "Oh it is a boss. How delightful. Try not to get killed immediately.",
                "The boss of this dungeon. No pressure. Actually, lots of pressure. Sorry.",
            ],
            "victory": [
                "Fine. I will admit it. That was actually impressive.",
                "You won. I was not worried at all. Obviously. Not even a little.",
                "Huh. You actually did it. I am... mildly impressed. Do not let it go to your head.",
            ],
            "death": [
                "Well. That happened. Get up and try again. You are embarrassing me.",
                "Died again. Shocking. Truly shocking. No one could have seen that coming.",
                "Right. Rest, reflect on your mistakes, and perhaps do better next time.",
            ],
            "achievement": [
                "You got an achievement. Good. Now get back to not dying.",
                "Achievement unlocked. Finally something worth noting.",
                "Oh an achievement. How exciting. Are you going to celebrate or keep going?",
            ],
            "hunterClose": [
                "Something is following us and I would very much like it to stop.",
                "The hunter is close. I suggest moving faster. Much faster.",
                "We are being hunted. This is fine. Everything is fine. MOVE.",
            ],
        ],
        "mysterious": [
            "dungeonStart": [
                "The stones remember those who walked here before. Walk carefully.",
                "Something waits in the dark ahead. It has been waiting a long time.",
                "I have seen what lies beyond these walls. Tread with purpose.",
            ],
            "levelUp": [
                "The power within you grows. Level {lvl}. The dungeon feels it too.",
                "You become more than you were. Level {lvl}. The walls remember.",
                "Growth. Level {lvl}. You are not the same as when you entered.",
            ],
            "lowHp": [
                "The veil between life and death grows thin. Heal before it takes you.",
                "Your light dims. Restore it before the darkness claims what remains.",
                "Death watches from the corner. Do not give it reason to step forward.",
            ],
            "bossEncounter": [
                "It has waited for you. Longer than you know. Do not disappoint it.",
                "The heart of this dungeon beats before you. Face it with everything you are.",
                "Ancient power stirs. It knows your name. Show it why that matters.",
            ],
            "victory": [
                "The dungeon bows to you. For now.",
                "You have silenced what many could not. The walls remember this.",
                "Victory. But something deeper stirs. The dungeon is not finished with you.",
            ],
            "death": [
                "The dark takes you. But darkness is not permanent. Return.",
                "Even in death there is a lesson. Find it. Come back changed.",
                "The dungeon claims you for now. It will not hold you forever.",
            ],
            "achievement": [
                "A mark is made in the great record. You have been noticed.",
                "The achievement echoes through the dungeon walls. They remember.",
                "Something ancient acknowledges what you have done.",
            ],
            "hunterClose": [
                "Something follows that was not here before. It has a purpose.",
                "The hunter draws near. Its intent is singular. Do not let it catch you.",
                "Footsteps that are not yours. Close now. Very close.",
            ],
        ],
        "calm": [
            "dungeonStart": [
                "Ready when you are.",
                "The dungeon awaits. Take your time.",
                "I am here. Let us go.",
            ],
            "levelUp": [
                "Level {lvl}. Well done.",
                "Stronger now. Good.",
                "Level {lvl}. Keep going.",
            ],
            "lowHp": [
                "Heal up.",
                "Your HP is low. A potion would help.",
                "Take care of yourself first.",
            ],
            "bossEncounter": [
                "The boss. You are ready.",
                "This is the floor boss. Stay focused.",
                "Three phases. Take it one at a time.",
            ],
            "victory": [
                "Well done.",
                "You won. Good fight.",
                "Clean. Let us move on.",
            ],
            "death": [
                "Rest. Come back.",
                "Not today. Try again.",
                "It happens. Return when ready.",
            ],
            "achievement": [
                "Achievement earned.",
                "Well deserved.",
                "Good.",
            ],
            "hunterClose": [
                "Keep moving.",
                "Hunter is close. Do not stop.",
                "Move.",
            ],
        ],
    ]
}
