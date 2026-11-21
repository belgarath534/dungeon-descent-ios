import Foundation

/// CLOUD SYNC (12.0): the whole save, not only the 12 keys the old cloud save
/// carried, in the same "saves/{uid}" document the web version uses.
///
/// The document gets three more fields next to the old ones:
///   full     every dd_ key except the device-only ones, as one JSON string
///   savedAt  when it was written (milliseconds)
///   savedBy  which kind of device wrote it ("ios", "mac", "vision", "web")
///
/// Each device remembers the savedAt it last matched ("dd_sync_last") and when
/// its own save last changed ("dd_sync_dirty_at", kept by FileStore), so it
/// can tell a newer save from another device apart from its own progress.
/// The web version (js/28-cloud-sync.js) follows the same rules.
public enum CloudSync {
    public static let lastKey = "dd_sync_last"
    public static let dirtyKey = "dd_sync_dirty_at"

    /// Settings of this device only, never sent or replaced.
    public static let deviceOnly: Set<String> = [
        "dd_presence_id", "dd_dev_mode", "dd_lang", "dd_notif_prefs", "dd_icloud_backup_enabled",
        "dd_last_seen", "dd_version_seen", "dd_shake", "dd_music_loop",
    ]

    /// Saved by just having the game open, not by playing: they travel with
    /// the save but don't count as progress. (Total playtime is written every
    /// time the app closes, so every device looked changed and the game kept
    /// asking which save to keep.)
    public static let passive: Set<String> = ["dd_total_playtime"]

    /// Whether a key travels with the save.
    public static func synced(_ key: String) -> Bool {
        key.hasPrefix("dd_") && !key.hasPrefix("dd_sync_") && !deviceOnly.contains(key)
    }

    /// Whether changing a key is progress (this device has something the cloud doesn't).
    public static func progress(_ key: String) -> Bool { synced(key) && !passive.contains(key) }

    /// The part of a save that goes to the cloud.
    public static func full(_ snapshot: [String: String]) -> [String: String] {
        snapshot.filter { synced($0.key) }
    }

    /// Firestore's limit is 1 MiB a document; past this the full save isn't
    /// sent (the old 12 keys still are) rather than the whole sync failing.
    public static let maxBytes = 900_000

    public static func encode(_ full: [String: String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: full, options: [.sortedKeys]),
              data.count <= maxBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode(_ s: String?) -> [String: String]? {
        guard let s, let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out: [String: String] = [:]
        for (k, v) in obj where synced(k) {
            if let str = v as? String { out[k] = str }
        }
        return out
    }

    public enum Decision: Equatable, Sendable {
        /// The cloud has a newer save and nothing changed here: load it.
        case pull
        /// This device has progress the cloud doesn't: send it.
        case push
        /// Both changed since they last matched: the player chooses.
        case ask
        /// Already the same.
        case nothing
    }

    /// cloudSavedAt: the cloud's savedAt (0 when there's no full save yet);
    /// lastSync: the savedAt this device last matched (0 if never);
    /// dirtyAt: when this device's save last changed (0 if never).
    public static func decide(cloudSavedAt: Double, lastSync: Double, dirtyAt: Double) -> Decision {
        let cloudNewer = cloudSavedAt > lastSync
        let localChanged = dirtyAt > lastSync
        switch (cloudNewer, localChanged) {
        case (true, false): return .pull
        case (true, true): return .ask
        case (false, true): return .push
        case (false, false): return .nothing
        }
    }

    public static func number(_ s: String?) -> Double { Double(s ?? "") ?? 0 }
}
