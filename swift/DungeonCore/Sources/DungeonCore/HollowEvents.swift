import Foundation

/// The Hollow's special encounters before a fight (enterRoom): the Weeping
/// Child (THE WEEPING CHILD) and the Weeping Mother (WEEPING MOTHER), and the
/// Music Box enemy's melody and the Music Box it leaves for the Child.
public enum HollowEvents {
    static let hollow = "The Hollow"

    /// A Weeping Child (floor 3+, 10%) or Weeping Mother (floor 5+, 7%) in
    /// place of this room's fight. A Paladin with class traits soothes the
    /// Child just by being there (Divine Presence).
    public static func encounter(_ run: inout Run, classTraits: Bool, dice: inout some Dice) -> (event: String?, line: String?) {
        guard run.dungeon == hollow else { return (nil, nil) }
        if run.floor >= 3 && dice.chance(run.weather?.silentNight == true ? 0.20 : 0.10) {
            if run.cls == "Paladin" && classTraits && !run.weepingChildSoothed {
                run.weepingChildSoothed = true
                return (nil, "🛡 Divine Presence. The Weeping Child is soothed by your holy aura.")
            }
            return (hasBox(run) ? "weeping-child-box" : "weeping-child", nil)
        }
        if run.floor >= 5 && dice.chance(0.07) {
            return (run.weepingChildSoothed ? "weeping-mother-child" : "weeping-mother", nil)
        }
        return (nil, nil)
    }

    static let childText = "In the corner of the room, something small is sitting with its knees pulled to its chest. It is crying. The sound fills the entire floor. You do not know how long it has been here. You do not know what it is. But something about it makes you very reluctant to draw your weapon."
    static let motherText = "A woman stands in the hallway. She is not looking at you. She is looking past you, through walls, through floors, through everything. She has been searching this house for longer than the house has existed."

    public static func event(_ id: String) -> Encounters.Event? {
        switch id {
        case "weeping-child":
            return Encounters.Event(id: id, title: "The Weeping Child", text: childText,
                                    choices: ["🤱 Pick It Up Gently", "🎵 Hum a Lullaby"], weight: 0, dungeons: nil)
        case "weeping-child-box":
            return Encounters.Event(id: id, title: "The Weeping Child", text: childText,
                                    choices: ["🤱 Pick It Up Gently", "🎵 Hum a Lullaby", "🎵 Play the Music Box (75%)"], weight: 0, dungeons: nil)
        case "weeping-mother-child":
            return Encounters.Event(id: id, title: "The Weeping Mother", text: motherText + " You realize you know what she is looking for.",
                                    choices: ["👶 Lead Her to the Child", "⚔ Fight Her"], weight: 0, dungeons: nil)
        case "weeping-mother":
            return Encounters.Event(id: id, title: "The Weeping Mother", text: motherText + " You do not have what she is looking for.",
                                    choices: ["🧹 Do a Chore For Her", "⚔ Fight Her"], weight: 0, dungeons: nil)
        default: return nil
        }
    }

    // MARK: The Music Box (the Hollow enemy and its item)

    public static func isBoxItem(_ i: Item) -> Bool { i.extra["isMusicBoxItem"] == .bool(true) }
    static func hasBox(_ run: Run) -> Bool { run.inventory.contains(where: isBoxItem) }

    static let boxItem: Item = {
        var i = Item(name: "Music Box", icon: "🎵", type: "keyitem",
                     desc: "A small mechanical box. The melody it plays is familiar. Use it on the Weeping Child.")
        i.extra["isMusicBoxItem"] = .bool(true)
        return i
    }()

    /// Beating The Music Box leaves its box behind, for the Weeping Child.
    public static func onKill(_ e: Enemy, _ run: inout Run) -> String? {
        guard e.flag("isMusicBox") else { return nil }
        run.inventory.append(boxItem)
        return "🎵 The Music Box dropped a Music Box item. It is now in your inventory. Use it on the Weeping Child."
    }

    /// musicBoxMelody: instead of attacking, the box plays: three notes of 6–10
    /// damage (half while defending).
    static func melody(_ run: inout Run, dice: inout some Dice, log: inout [String]) -> Bool {
        guard let e = run.enemy, e.flag("isMusicBox") else { return false }
        log.append("♪ The Music Box plays. Brace yourself.")
        for n in 1...3 where run.hp > 0 {
            var d = dice.roll(6...10)
            if run.defending { d = max(1, jsRound(Double(d) * 0.5)) }
            run.hp = max(0, run.hp - d)
            log.append("♪ Note \(n) of 3. \(d) damage. HP: \(run.hp)/\(run.maxHp).")
        }
        return true
    }

    // MARK: Choices

    static func child(_ run: Run) -> Enemy {
        let ng = run.ngPlus ? 1.20 : 1.0
        var e = Enemy(name: "The Weeping Child", icon: "😢", hp: jsRound(45 * ng), maxHp: jsRound(45 * ng),
                      atk: jsRound(12 * ng)...jsRound(20 * ng), gold: 15...25)
        e.desc = "It is small but it is furious."
        return e
    }

    static func mother(_ run: Run) -> Enemy {
        let ng = run.ngPlus ? 1.20 : 1.0
        var e = Enemy(name: "The Weeping Mother", icon: "👩", hp: jsRound(80 * ng), maxHp: jsRound(80 * ng),
                      atk: jsRound(16 * ng)...jsRound(26 * ng), gold: 25...40)
        e.desc = "She is not angry. She is simply looking for something and you are in the way."
        return e
    }

    static func choose(_ id: String, _ choice: Int, _ run: inout Run, dice: inout some Dice, wallet: Wallet) -> Encounters.Outcome {
        typealias Outcome = Encounters.Outcome
        func soothed(_ reward: Int, _ text: String) -> Outcome {
            run.weepingChildSoothed = true
            run.gold += reward
            wallet.addGold(reward)
            var o = Outcome(message: text, gold: reward)
            o.stat = "wepingChildSoothed"
            return o
        }
        if id.hasPrefix("weeping-child") {
            if choice == 2 {
                if let i = run.inventory.firstIndex(where: isBoxItem) { run.inventory.remove(at: i) }
                var o: Outcome
                if dice.chance(0.75) {
                    o = soothed(dice.roll(22...33), "You open the music box. The melody fills the room. The child goes very still. Its eyes grow heavy. It has heard this melody before. It remembers something safe. The child closes its eyes. It is asleep.")
                    o.message += " You gain \(o.gold) gold."
                } else {
                    o = Outcome(message: "You open the music box. The melody plays. Then it stops. The child opens its eyes. It stares at the music box. Then at you. It begins to scream.", enemy: child(run))
                }
                o.music = "music-box"
                return o
            }
            let pick = choice == 0
            if dice.chance(pick ? 0.50 : 0.55) {
                let reward = dice.roll(18...29)
                return soothed(reward, pick
                    ? "You pick up the child carefully. For a moment nothing happens. Then it stops crying. It closes its eyes. Its breathing slows. You set it down gently. It is asleep. You gain \(reward) gold and leave the room quietly."
                    : "You begin to hum. It is not a song you know. It comes from somewhere older. The child stops crying and listens. Its eyes grow heavy. It is asleep. You gain \(reward) gold and stand there for a moment before leaving.")
            }
            return Outcome(message: pick
                ? "The child startles awake as you reach for it. Its eyes fly open. What you see in them is not fear. It begins to scream."
                : "The humming stops working. The child looks up at you. Its expression changes. It was never just crying. It was warning you.",
                enemy: child(run))
        }
        // The Weeping Mother
        if choice == 1 {
            return Outcome(message: "She turns to face you fully for the first time. Her expression does not change. It was never going to change.", enemy: mother(run))
        }
        if id == "weeping-mother-child" {
            let reward = dice.roll(30...49)
            run.gold += reward
            wallet.addGold(reward)
            run.maxHp += 5
            run.hp = min(run.maxHp, run.hp + 20)
            var o = Outcome(message: "You lead her through the corridors. She follows without a word. When she sees the child sleeping in the corner she stops. She kneels down. She does not cry anymore. She looks at you once. Then she is gone. Both of them are gone. The room feels different now. Lighter. You gain \(reward) gold. Your max HP increases by 5.", gold: reward)
            o.stat = "motherReunion"
            return o
        }
        let cost = dice.roll(15...24)
        run.hp = max(1, run.hp - cost)
        return Outcome(message: "You spend time helping her. Moving furniture. Searching rooms. Looking in places you would rather not look. She watches without speaking. Eventually she steps aside. You lost \(cost) HP but you are still alive.")
    }
}
