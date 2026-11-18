import Foundation

/// PLAYTIME TRACKER: total time with the game open, kept in
/// "dd_total_playtime" (milliseconds, like the web version) and shown in the
/// pause menu.
public enum Playtime {
    static let key = "dd_total_playtime"

    public static func stored(_ store: GameStore) -> Double { Double(store.getItem(key) ?? "") ?? 0 }

    /// Adds a stretch of play (seconds).
    public static func add(_ seconds: Double, store: GameStore) {
        guard seconds > 0, seconds < 24 * 3600 else { return }
        store.setItem(key, String(Int(stored(store) + seconds * 1000)))
    }

    /// formatPlaytime: "3h 12m 5s", "12m 5s", "5s".
    public static func format(ms: Double) -> String {
        let total = Int(ms / 1000)
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    /// Read aloud: "3 hours 12 minutes".
    public static func spoken(ms: Double) -> String {
        let total = Int(ms / 1000)
        let h = total / 3600, m = total % 3600 / 60
        if h > 0 { return "\(h) hour\(h == 1 ? "" : "s") \(m) minute\(m == 1 ? "" : "s")" }
        if m > 0 { return "\(m) minute\(m == 1 ? "" : "s")" }
        return "less than a minute"
    }
}
