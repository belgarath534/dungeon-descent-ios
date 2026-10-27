import Foundation

/// THE STALKER FLOOR (The Shadow World): a dark 5×5 room with the Darkness
/// Swallower in it. Reach an edge three times to escape; it steps toward you
/// every time you move. Its growl tells you where it is.
public struct StalkerFloor: Codable, Sendable, Equatable {
    public static let size = 5
    public static let escapesNeeded = 3

    public var px = 2, py = 2
    public var ex: Int, ey: Int
    public var escapes = 0

    public init(dice: inout some Dice) {
        let edges = [(0, 0), (4, 0), (0, 4), (4, 4), (2, 0), (2, 4), (0, 2), (4, 2)]
        let e = edges[dice.roll(0...(edges.count - 1))]
        ex = e.0
        ey = e.1
    }

    public var distance: Int { abs(px - ex) + abs(py - ey) }

    /// getStalkerDirection: which way it is, from you.
    public var direction: String {
        let dx = ex - px, dy = ey - py
        if abs(dx) >= abs(dy) { return dx > 0 ? "right" : "left" }
        return dy > 0 ? "ahead" : "behind"
    }

    /// The growl's left-right panning and loudness.
    public var pan: Double { direction == "left" ? -0.8 : direction == "right" ? 0.8 : 0 }
    public var growlVolume: Double { max(0.2, 1 - Double(distance) * 0.15) }
    public var stepVolume: Double { max(0.1, 1 - Double(distance) * 0.12) }

    public enum Outcome: Equatable, Sendable { case moved, escapedOnce, escaped, caught }

    /// stalkerMove: you step (a wall keeps you in place, but it still comes),
    /// then it closes in along its longer gap.
    public mutating func move(_ dir: String) -> Outcome {
        switch dir {
        case "north": py = max(0, py - 1)
        case "south": py = min(Self.size - 1, py + 1)
        case "west": px = max(0, px - 1)
        case "east": px = min(Self.size - 1, px + 1)
        default: break
        }
        // Walking into it is being caught. (The web version still moved it
        // first, stepping it off you.)
        if distance == 0 { return .caught }
        let dx = px - ex, dy = py - ey
        if abs(dx) >= abs(dy) { ex += dx > 0 ? 1 : -1 } else { ey += dy > 0 ? 1 : -1 }
        if distance == 0 { return .caught }
        if px == 0 || px == Self.size - 1 || py == 0 || py == Self.size - 1 {
            escapes += 1
            if escapes >= Self.escapesNeeded { return .escaped }
            px = 2
            py = 2
            return .escapedOnce
        }
        return .moved
    }

    /// What the status line reads.
    public var status: String {
        "🌑 \(distance) step\(distance != 1 ? "s" : "") away — \(direction).  Escapes: \(escapes) / \(Self.escapesNeeded)"
    }

    /// The line after a step.
    public func report(_ dir: String) -> String {
        let hint = direction == "ahead" || direction == "behind" ? " — \(direction) of you" : ""
        switch distance {
        case 1: return "💀 The Darkness Swallower is right next to you. You can hear it breathe."
        case 2: return "⚠️ It is 2 steps away\(hint)."
        default: return "👣 \(dir). The Darkness Swallower is \(distance) step\(distance != 1 ? "s" : "") away\(hint)."
        }
    }

    // MARK: In a run

    /// checkStalkerFloor: in The Shadow World from floor 3, 10% of rooms.
    public static func shouldStart(_ run: Run, dice: inout some Dice) -> Bool {
        run.dungeon == ShadowWorld.name && run.floor >= 3 && !run.inCombat && run.stalker == nil && dice.chance(0.10)
    }

    /// stalkerCaught: 35% of your max HP, but it leaves you standing.
    public static func caught(_ run: inout Run) -> Int {
        let dmg = jsRound(Double(run.maxHp) * 0.35)
        run.hp = max(1, run.hp - dmg)
        run.stalker = nil
        return dmg
    }

    /// stalkerEscaped: 150 gold and a Shadow World weapon or armor.
    public static func escaped(_ run: inout Run, wallet: Wallet, dice: inout some Dice) -> Item? {
        run.stalker = nil
        run.gold += 150
        wallet.addGold(150)
        let gear = ItemTables.loot(for: ShadowWorld.name).filter { $0.isWeapon || $0.isArmor }
        guard !gear.isEmpty else { return nil }
        let item = gear[dice.roll(0...(gear.count - 1))]
        run.inventory.append(item)
        return item
    }

    /// stalkerChooseFight: face it when it's one step away.
    public static func fight(_ run: inout Run) -> Enemy {
        run.stalker = nil
        let hp = jsRound(Double(run.maxHp) * 1.5)
        let top = run.atk.upperBound
        var e = Enemy(name: "The Darkness Swallower", icon: "🌑", hp: hp, maxHp: hp,
                      atk: jsRound(Double(top) * 1.2)...jsRound(Double(top) * 1.8), gold: 80...150)
        e.mechanics["corruptOnHit"] = .number(2)
        e.desc = "It has been waiting in this room for 3000 years. You chose to fight it. That was very brave. Possibly very stupid."
        return e
    }
}
