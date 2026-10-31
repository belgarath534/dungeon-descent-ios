import Foundation

/// What the iPhone and the Apple Watch say to each other. The phone keeps the
/// save and runs Endless Descent; the watch asks it for the state and sends
/// commands. Everything goes over WatchConnectivity as JSON under "payload".
enum WatchLink {
    static let commandKey = "cmd"
    static let indexKey = "index"
    static let payloadKey = "payload"

    enum Command: String {
        case status, start, potion, end
    }

    struct Character: Codable, Identifiable, Equatable {
        var index: Int
        var name: String
        var cls: String
        var level: Int
        var dungeon: String
        var id: Int { index }
    }

    struct Run: Codable, Equatable {
        var charName: String
        var cls: String
        var floor: Int
        var hp: Int
        var maxHp: Int
        var level: Int
        var points: Int
        var potions: Int
        var enemiesDefeated: Int
        var bossesDefeated: Int
        var running: Bool
        /// When the next fight happens (seconds since 1970).
        var nextFightAt: Double
        var startedAt: Double
        /// The newest log lines, newest first.
        var log: [String]
    }

    struct Snapshot: Codable, Equatable {
        var characters: [Character]
        /// The run going now, or the one that just ended (running == false).
        var run: Run?
        var totalPoints: Int
        var bestFloor: Int
        /// The answer to the last command ("Potion used …", "Pick your skills on your iPhone …").
        var message: String?
        var sentAt: Double
    }

    static func encode(_ s: Snapshot) -> [String: Any] {
        guard let d = try? JSONEncoder().encode(s) else { return [:] }
        return [payloadKey: d]
    }

    static func decode(_ dict: [String: Any]) -> Snapshot? {
        guard let d = dict[payloadKey] as? Data else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: d)
    }
}
