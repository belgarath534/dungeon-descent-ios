import Foundation

/// OFFLINE AFK CATCH-UP (checkOfflineProgress): after an hour or more away,
/// your first character "rested" and comes back with gold (35 plus 4 a level
/// for every hour, up to 8 hours) and a Soul Fragment for every two hours.
///
/// The web version only measured the time between two launches of the game,
/// so leaving it open in the background and coming back never counted. Here
/// the time you leave the app is remembered too ("dd_last_seen").
public enum OfflineRest {
    public struct Reward: Equatable, Sendable {
        public let name: String
        public let hoursText: String
        public let gold: Int
        public let kills: Int
        public let fragments: Int
    }

    static let key = "dd_last_seen"

    /// Leaving the app (or using it): this is when you were last here.
    public static func seen(_ store: GameStore, now: Date = Date()) {
        store.setItem(key, String(Int(now.timeIntervalSince1970 * 1000)))
    }

    /// Opening or coming back: the reward for the time away, if it was an
    /// hour or more. Pays the gold and fragments into the store.
    public static func check(_ store: GameStore, wallet: Wallet, character: PlayerCharacter?,
                             now: Date = Date()) -> Reward? {
        let last = Double(store.getItem(key) ?? "") ?? 0
        seen(store, now: now)
        guard last > 0, let ch = character else { return nil }
        let hours = (now.timeIntervalSince1970 * 1000 - last) / 3_600_000
        guard hours >= 1 else { return nil }
        let capped = min(hours, 8)
        let level = max(1, ch.persistLevel ?? 1)
        let gold = Int((Double(35 + level * 4) * capped).rounded())
        let kills = Int((capped * 8).rounded())
        let fragments = Int(capped / 2)
        wallet.addGold(gold)
        if fragments > 0 {
            store.setItem("dd_soul_fragments", String(CustomSpirits.fragments(store) + fragments))
        }
        return Reward(name: ch.name, hoursText: capped >= 2 ? "\(Int(capped)) hours" : "about an hour",
                      gold: gold, kills: kills, fragments: fragments)
    }
}
