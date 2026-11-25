import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import DungeonCore

/// 12.2 Guilds online: the "guilds" collection in the same Firestore database
/// as accounts and community enemies (firebase/firestore.rules says who may
/// change what). A guild is one document: its name, description, leader,
/// members (account → name, up to 20) and this week's Guild Boss damage, for
/// the rankings. Its chat and each member's boss damage are under it.
/// Guilds need an account, so the rules know who's who.
@MainActor
final class GuildStore: ObservableObject {
    static let shared = GuildStore()

    struct Guild: Identifiable, Equatable {
        let id: String
        var name: String
        var desc: String
        var leader: String
        var leaderName: String
        /// Account → name.
        var members: [String: String]
        var week: String
        var weekDamage: Int

        /// This week's damage, for the rankings (0 when it's from an older week).
        var thisWeek: Int { week == Guilds.week().key ? weekDamage : 0 }
        /// Members by name, the leader first.
        var roster: [(uid: String, name: String)] {
            members.map { ($0.key, $0.value) }.sorted {
                $0.uid == leader ? true : $1.uid == leader ? false
                    : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    struct Message: Identifiable, Equatable {
        let id: String
        let uid: String
        let username: String
        let message: String
        let timestamp: Double
    }

    struct Hit: Identifiable, Equatable {
        var id: String { uid }
        let uid: String
        let name: String
        let damage: Int
    }

    @Published private(set) var mine: Guild?
    /// Looked for your guild at least once.
    @Published private(set) var checked = false
    @Published private(set) var all: [Guild] = []
    @Published private(set) var chat: [Message] = []
    @Published private(set) var hits: [Hit] = []
    /// Everyone's damage this week; nil while loading or offline.
    @Published private(set) var bossTotal: Int?

    private var db: Firestore { Firestore.firestore(database: "dungeon-descent") }
    private var col: CollectionReference { db.collection("guilds") }
    private var names: CollectionReference { db.collection("guildNames") }
    private var chatListener: ListenerRegistration?
    private var seen: Set<String> = []
    private var firstChat = true

    var uid: String? { Auth.auth().currentUser?.uid }
    var signedIn: Bool { uid != nil }
    var isLeader: Bool { mine != nil && mine?.leader == uid }
    static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    /// The name members see: your chat username, else your account's, else "Adventurer".
    func myName(_ store: GameStore) -> String {
        let n = [store.getItem("dd_chat_username"), store.getItem("dd_username")].compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "Adventurer"
        return String(n.prefix(20))
    }

    private static func guild(_ id: String, _ v: [String: Any]) -> Guild? {
        guard let name = v["name"] as? String, let leader = v["leader"] as? String else { return nil }
        return Guild(id: id, name: name, desc: v["desc"] as? String ?? "", leader: leader,
                     leaderName: v["leaderName"] as? String ?? "", members: v["members"] as? [String: String] ?? [:],
                     week: v["week"] as? String ?? "", weekDamage: (v["weekDamage"] as? NSNumber)?.intValue ?? 0)
    }

    // MARK: Finding guilds

    /// Your guild (found by your account, so it's the same on every device).
    func loadMine() async {
        defer { checked = true }
        guard let uid else { mine = nil; return }
        guard let snap = try? await col.whereField(FieldPath(["members", uid]), isGreaterThan: "").limit(to: 1).getDocuments()
        else { return }
        mine = snap.documents.first.flatMap { Self.guild($0.documentID, $0.data()) }
    }

    /// Every guild, the strongest this week first.
    func loadAll() async -> Bool {
        guard let snap = try? await col.limit(to: 300).getDocuments() else { return false }
        all = snap.documents.compactMap { Self.guild($0.documentID, $0.data()) }.sorted {
            $0.thisWeek != $1.thisWeek ? $0.thisWeek > $1.thisWeek
                : $0.members.count != $1.members.count ? $0.members.count > $1.members.count
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return true
    }

    // MARK: Joining, leaving, leading

    /// Makes a guild with you as its leader. Returns a problem to read, or nil.
    func create(name raw: String, desc rawDesc: String, store: GameStore) async -> String? {
        guard let uid else { return "Sign in first (Settings, Account). Guilds need an account." }
        let name = raw.trimmingCharacters(in: .whitespaces)
        let desc = rawDesc.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = Guilds.nameProblem(name) ?? Guilds.descProblem(desc) { return p }
        await loadMine()
        if mine != nil { return "You're already in a guild. Leave it first." }
        let key = Guilds.key(name)
        if (try? await names.document(key).getDocument())?.exists == true { return "A guild called \(name) already exists. Choose another name." }
        let ref = col.document()
        let me = myName(store)
        let batch = db.batch()
        batch.setData(["gid": ref.documentID, "uid": uid], forDocument: names.document(key))
        batch.setData(["name": name, "nameKey": key, "desc": desc, "leader": uid, "leaderName": me,
                       "members": [uid: me], "createdAt": Self.now, "week": Guilds.week().key, "weekDamage": 0],
                      forDocument: ref)
        do {
            try await batch.commit()
        } catch {
            return "Couldn't create the guild. The name may have just been taken, or you're offline. Try again."
        }
        mine = Guild(id: ref.documentID, name: name, desc: desc, leader: uid, leaderName: me, members: [uid: me],
                     week: Guilds.week().key, weekDamage: 0)
        return nil
    }

    func join(_ g: Guild, store: GameStore) async -> String? {
        guard let uid else { return "Sign in first (Settings, Account). Guilds need an account." }
        await loadMine()
        if mine != nil { return "You're already in a guild. Leave it first." }
        if g.members.count >= Guilds.maxMembers { return "\(g.name) is full: \(Guilds.maxMembers) members." }
        do {
            try await col.document(g.id).updateData([FieldPath(["members", uid]): myName(store)])
        } catch {
            return "Couldn't join \(g.name). It may have just filled up, or you're offline."
        }
        await loadMine()
        return nil
    }

    /// Leaving. A leader hands the guild to someone first, or, alone, disbands it.
    func leave() async -> String? {
        guard let uid, let g = mine else { return nil }
        if g.leader == uid {
            if g.members.count > 1 { return "You lead \(g.name). Make another member the leader first, or disband the guild." }
            return await disband()
        }
        do {
            try await col.document(g.id).updateData([FieldPath(["members", uid]): FieldValue.delete()])
        } catch { return "Couldn't leave the guild. Check your connection." }
        closeChat()
        mine = nil
        return nil
    }

    func remove(_ member: String) async -> String? {
        guard isLeader, let g = mine, member != uid else { return nil }
        do {
            try await col.document(g.id).updateData([FieldPath(["members", member]): FieldValue.delete()])
        } catch { return "Couldn't remove them. Check your connection." }
        mine?.members[member] = nil
        return nil
    }

    func makeLeader(_ member: String) async -> String? {
        guard isLeader, let g = mine, let name = g.members[member] else { return nil }
        do {
            try await col.document(g.id).updateData(["leader": member, "leaderName": name])
        } catch { return "Couldn't change the leader. Check your connection." }
        mine?.leader = member
        mine?.leaderName = name
        return nil
    }

    func setDesc(_ raw: String) async -> String? {
        guard isLeader, let g = mine else { return nil }
        let desc = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = Guilds.descProblem(desc) { return p }
        do { try await col.document(g.id).updateData(["desc": desc]) } catch { return "Couldn't save it. Check your connection." }
        mine?.desc = desc
        return nil
    }

    /// The leader ends the guild (the developer can end any, for moderation).
    func disband(_ target: Guild? = nil) async -> String? {
        guard let g = target ?? mine else { return nil }
        let batch = db.batch()
        batch.deleteDocument(names.document(Guilds.key(g.name)))
        batch.deleteDocument(col.document(g.id))
        do { try await batch.commit() } catch { return "Couldn't disband the guild. Check your connection." }
        if g.id == mine?.id { closeChat(); mine = nil }
        all.removeAll { $0.id == g.id }
        return nil
    }

    // MARK: Guild chat

    func openChat(store: GameStore) {
        guard chatListener == nil, let g = mine else { return }
        firstChat = true
        let blocks = GlobalChat(store: store)
        chatListener = col.document(g.id).collection("chat").order(by: "timestamp").limit(toLast: 60)
            .addSnapshotListener { [weak self] snap, _ in
                guard let docs = snap?.documents else { return }
                let list = docs.map { d -> Message in
                    let v = d.data()
                    return Message(id: d.documentID, uid: v["uid"] as? String ?? "", username: v["username"] as? String ?? "Unknown",
                                   message: v["message"] as? String ?? "", timestamp: (v["timestamp"] as? NSNumber)?.doubleValue ?? 0)
                }
                Task { @MainActor in self?.received(list, blocks: blocks) }
            }
    }

    func closeChat() {
        chatListener?.remove()
        chatListener = nil
        chat = []
        seen = []
    }

    private func received(_ list: [Message], blocks: GlobalChat) {
        let me = uid
        let shown = list.filter { !blocks.isBlocked($0.username) }
        if !firstChat {
            for m in shown where !seen.contains(m.id) && m.uid != me {
                Feedback.announce("Guild. \(m.username) said \(m.message)")
            }
        }
        firstChat = false
        seen.formUnion(list.map(\.id))
        chat = shown
    }

    func send(_ raw: String, store: GameStore) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, let g = mine else { return "Join a guild first." }
        if text.isEmpty { return "Please type a message first." }
        if text.count > 200 { return "Message too long. Maximum 200 characters." }
        if CommunityEnemies.hasBadWord(text) { return "Your message contains inappropriate content and was not sent." }
        col.document(g.id).collection("chat").addDocument(data: [
            "uid": uid, "username": myName(store), "message": text, "timestamp": Self.now,
        ]) { error in
            if error != nil { Task { @MainActor in Feedback.announce("Failed to send message. Check your connection.") } }
        }
        return nil
    }

    /// Your own message, or any message for the leader.
    func canDelete(_ m: Message) -> Bool { m.uid == uid || isLeader }

    func delete(_ m: Message) async {
        guard let g = mine else { return }
        try? await col.document(g.id).collection("chat").document(m.id).delete()
    }

    // MARK: The Guild Boss

    private func hitsRef(_ g: Guild, _ week: String) -> CollectionReference {
        col.document(g.id).collection("boss").document(week).collection("hits")
    }

    /// The guild's damage this week (and everyone's share).
    func loadBoss(week: Guilds.Week) async {
        guard let g = mine else { bossTotal = nil; return }
        guard let snap = try? await hitsRef(g, week.key).getDocuments() else { bossTotal = nil; return }
        hits = snap.documents.map {
            Hit(uid: $0.documentID, name: $0.data()["name"] as? String ?? "Unknown",
                damage: ($0.data()["damage"] as? NSNumber)?.intValue ?? 0)
        }.sorted { $0.damage > $1.damage }
        bossTotal = hits.reduce(0) { $0 + $1.damage }
    }

    /// Another week's total (for last week's reward).
    func total(week: Guilds.Week) async -> Int? {
        guard let g = mine, let snap = try? await hitsRef(g, week.key).getDocuments() else { return nil }
        return snap.documents.reduce(0) { $0 + (($1.data()["damage"] as? NSNumber)?.intValue ?? 0) }
    }

    /// Sends one strike's damage: your share, and the guild's total for the rankings.
    func record(_ damage: Int, week: Guilds.Week, store: GameStore) async {
        guard let uid, let g = mine else { return }
        try? await hitsRef(g, week.key).document(uid).setData([
            "damage": FieldValue.increment(Int64(damage)), "name": myName(store), "updatedAt": Self.now,
        ], merge: true)
        let ref = col.document(g.id)
        if let cur = try? await ref.getDocument().data(), cur["week"] as? String == week.key {
            try? await ref.updateData(["weekDamage": FieldValue.increment(Int64(damage))])
        } else {
            try? await ref.updateData(["week": week.key, "weekDamage": damage])
        }
        bossTotal = (bossTotal ?? 0) + damage
    }

    // MARK: Reports

    func report(guild g: Guild, reason: String, reporter: String?) async {
        await GlobalChat.sendReport(kind: "guild", id: g.id, author: g.leaderName,
                                    content: "\(g.name): \(g.desc)", reason: reason, reporter: reporter)
    }

    func report(_ m: Message, reason: String, reporter: String?) async {
        chat.removeAll { $0.id == m.id }
        await GlobalChat.sendReport(kind: "guild message", id: m.id, author: m.username,
                                    content: String(m.message.prefix(300)), reason: reason, reporter: reporter)
    }
}
