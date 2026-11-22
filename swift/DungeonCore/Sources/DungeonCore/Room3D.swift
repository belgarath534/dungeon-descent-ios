import Foundation

/// A compass direction in 3D Mode's room grid. North is "ahead" (y goes down
/// the grid going north, like the web version's ROOM3D_DIRS).
public enum Compass: String, Codable, CaseIterable, Sendable {
    case north, south, east, west

    public var dx: Int { self == .east ? 1 : self == .west ? -1 : 0 }
    public var dy: Int { self == .south ? 1 : self == .north ? -1 : 0 }
    public var opposite: Compass {
        switch self {
        case .north: return .south
        case .south: return .north
        case .east: return .west
        case .west: return .east
        }
    }
}

/// 3D MODE: the floor as a connected grid of rooms with real walls and doors.
/// Walls decide when the next room happens; everything inside a room is the
/// same enterRoom() every other run uses.
public struct RoomGraph: Codable, Sendable, Equatable {
    public struct Cell: Codable, Sendable, Equatable {
        public var gx: Int
        public var gy: Int
        public var doors: [Compass] = []
        public var visited = false

        public func has(_ d: Compass) -> Bool { doors.contains(d) }
    }

    public private(set) var cells: [String: Cell] = [:]
    public private(set) var gx = 0
    public private(set) var gy = 0
    /// The way you last walked; the way you're facing.
    public private(set) var lastMove: Compass?

    static func key(_ x: Int, _ y: Int) -> String { "\(x),\(y)" }

    /// generate3DRoomGraph: a random walk from (0,0). The start room is one
    /// more than the floor needs, since standing in it never counts.
    public init(roomsNeeded: Int, dice: inout some Dice) {
        cells[Self.key(0, 0)] = Cell(gx: 0, gy: 0, visited: true)
        grow(max(2, roomsNeeded + 1) - 1, dice: &dice)
    }

    /// extend3DRoomGraph: Wander adds rooms to the floor, so the map grows too.
    public mutating func extend(_ n: Int, dice: inout some Dice) { grow(n, dice: &dice) }

    private mutating func grow(_ n: Int, dice: inout some Dice) {
        var order = cells.keys.sorted()
        var added = 0, guardCount = 0
        while added < n && guardCount < 2000 {
            guardCount += 1
            let fromKey = order[dice.roll(0...(order.count - 1))]
            guard var from = cells[fromKey] else { continue }
            var dirs = Compass.allCases
            for i in stride(from: dirs.count - 1, to: 0, by: -1) { dirs.swapAt(i, dice.roll(0...i)) }
            for d in dirs {
                let k = Self.key(from.gx + d.dx, from.gy + d.dy)
                if cells[k] != nil { continue }
                cells[k] = Cell(gx: from.gx + d.dx, gy: from.gy + d.dy, doors: [d.opposite])
                from.doors.append(d)
                cells[fromKey] = from
                order.append(k)
                added += 1
                break
            }
        }
    }

    public var here: Cell { cells[Self.key(gx, gy)] ?? Cell(gx: gx, gy: gy) }
    public func cell(_ x: Int, _ y: Int) -> Cell? { cells[Self.key(x, y)] }
    public func neighbor(_ d: Compass) -> Cell? { here.has(d) ? cell(gx + d.dx, gy + d.dy) : nil }
    public var unvisited: Int { cells.values.filter { !$0.visited }.count }

    public enum Step: Equatable, Sendable { case wall, entered(firstVisit: Bool) }

    /// moveRoom3D: a door takes you through; a wall doesn't.
    public mutating func move(_ d: Compass) -> Step {
        guard here.has(d), var target = cell(gx + d.dx, gy + d.dy) else { return .wall }
        let first = !target.visited
        target.visited = true
        gx = target.gx
        gy = target.gy
        lastMove = d
        cells[Self.key(gx, gy)] = target
        return .entered(firstVisit: first)
    }

    /// A room you walked into that didn't count (the Darkness Swallower took
    /// you first) stays new.
    public mutating func unvisitHere() {
        guard var c = cells[Self.key(gx, gy)] else { return }
        c.visited = false
        cells[Self.key(gx, gy)] = c
    }

    /// Never run out of new rooms before the floor is done. (The web version
    /// could strand you with every room visited and the floor one short.)
    public mutating func ensureRooms(left needed: Int, dice: inout some Dice) {
        if unvisited < needed { grow(needed - unvisited, dice: &dice) }
    }

    /// _room3DExitsText
    public static func exitsText(_ cell: Cell) -> String {
        let exits = Compass.allCases.filter { cell.has($0) }.map(\.rawValue)
        switch exits.count {
        case 0: return "No other doors from here."
        case 1: return "A door to the \(exits[0])."
        default: return "Doors to the \(exits.dropLast().joined(separator: ", ")) and \(exits.last!)."
        }
    }

    public var exitsText: String { Self.exitsText(here) }

    /// _corridorDepth: how many rooms run straight on through doors that way.
    public func corridorDepth(_ d: Compass, max maxDepth: Int = 3) -> Int {
        var depth = 0
        var cur: Cell? = here
        var x = gx, y = gy
        while depth < maxDepth, let c = cur, c.has(d) {
            x += d.dx
            y += d.dy
            cur = cell(x, y)
            if cur == nil { break }
            depth += 1
        }
        return depth
    }

    // MARK: Echo-location

    /// What the next new room holds, read from the floor's plan: every
    /// unvisited door leads to the same next room.
    public enum Ahead: String, Sendable { case danger, good, mystery }

    public static func ahead(_ run: Run) -> Ahead? {
        guard run.roomPlan.indices.contains(run.roomsOnFloor) else { return nil }
        switch run.roomPlan[run.roomsOnFloor] {
        case "cursed": return .danger
        case "treasure", "rest", "merchant": return .good
        case "secret": return .mystery
        default: return nil
        }
    }

    public struct Echo: Sendable, Equatable {
        public struct Open: Sendable, Equatable {
            public var dir: Compass
            public var depth: Int
            public var ahead: Ahead?
        }
        public var open: [Open] = []
        public var walls: [Compass] = []
        public var summary = ""
    }

    /// echoLocate: open doors, walls, and what stirs beyond the new ones.
    public func echo(ahead: Ahead?) -> Echo {
        var e = Echo()
        var beyond: [Ahead: [String]] = [:]
        for d in Compass.allCases {
            if here.has(d) {
                let n = neighbor(d)
                let a = (n?.visited == false) ? ahead : nil
                e.open.append(.init(dir: d, depth: corridorDepth(d), ahead: a))
                if let a { beyond[a, default: []].append(d.rawValue) }
            } else {
                e.walls.append(d)
            }
        }
        var s = e.open.isEmpty ? "Echo-location: walls on every side."
            : "Echo-location: open to the \(e.open.map(\.dir.rawValue).joined(separator: ", "))."
                + (e.walls.isEmpty ? "" : " Wall to the \(e.walls.map(\.rawValue).joined(separator: ", ")).")
        if let w = beyond[.danger] { s += " Something dangerous stirs beyond the \(w.joined(separator: ", "))." }
        if let w = beyond[.good] { s += " Something promising lies beyond the \(w.joined(separator: ", "))." }
        if let w = beyond[.mystery] { s += " Something uncertain waits beyond the \(w.joined(separator: ", "))." }
        e.summary = s
        return e
    }
}

/// The Beta Features switch and 3D Settings, in the web version's keys.
public enum ThreeDMode {
    public static func isOn(_ store: GameStore) -> Bool { beta(store)["3dmode"] == true }

    public static func setOn(_ on: Bool, store: GameStore) {
        var f = beta(store)
        f["3dmode"] = on
        if let d = try? JSONEncoder().encode(f), let s = String(data: d, encoding: .utf8) { store.setItem("dd_beta_features", s) }
    }

    static func beta(_ store: GameStore) -> [String: Bool] {
        guard let s = store.getItem("dd_beta_features"), let d = s.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return ["3dmode": false] }
        return any.compactMapValues { $0 as? Bool }
    }

    public struct Settings: Codable, Sendable, Equatable {
        public var shadows = false
        public var torchFlicker = true
        public var fpsCounter = false
        public var minimap = true
        public init() {}
    }

    /// get3DSettings: saved values over the defaults.
    public static func settings(_ store: GameStore) -> Settings {
        var s = Settings()
        guard let raw = store.getItem("dd_3d_settings"), let d = raw.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return s }
        if let v = any["shadows"] as? Bool { s.shadows = v }
        if let v = any["torchFlicker"] as? Bool { s.torchFlicker = v }
        if let v = any["fpsCounter"] as? Bool { s.fpsCounter = v }
        if let v = any["minimap"] as? Bool { s.minimap = v }
        return s
    }

    public static func save(_ s: Settings, store: GameStore) {
        if let d = try? JSONEncoder().encode(s), let str = String(data: d, encoding: .utf8) { store.setItem("dd_3d_settings", str) }
    }
}
