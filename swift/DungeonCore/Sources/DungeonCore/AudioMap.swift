import Foundation

/// 12.0 AUDIO MAP: the floor played as sounds placed around you, then a
/// spoken summary. In 3D Mode each room you know of sounds from where it
/// really is (north in front, east to the right). Otherwise the floor plays
/// left to right like a progress bar: the rooms behind you, you, the rooms
/// still ahead, then the stairs (or the boss).
public enum AudioMap {
    public enum Kind: String, Sendable, CaseIterable {
        /// Where you stand.
        case you
        /// A room you've been in.
        case explored
        /// A room you know is there (a door leads to it) but haven't entered.
        case unexplored
        /// The way down, once the floor is done.
        case stairs
        /// The boss waiting at the end of this floor.
        case boss
        /// The enemy you're fighting.
        case enemy
        /// Hunter Mode: the hunter on your trail.
        case hunter
    }

    /// One sound. `x` is meters to the east (negative is west), `z` meters to
    /// the south (negative is in front of you), like SpatialAudio's points.
    public struct Cue: Sendable, Equatable {
        public var kind: Kind
        public var x: Double
        public var z: Double
        public var delay: Double
    }

    public struct Map: Sendable {
        public var cues: [Cue]
        public var summary: String
    }

    /// The most sounds a map plays (the audio engine has 20 voices).
    public static let maxCues = 18
    /// Seconds between sounds.
    public static let gap = 0.22

    public static let legend = "A soft low note is a room you've been in, a brighter blip is a room you haven't entered, falling notes are the stairs and a deep growl is the boss."

    /// The map for the run as it stands. `hunterFrom` is where the hunter
    /// follows from; `bossFloor` is this run's boss floor (Challenges).
    public static func build(_ run: Run, bossFloor: Int = 10, hunterFrom: Compass = .south) -> Map {
        let isBossFloor = run.floor >= bossFloor && run.difficulty != .endless
        let left = max(0, run.floorRoomsNeeded - run.roomsOnFloor)
        var cues: [Cue] = [Cue(kind: .you, x: 0, z: 0, delay: 0)]
        var summary = "Audio map. Floor \(run.floor)."

        if let g = run.roomGraph {
            // Rooms you've seen, and the ones their doors lead to.
            var known: [(RoomGraph.Cell, Bool)] = []
            var seen = Set<String>()
            let all = g.cells.values.sorted { ($0.gy, $0.gx) < ($1.gy, $1.gx) }
            for c in all where c.visited {
                if seen.insert("\(c.gx),\(c.gy)").inserted { known.append((c, true)) }
            }
            for c in all where c.visited {
                for d in c.doors {
                    if let n = g.cell(c.gx + d.dx, c.gy + d.dy), !n.visited, seen.insert("\(n.gx),\(n.gy)").inserted {
                        known.append((n, false))
                    }
                }
            }
            let here = g.here
            let others = known.filter { !($0.0.gx == here.gx && $0.0.gy == here.gy) }
                .sorted { a, b in
                    let da = abs(a.0.gx - here.gx) + abs(a.0.gy - here.gy), db = abs(b.0.gx - here.gx) + abs(b.0.gy - here.gy)
                    return da != db ? da < db : (a.0.gx, a.0.gy) < (b.0.gx, b.0.gy)
                }
            for (c, visited) in others.prefix(maxCues - 3) {
                cues.append(Cue(kind: visited ? .explored : .unexplored,
                                x: Double(c.gx - here.gx) * 2, z: Double(c.gy - here.gy) * 2, delay: 0))
            }
            let explored = known.filter { $0.1 }.count
            let open = known.filter { !$0.1 }.count
            summary += " \(explored) room\(explored == 1 ? "" : "s") explored, \(open) you haven't entered yet."
            summary += " " + RoomGraph.exitsText(here)
        } else {
            // Left to right: done, you, ahead, the end.
            let total = min(maxCues - 3, max(1, run.floorRoomsNeeded))
            let done = min(run.roomsOnFloor, total)
            let slots = total + 2
            func x(_ i: Int) -> Double { slots <= 1 ? 0 : -4 + 8 * Double(i) / Double(slots - 1) }
            cues = []
            for i in 0..<done { cues.append(Cue(kind: .explored, x: x(i), z: 0, delay: 0)) }
            cues.append(Cue(kind: .you, x: x(done), z: 0, delay: 0))
            for i in done..<total { cues.append(Cue(kind: .unexplored, x: x(i + 1), z: 0, delay: 0)) }
        }

        // The end of the floor: at the far right of the line, or (3D Mode,
        // where it has no room of its own) right here once the floor is done.
        let endKind: Kind = isBossFloor ? .boss : .stairs
        if run.roomGraph == nil { cues.append(Cue(kind: endKind, x: 4, z: 0, delay: 0)) }
        else if left == 0 { cues.append(Cue(kind: endKind, x: 0, z: -1, delay: 0)) }
        if left == 0 {
            summary += isBossFloor ? " The boss is here." : " The floor is done: the stairs are open."
        } else if run.roomGraph == nil {
            summary += " \(run.roomsOnFloor) room\(run.roomsOnFloor == 1 ? "" : "s") behind you, \(left) ahead, then \(isBossFloor ? "the boss" : "the stairs")."
        } else {
            summary += " \(left) more room\(left == 1 ? "" : "s") to find before \(isBossFloor ? "the boss" : "the stairs")."
        }

        // Who's here.
        if let e = run.enemy, e.hp > 0 {
            cues.append(Cue(kind: .enemy, x: 0, z: -2, delay: 0))
            summary += " \(e.name) is in front of you."
        }
        if let h = run.hunter {
            let m = Double(min(10, max(1, h.dist)))
            cues.append(Cue(kind: .hunter, x: Double(hunterFrom.dx) * m, z: Double(hunterFrom.dy) * m, delay: 0))
            summary += " " + Hunter.line(h.dist)
        }

        for i in cues.indices { cues[i].delay = Double(i) * gap }
        return Map(cues: Array(cues.prefix(maxCues)), summary: summary)
    }
}
