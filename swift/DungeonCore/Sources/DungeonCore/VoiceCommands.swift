import Foundation

/// 12.1 VOICE COMMANDS IN FIGHTS (a player's request): what was heard,
/// matched to one of the moves on screen. Each option is a phrase ("revive
/// mortarion", "heavy") and the action it means; the first option whose
/// words were all heard wins, so specific phrases go first.
public enum VoiceCommands {
    public struct Option: Equatable, Sendable {
        public let phrase: String
        public let action: String
        public init(_ phrase: String, _ action: String) { self.phrase = phrase; self.action = action }
    }

    static func words(_ s: String) -> [String] {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    public static func match(_ heard: String, _ options: [Option]) -> String? {
        let said = words(heard)
        guard !said.isEmpty else { return nil }
        let set = Set(said)
        // Longest phrases first among equals, so "heavy attack" beats "attack".
        for o in options.enumerated().sorted(by: { (words($0.element.phrase).count, -$0.offset) > (words($1.element.phrase).count, -$1.offset) }).map(\.element) {
            let need = words(o.phrase)
            if !need.isEmpty && need.allSatisfy(set.contains) { return o.action }
        }
        return nil
    }

    /// The basic moves every fight has (solo and co-op share the action names).
    public static let basics: [Option] = [
        Option("heavy", "heavy"), Option("heavy attack", "heavy"), Option("heavy strike", "heavy"), Option("smash", "heavy"),
        Option("attack", "attack"), Option("hit", "attack"), Option("strike", "attack"), Option("fight", "attack"),
        Option("defend", "defend"), Option("block", "defend"), Option("guard", "defend"), Option("shield", "defend"),
        Option("potion", "potion"), Option("drink", "potion"), Option("heal me", "potion"),
        Option("shoot", "gun"), Option("gun", "gun"), Option("fire", "gun"),
    ]
}
