import Foundation

/// Hide and Seek, single player: a 7×7 house, you start in one corner and
/// the way out is in the other, and the Darkness Swallower closes in one
/// room on every move unless a Hide works.
public struct HideAndSeek: Codable, Sendable {
    public static let size = 7
    /// HS_CHASE_THRESHOLD: this close or closer, the chase music plays.
    public static let chaseDistance = 4

    public static let roomDescs = [
        "A narrow hallway stretches ahead. The air is cold.",
        "You pass a door hanging off one hinge.",
        "Something scratches at the walls, far off.",
        "The floorboards creak with every step. You wince.",
        "A broken window lets in a sliver of moonlight.",
        "You hear breathing that is not yours.",
        "Dust hangs in the air, undisturbed until now.",
        "A hallway splits ahead. You pick one at random.",
        "Something moved, just at the edge of your hearing.",
        "The silence presses in on you.",
        "A chair lies on its side. You do not remember knocking it over.",
        "The walls narrow here. There is not much room to run.",
    ]

    public struct HideItem: Sendable { public let name, icon, desc: String }

    public static let hideItems = [
        HideItem(name: "Torn Curtain", icon: "🧥", desc: "Something to pull over yourself."),
        HideItem(name: "Loose Floorboard", icon: "🪵", desc: "A gap just big enough to slip into."),
        HideItem(name: "Old Coat Closet", icon: "🚪", desc: "Cracked open. Room for one."),
    ]

    static let monsterStarts = [(size - 1, 0), (0, size - 1), (size - 1, size - 1), (size - 1, size / 2), (size / 2, size - 1)]

    public var active = true
    public var moves = 0
    public var px = 0, py = 0
    public let ex = size - 1, ey = size - 1
    public var mx: Int, my: Int
    public var hideCooldown = 0
    public var hidSuccessPending = false
    public var items = 0

    public init(dice: inout some Dice) {
        let m = Self.monsterStarts[dice.roll(0...(Self.monsterStarts.count - 1))]
        mx = m.0
        my = m.1
    }

    /// Rooms between you and it.
    public var distance: Int { abs(px - mx) + abs(py - my) }
    public var chasing: Bool { distance <= Self.chaseDistance }

    /// Which way it is, for the growl's left-right panning (-1 left, 1 right).
    public var pan: Double {
        let dx = mx - px, dy = my - py
        if dx == 0 && dy == 0 { return 0 }
        guard abs(dx) >= abs(dy) else { return 0 }
        return dx > 0 ? 0.8 : -0.8
    }

    /// How loud it sounds: closer is louder.
    public var volume: Double { max(0.15, 1 - Double(distance) * 0.08) }

    /// hsMonsterAdvance: one room closer on the longer axis.
    mutating func advance() {
        let dx = px - mx, dy = py - my
        if dx == 0 && dy == 0 { return }
        if abs(dx) >= abs(dy) { mx += dx > 0 ? 1 : -1 } else { my += dy > 0 ? 1 : -1 }
    }

    public enum Outcome: Equatable, Sendable { case none, wall, caught, escaped }

    public struct Step: Sendable {
        public var outcome: Outcome = .none
        public var desc = ""
        public var event = ""
        public var spoken = ""
    }

    public enum Direction: String, Sendable { case north, south, east, west }

    /// hsMove
    public mutating func move(_ dir: Direction, dice: inout some Dice) -> Step {
        var s = Step()
        guard active else { return s }
        if hideCooldown > 0 { hideCooldown -= 1 }
        var moved = true
        switch dir {
        case .north: if py > 0 { py -= 1 } else { moved = false }
        case .south: if py < Self.size - 1 { py += 1 } else { moved = false }
        case .west: if px > 0 { px -= 1 } else { moved = false }
        case .east: if px < Self.size - 1 { px += 1 } else { moved = false }
        }
        guard moved else {
            s.outcome = .wall
            s.spoken = "There is a wall that way. Try a different direction."
            return s
        }
        moves += 1
        if hidSuccessPending { hidSuccessPending = false } else { advance() }
        s.desc = Self.roomDescs[dice.roll(0...(Self.roomDescs.count - 1))]
        var found: HideItem?
        if items < 2 && dice.chance(0.20) {
            let item = Self.hideItems[dice.roll(0...(Self.hideItems.count - 1))]
            items += 1
            found = item
            s.event = "\(item.icon) You spot a \(item.name). \(item.desc)"
        }
        if distance <= 0 {
            active = false
            s.outcome = .caught
            return s
        }
        if px == ex && py == ey {
            active = false
            s.outcome = .escaped
            return s
        }
        s.spoken = "Moving \(dir.rawValue). \(s.desc)" + (found.map { " You spot a \($0.name). \($0.desc) It will help you hide." } ?? "")
        let warn = [6: "You can hear it somewhere behind you.", 4: "It is getting closer. You should move faster.",
                    2: "It is right behind you. Hide, or run.", 1: "It is almost on you."]
        if let w = warn[distance] { s.spoken += " " + w }
        return s
    }

    /// hsHide: 55%, or 80% using something you found. A good hide makes your
    /// next move safe; a bad one lets it close in right away.
    public mutating func hide(dice: inout some Dice) -> Step {
        var s = Step()
        guard active else { return s }
        if hideCooldown > 0 {
            s.event = "⏳ Still catching your breath from last time."
            s.spoken = "You just hid. Give it a moment before trying again."
            return s
        }
        hideCooldown = 1
        let usedItem = items > 0
        if usedItem { items -= 1 }
        if dice.chance(0.55 + (usedItem ? 0.25 : 0)) {
            hidSuccessPending = true
            s.event = usedItem ? "🫥 You duck out of sight and wait. It passes right by, unaware."
                : "🫥 You hold your breath. It passes by, closer than you'd like."
            s.spoken = (usedItem ? "You hid using what you found. " : "You hid successfully. ") + "It lost your trail — your next move is safe."
        } else {
            advance()
            s.event = "🫥 You hide, but it senses you anyway."
            s.spoken = "It sensed you. Now \(distance) \(distance == 1 ? "room" : "rooms") away."
            if distance <= 0 {
                active = false
                s.outcome = .caught
            }
        }
        return s
    }
}
