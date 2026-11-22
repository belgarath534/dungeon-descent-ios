import Foundation

/// ENDLESS DESCENT RIVALS: other players' best Endless Descent floors (the
/// online "afk-rivals" ladder). The Lock Screen shows the next one above the
/// floor you're on, and who you just passed.
public enum AFKRivals {
    /// The online ladder everyone's best floor goes into.
    public static let season = "afk-rivals"

    public struct Rival: Equatable, Sendable {
        public let name: String
        public let floor: Int
        public init(name: String, floor: Int) {
            self.name = name
            self.floor = floor
        }
    }

    /// "Next rival: Mira, floor 57, 5 to go." Having passed someone on this
    /// floor, that comes first: "Passed Kai (floor 51)!" Nil without rivals.
    public static func line(floor: Int, rivals: [Rival]) -> String? {
        guard !rivals.isEmpty else { return nil }
        let above = rivals.filter { $0.floor >= floor }.min { $0.floor < $1.floor }
        let passed = rivals.filter { $0.floor == floor - 1 }.first
        var parts: [String] = []
        if let p = passed { parts.append("Passed \(p.name) (floor \(p.floor))!") }
        if let a = above {
            let gap = a.floor - floor
            parts.append("Next rival: \(a.name), floor \(a.floor)" + (gap == 0 ? ", level with you." : ", \(gap) to go."))
        } else {
            parts.append("You're deeper than every rival on the board!")
        }
        return parts.joined(separator: " ")
    }
}
