import Foundation

/// String key/value storage, the same shape as the web version's DDStore.
/// Keys and value formats match the web game exactly ("dd_global_gold" holds
/// "250", "dd_chars" holds a JSON array), so saves, iCloud backups and
/// character export codes move between the two versions unchanged.
public protocol GameStore: AnyObject {
    func getItem(_ key: String) -> String?
    func setItem(_ key: String, _ value: String)
    func removeItem(_ key: String)
    /// Writes many keys at once (one save to disk instead of one per key).
    func setItems(_ items: [String: String])
}

extension GameStore {
    public func setItems(_ items: [String: String]) {
        for (k, v) in items { setItem(k, v) }
    }
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

/// Saves everything to one JSON file on disk. Writes are batched like the web
/// version's DDStore: a burst of changes becomes one write about 0.4s later.
/// Call `flushNow()` when the app goes to the background.
public final class FileStore: GameStore {
    private let url: URL
    private var values: [String: String]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "dd.filestore")
    private var dirty = false
    private var scheduled = false
    private let delay: TimeInterval

    public init(url: URL, delay: TimeInterval = 0.4) {
        self.url = url
        self.delay = delay
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
        scheduleWrite()
    }

    public func removeItem(_ key: String) {
        lock.lock(); values[key] = nil; lock.unlock()
        scheduleWrite()
    }

    public func setItems(_ items: [String: String]) {
        lock.lock(); values.merge(items) { _, new in new }; lock.unlock()
        scheduleWrite()
    }

    /// Every key and value, for a full backup.
    public func snapshot() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return values
    }

    /// Writes any pending changes immediately.
    public func flushNow() {
        queue.sync { write() }
    }

    private func scheduleWrite() {
        lock.lock()
        dirty = true
        let start = !scheduled
        scheduled = true
        lock.unlock()
        guard start else { return }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.write() }
    }

    /// Runs on `queue`.
    private func write() {
        lock.lock()
        scheduled = false
        guard dirty else { lock.unlock(); return }
        dirty = false
        let snapshot = values
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
