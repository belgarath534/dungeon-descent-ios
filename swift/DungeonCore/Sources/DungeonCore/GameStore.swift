import Foundation

/// String key/value storage, the same shape as the web version's DDStore.
/// Keys and value formats match the web game exactly ("dd_global_gold" holds
/// "250", "dd_chars" holds a JSON array), so saves, iCloud backups and
/// character export codes move between the two versions unchanged.
public protocol GameStore: AnyObject {
    func getItem(_ key: String) -> String?
    func setItem(_ key: String, _ value: String)
    func removeItem(_ key: String)
}

/// Storage keys used by the web version, collected in one place.
public enum StoreKey {
    public static let chars = "dd_chars"
    public static let globalGold = "dd_global_gold"
    public static let totalGoldEver = "dd_total_gold_ever"
    public static let totalGoldSpent = "dd_total_gold_spent"
    public static let diamonds = "dd_diamonds"
    public static let unlocks = "dd_unlocks"
    public static let equippedWeapon = "dd_equipped_weapon"
    public static let equippedArmor = "dd_equipped_armor"
}

/// Keeps everything in memory. Used by tests and previews.
public final class MemoryStore: GameStore {
    private var values: [String: String]
    public init(_ values: [String: String] = [:]) { self.values = values }
    public func getItem(_ key: String) -> String? { values[key] }
    public func setItem(_ key: String, _ value: String) { values[key] = value }
    public func removeItem(_ key: String) { values[key] = nil }
}

/// Saves everything to one JSON file on disk.
public final class FileStore: GameStore {
    private let url: URL
    private var values: [String: String]
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            values = decoded
        } else {
            values = [:]
        }
    }

    public func getItem(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    public func setItem(_ key: String, _ value: String) {
        lock.lock(); values[key] = value; lock.unlock()
        flush()
    }

    public func removeItem(_ key: String) {
        lock.lock(); values[key] = nil; lock.unlock()
        flush()
    }

    private func flush() {
        lock.lock(); let snapshot = values; lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
