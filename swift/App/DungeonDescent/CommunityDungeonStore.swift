import SwiftUI
import FirebaseDatabase
import DungeonCore

/// 12.1: community dungeons online, in the shared database the co-op rooms
/// use ("pvp_rooms/cdun_<id>", kind "cdungeon"), so every version can read
/// them. Plays, clears and likes are counted with transactions.
@MainActor
final class CommunityDungeonStore: ObservableObject {
    static let shared = CommunityDungeonStore()
    static let kind = "cdungeon"

    @Published private(set) var all: [CommunityDungeons.Dungeon] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false

    private var root: DatabaseReference { Database.database().reference(withPath: "pvp_rooms") }
    private func ref(_ id: String) -> DatabaseReference { root.child(id) }
    private static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    // MARK: Reading

    func load() {
        loading = true
        root.queryOrdered(byChild: "kind").queryEqual(toValue: Self.kind).observeSingleEvent(of: .value, with: { [weak self] snap in
            var list: [CommunityDungeons.Dungeon] = []
            for case let child as DataSnapshot in snap.children {
                if let v = child.value as? [String: Any], let d = Self.decode(child.key, v) { list.append(d) }
            }
            Task { @MainActor in
                guard let self else { return }
                self.all = list.filter(\.approved).sorted { ($0.plays + 3 * $0.likes, $0.createdAt) > ($1.plays + 3 * $1.likes, $1.createdAt) }
                self.loading = false
                self.failed = false
            }
        }, withCancel: { [weak self] _ in
            Task { @MainActor in self?.loading = false; self?.failed = true }
        })
    }

    /// Dungeons from blocked creators are left out.
    func visible(_ store: GameStore) -> [CommunityDungeons.Dungeon] {
        let chat = GlobalChat(store: store)
        let hidden = Set(UserDefaults.standard.stringArray(forKey: "swift_hidden_dungeons") ?? [])
        return all.filter { !chat.isBlocked($0.creator) && !hidden.contains($0.id) }
    }

    nonisolated static func decode(_ id: String, _ v: [String: Any]) -> CommunityDungeons.Dungeon? {
        guard v["kind"] as? String == kind, let name = v["name"] as? String, let base = v["base"] as? String else { return nil }
        func n(_ k: String) -> Int { (v[k] as? NSNumber)?.intValue ?? 0 }
        var d = CommunityDungeons.Dungeon(id: id, name: name, desc: v["desc"] as? String ?? "", creator: v["creator"] as? String ?? "Unknown",
                                          base: base, enemies: (v["enemies"] as? [String]) ?? [], boss: v["boss"] as? String,
                                          rule: v["rule"] as? String, music: v["music"] as? String)
        d.likes = n("likes"); d.plays = n("plays"); d.clears = n("clears")
        d.createdAt = (v["createdAt"] as? NSNumber)?.doubleValue ?? 0
        d.approved = v["approved"] as? Bool ?? true
        return d
    }

    // MARK: Writing

    /// Publishes a dungeon; calls back with an error message, or nil.
    func submit(_ d: CommunityDungeons.Dungeon, done: @escaping @MainActor (String?) -> Void) {
        let id = "cdun_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))
        var data: [String: Any] = ["kind": Self.kind, "name": d.name, "desc": d.desc, "creator": d.creator, "base": d.base,
                                   "enemies": d.enemies, "likes": 0, "plays": 0, "clears": 0, "createdAt": Self.now, "approved": true]
        if let b = d.boss { data["boss"] = b }
        if let r = d.rule { data["rule"] = r }
        if let m = d.music { data["music"] = m }
        ref(id).setValue(data) { [weak self] error, _ in
            Task { @MainActor in
                if error == nil {
                    var mine = UserDefaults.standard.stringArray(forKey: "swift_my_dungeons") ?? []
                    mine.append(id)
                    UserDefaults.standard.set(mine, forKey: "swift_my_dungeons")
                    self?.load()
                }
                done(error == nil ? nil : "Couldn't publish it. Check your connection and try again.")
            }
        }
    }

    private func bump(_ id: String, _ key: String) {
        ref(id).child(key).runTransactionBlock { data in
            data.value = ((data.value as? NSNumber)?.intValue ?? 0) + 1
            return .success(withValue: data)
        }
    }

    func played(_ id: String) { bump(id, "plays") }
    func cleared(_ id: String) { bump(id, "clears") }

    func isLiked(_ id: String) -> Bool { (UserDefaults.standard.stringArray(forKey: "swift_liked_dungeons") ?? []).contains(id) }

    /// One like per dungeon on this device.
    func like(_ d: CommunityDungeons.Dungeon) {
        guard !isLiked(d.id) else { Feedback.announce("You already liked \(d.name)."); return }
        UserDefaults.standard.set((UserDefaults.standard.stringArray(forKey: "swift_liked_dungeons") ?? []) + [d.id], forKey: "swift_liked_dungeons")
        bump(d.id, "likes")
        if let i = all.firstIndex(where: { $0.id == d.id }) { all[i].likes += 1 }
        Sound.sfx("sfx-confirm")
        Feedback.announce("You liked \(d.name).")
    }

    func isMine(_ id: String) -> Bool { (UserDefaults.standard.stringArray(forKey: "swift_my_dungeons") ?? []).contains(id) }

    /// Hidden here at once, and sent to the developer.
    func report(_ d: CommunityDungeons.Dungeon) async {
        UserDefaults.standard.set((UserDefaults.standard.stringArray(forKey: "swift_hidden_dungeons") ?? []) + [d.id], forKey: "swift_hidden_dungeons")
        objectWillChange.send()
        await GlobalChat.sendReport(kind: "dungeon", id: d.id, author: d.creator, content: "\(d.name): \(d.desc)",
                                    reason: "", reporter: nil)
    }

    /// Developer Tools: remove or restore a dungeon for everyone.
    func moderate(_ id: String, approved: Bool) async -> String {
        let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.hasPrefix("cdun_") else { return "That isn't a dungeon ID." }
        do {
            try await ref(clean).updateChildValues(["approved": approved, "moderatedAt": Self.now])
            load()
            return approved ? "The dungeon is back for everyone." : "The dungeon is removed for everyone."
        } catch {
            return "Couldn't change it: \(error.localizedDescription)"
        }
    }
}
