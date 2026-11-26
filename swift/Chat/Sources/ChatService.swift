import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let uid: String
    let username: String
    let text: String
    let date: Date
    let replyTo: String?
}

struct Channel: Identifiable, Equatable {
    let id: String
    let name: String
    let topic: String
    let order: Int
    let modsPost: Bool
    let testersOnly: Bool
}

struct Member: Equatable {
    let uid: String
    let username: String
    let createdAt: Date
    let agreed: Bool
    let mod: Bool
    let tester: Bool
    let trusted: Bool
    let dmOff: Bool
}

/// A place to talk: a channel, a private conversation or a group chat.
struct Room: Identifiable, Hashable {
    enum Kind: String { case channel, dm, group }
    let kind: Kind
    let id: String
    var title: String
    /// Firestore path of the room's document (messages live under it).
    var path: String
    var members: [String: String] = [:]
    var owner: String? = nil
    var lastAt: Date? = nil
    var canPost = true
}

/// Everything the app reads and writes in Firestore. The rules
/// (firebase/firestore.rules, "Dungeon Descent Chat") enforce what's allowed;
/// this just asks for it and explains refusals in plain words.
@MainActor
final class ChatService: ObservableObject {
    @Published private(set) var member: Member?
    @Published private(set) var memberLoaded = false
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var dms: [Room] = []
    @Published private(set) var groups: [Room] = []
    @Published private(set) var blocked: [String: String] = [:]
    @Published private(set) var banned = false
    @Published private(set) var isDeveloper = false
    @Published var gameUsername: String?

    static let developerUID = "WgqZGmnPKeYIymlMkx0aAg8G2T52"
    private var db: Firestore { Account.db }
    private var uid: String?
    private var listeners: [ListenerRegistration] = []

    var isMod: Bool { isDeveloper || member?.mod == true }
    var isTester: Bool { isMod || member?.tester == true }

    // MARK: Starting and stopping

    func start(uid: String?) {
        guard uid != self.uid else { return }
        stop()
        self.uid = uid
        guard let uid else { return }
        isDeveloper = uid == Self.developerUID
        memberLoaded = false
        listeners.append(db.collection("chat_members").document(uid).addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in
                self?.member = snap.flatMap { Self.member($0) }
                self?.memberLoaded = true
            }
        })
        listeners.append(db.collection("chat_bans").document(uid).addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in self?.banned = snap?.exists == true }
        })
        listeners.append(db.collection("chat_channels").addSnapshotListener { [weak self] snap, _ in
            let list = (snap?.documents ?? []).map { d in
                Channel(id: d.documentID, name: d["name"] as? String ?? d.documentID, topic: d["topic"] as? String ?? "",
                        order: d["order"] as? Int ?? 99, modsPost: d["modsPost"] as? Bool ?? false,
                        testersOnly: d["testersOnly"] as? Bool ?? false)
            }.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
            Task { @MainActor in self?.channels = list }
        })
        listeners.append(db.collection("chat_dms").whereField("members", arrayContains: uid).addSnapshotListener { [weak self] snap, _ in
            let rooms = (snap?.documents ?? []).compactMap { d -> Room? in
                guard let members = d["members"] as? [String], let other = members.first(where: { $0 != uid }) else { return nil }
                let names = d["names"] as? [String: String] ?? [:]
                return Room(kind: .dm, id: d.documentID, title: names[other] ?? "Player", path: "chat_dms/\(d.documentID)",
                            members: names, lastAt: (d["lastAt"] as? Timestamp)?.dateValue())
            }.sorted { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) }
            Task { @MainActor in self?.dms = rooms }
        })
        listeners.append(db.collection("chat_groups").whereField(FieldPath(["members", uid]), isGreaterThan: "").addSnapshotListener { [weak self] snap, _ in
            let rooms = (snap?.documents ?? []).map { d in
                Room(kind: .group, id: d.documentID, title: d["name"] as? String ?? "Group", path: "chat_groups/\(d.documentID)",
                     members: d["members"] as? [String: String] ?? [:], owner: d["owner"] as? String,
                     lastAt: (d["lastAt"] as? Timestamp)?.dateValue())
            }.sorted { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) }
            Task { @MainActor in self?.groups = rooms }
        })
        listeners.append(db.collection("chat_members").document(uid).collection("blocks").addSnapshotListener { [weak self] snap, _ in
            let map = Dictionary((snap?.documents ?? []).map { ($0.documentID, $0["name"] as? String ?? "Player") }, uniquingKeysWith: { a, _ in a })
            Task { @MainActor in self?.blocked = map }
        })
        Task {
            let profile = try? await db.collection("users").document(uid).getDocument().data()
            gameUsername = profile?["username"] as? String
        }
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        member = nil; channels = []; dms = []; groups = []; blocked = [:]; banned = false
        uid = nil
    }

    nonisolated static func member(_ d: DocumentSnapshot) -> Member? {
        guard d.exists, let name = d["username"] as? String else { return nil }
        return Member(uid: d.documentID, username: name,
                      createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                      agreed: d["agreedAt"] is Timestamp, mod: d["mod"] as? Bool ?? false,
                      tester: d["tester"] as? Bool ?? false, trusted: d["trusted"] as? Bool ?? false,
                      dmOff: d["dmOff"] as? Bool ?? false)
    }

    // MARK: Joining

    /// The username rules, the same as the game's (3 to 20 letters, numbers or underscores).
    nonisolated static func usernameProblem(_ n: String) -> String? {
        if n.count < 3 { return "A username needs at least 3 characters." }
        if n.count > 20 { return "A username can have at most 20 characters." }
        if !n.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) {
            return "A username can only have letters, numbers and underscores."
        }
        let low = n.lowercased()
        if ["admin", "moderator", "developer", "dungeondescent", "official", "staff", "support"].contains(where: low.contains)
            || ["dev", "mod", "leonardo"].contains(low) {
            return "That name is kept for the Dungeon Descent team. Pick another."
        }
        return nil
    }

    /// Makes your chat profile with your game username, or claims a new one
    /// in the same step (it then becomes your username in the game too).
    func join(username raw: String) async -> String? {
        guard let uid else { return "You're not signed in." }
        let name = raw.trimmingCharacters(in: .whitespaces)
        if let p = Self.usernameProblem(name), !(isDeveloper && name.lowercased() == "leonardo") { return p }
        let nameRef = db.collection("usernames").document(name.lowercased())
        if let snap = try? await nameRef.getDocument(), snap.exists, let owner = snap["uid"] as? String, owner != uid {
            return "Someone already has that username. Try another."
        }
        let batch = db.batch()
        batch.setData(["uid": uid, "username": name], forDocument: nameRef)
        batch.setData(["username": name, "createdAt": FieldValue.serverTimestamp(),
                       "lastPostAt": FieldValue.serverTimestamp(), "dmOff": false],
                      forDocument: db.collection("chat_members").document(uid))
        do {
            try await batch.commit()
            try? await db.collection("users").document(uid).setData(["username": name], merge: true)
            return nil
        } catch {
            return "Couldn't save that username. Check your connection and try again."
        }
    }

    func agreeToRules() async {
        guard let uid else { return }
        try? await db.collection("chat_members").document(uid).updateData(["agreedAt": FieldValue.serverTimestamp()])
    }

    func setDMsOff(_ off: Bool) async {
        guard let uid else { return }
        try? await db.collection("chat_members").document(uid).updateData(["dmOff": off])
    }

    // MARK: Messages

    func listen(_ room: Room, limit: Int = 100, onChange: @escaping @MainActor ([ChatMessage]) -> Void) -> ListenerRegistration {
        db.collection(room.path + "/messages").order(by: "ts", descending: true).limit(to: limit)
            .addSnapshotListener { snap, _ in
                let list = (snap?.documents ?? []).map { d in
                    ChatMessage(id: d.documentID, uid: d["uid"] as? String ?? "", username: d["username"] as? String ?? "Player",
                                text: d["text"] as? String ?? "", date: (d["ts"] as? Timestamp)?.dateValue() ?? Date(),
                                replyTo: d["replyTo"] as? String)
                }.reversed()
                Task { @MainActor in onChange(Array(list)) }
            }
    }

    /// The same whole-word filter as the rules, so you hear why before sending.
    nonisolated static let badWords = try! NSRegularExpression(pattern:
        #"\b(fuck\w*|motherfuck\w*|shit|shits|shitty|shitting|bullshit|bitch\w*|cunt\w*|nigg\w*|fag|fags|faggot\w*|retard\w*|whore\w*|slut\w*|dick|dicks|cock|cocks|pussy|pussies|ass|asshole\w*|bastard\w*|piss|pissed|pissing)\b"#,
        options: [.caseInsensitive])
    nonisolated static func hasBadWord(_ t: String) -> Bool {
        badWords.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    private var lastSent = Date.distantPast

    /// Sends a message; returns why not, in plain words, when it can't.
    func send(_ raw: String, in room: Room, replyTo: String? = nil) async -> String? {
        guard let uid, let me = member else { return "You're not signed in." }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "Type a message first." }
        if text.count > 1000 { return "That's too long. Messages can have up to 1000 characters." }
        if Self.hasBadWord(text) { return "That message has a word that isn't allowed here. Change it and try again." }
        if banned { return "You've been banned from chat, so you can't send messages." }
        let wait = 2.1 - Date().timeIntervalSince(lastSent)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        let batch = db.batch()
        var data: [String: Any] = ["uid": uid, "username": me.username, "text": text, "ts": FieldValue.serverTimestamp()]
        if let replyTo { data["replyTo"] = replyTo }
        batch.setData(data, forDocument: db.collection(room.path + "/messages").document())
        batch.updateData(["lastPostAt": FieldValue.serverTimestamp()], forDocument: db.collection("chat_members").document(uid))
        do {
            try await batch.commit()
            lastSent = Date()
            if room.kind != .channel {
                try? await db.document(room.path).updateData(["lastAt": FieldValue.serverTimestamp()])
            }
            await Push.notify(room: room, text: text, from: me.username)
            return nil
        } catch {
            if room.kind == .channel, channels.first(where: { $0.id == room.id })?.modsPost == true {
                return "Only moderators can post in this channel."
            }
            if room.kind == .dm { return "Couldn't send. This player may have turned private messages off or blocked you." }
            return "Couldn't send. Check your connection and try again."
        }
    }

    func delete(_ m: ChatMessage, in room: Room) async -> Bool {
        (try? await db.collection(room.path + "/messages").document(m.id).delete()) != nil
    }

    // MARK: Private messages and groups

    nonisolated static func pairID(_ a: String, _ b: String) -> String { [a, b].sorted().joined(separator: "_") }

    /// Opens (or starts) a private conversation with another player.
    func openDM(with other: String, name: String) async -> (Room?, String?) {
        guard let uid, let me = member else { return (nil, "You're not signed in.") }
        if other == uid { return (nil, "That's you.") }
        let pid = Self.pairID(uid, other)
        let path = "chat_dms/\(pid)"
        let room = Room(kind: .dm, id: pid, title: name, path: path, members: [uid: me.username, other: name])
        if let snap = try? await db.document(path).getDocument(), snap.exists { return (room, nil) }
        do {
            try await db.document(path).setData(["members": [uid, other].sorted(), "names": [uid: me.username, other: name],
                                                  "lastAt": FieldValue.serverTimestamp()])
            return (room, nil)
        } catch {
            if !(member?.trusted ?? false), !isMod, Date().timeIntervalSince(me.createdAt) < 86400 {
                return (nil, "New accounts can start private conversations after one day. You can still answer anyone who messages you.")
            }
            return (nil, "\(name) isn't taking private messages right now.")
        }
    }

    func createGroup(name: String) async -> (Room?, String?) {
        guard let uid, let me = member else { return (nil, "You're not signed in.") }
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty || n.count > 40 { return (nil, "A group name needs 1 to 40 characters.") }
        if Self.hasBadWord(n) { return (nil, "That group name has a word that isn't allowed.") }
        let ref = db.collection("chat_groups").document()
        do {
            try await ref.setData(["name": n, "owner": uid, "members": [uid: me.username],
                                   "createdAt": FieldValue.serverTimestamp(), "lastAt": FieldValue.serverTimestamp()])
            return (Room(kind: .group, id: ref.documentID, title: n, path: "chat_groups/\(ref.documentID)",
                         members: [uid: me.username], owner: uid), nil)
        } catch {
            if !(member?.trusted ?? false), !isMod, Date().timeIntervalSince(me.createdAt) < 86400 {
                return (nil, "New accounts can make groups after one day.")
            }
            return (nil, "Couldn't make the group. Check your connection.")
        }
    }

    func addToGroup(_ room: Room, username: String) async -> String? {
        guard let found = await findMember(username: username) else { return "No chat member is called \(username)." }
        if room.members.count >= 20 { return "Groups can have up to 20 people." }
        do {
            try await db.document(room.path).updateData([FieldPath(["members", found.uid]): found.username, "added": found.uid])
            return nil
        } catch {
            return "\(found.username) can't be added. They may have private messages off."
        }
    }

    func removeFromGroup(_ room: Room, uid other: String) async -> Bool {
        (try? await db.document(room.path).updateData([FieldPath(["members", other]): FieldValue.delete()])) != nil
    }

    func leaveGroup(_ room: Room) async -> String? {
        guard let uid else { return nil }
        if room.owner == uid {
            if let next = room.members.keys.first(where: { $0 != uid }) {
                try? await db.document(room.path).updateData(["owner": next])
            } else {
                try? await db.document(room.path).delete()
                return nil
            }
        }
        return (try? await db.document(room.path).updateData([FieldPath(["members", uid]): FieldValue.delete()])) == nil
            ? "Couldn't leave the group. Check your connection." : nil
    }

    func renameGroup(_ room: Room, to name: String) async -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty || n.count > 40 || Self.hasBadWord(n) { return "That name can't be used." }
        return (try? await db.document(room.path).updateData(["name": n])) == nil ? "Couldn't rename the group." : nil
    }

    func findMember(username: String) async -> Member? {
        let key = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty, let nameDoc = try? await db.collection("usernames").document(key).getDocument(),
              let owner = nameDoc.data()?["uid"] as? String,
              let snap = try? await db.collection("chat_members").document(owner).getDocument() else { return nil }
        return Self.member(snap)
    }

    // MARK: Safety

    func block(uid other: String, name: String) async {
        guard let uid else { return }
        try? await db.collection("chat_members").document(uid).collection("blocks").document(other)
            .setData(["name": name, "at": FieldValue.serverTimestamp()])
        Speech.say("\(name) is blocked. You won't see their messages, and they can't message you.")
    }

    func unblock(uid other: String) async {
        guard let uid else { return }
        try? await db.collection("chat_members").document(uid).collection("blocks").document(other).delete()
    }

    func report(_ m: ChatMessage, in room: Room, context: [ChatMessage], reason: String) async -> Bool {
        guard let uid, let me = member else { return false }
        let around = context.map { "\($0.username): \($0.text)" }
        let data: [String: Any] = ["by": uid, "byName": me.username, "kind": room.kind.rawValue,
                                   "path": room.path + "/messages/" + m.id, "author": m.uid, "authorName": m.username,
                                   "text": m.text, "context": around, "reason": String(reason.prefix(500)),
                                   "at": FieldValue.serverTimestamp()]
        return (try? await db.collection("chat_reports").addDocument(data: data)) != nil
    }

    // MARK: Moderators

    struct Report: Identifiable {
        let id: String
        let byName: String
        let authorUID: String
        let authorName: String
        let text: String
        let context: [String]
        let reason: String
        let path: String
        let kind: String
        let date: Date
    }

    func reports() async -> [Report] {
        guard isMod, let snap = try? await db.collection("chat_reports").order(by: "at", descending: true).limit(to: 100).getDocuments() else { return [] }
        return snap.documents.map { d in
            Report(id: d.documentID, byName: d["byName"] as? String ?? "?", authorUID: d["author"] as? String ?? "",
                   authorName: d["authorName"] as? String ?? "?", text: d["text"] as? String ?? "",
                   context: d["context"] as? [String] ?? [], reason: d["reason"] as? String ?? "",
                   path: d["path"] as? String ?? "", kind: d["kind"] as? String ?? "",
                   date: (d["at"] as? Timestamp)?.dateValue() ?? Date())
        }
    }

    func dismiss(_ r: Report) async { try? await db.collection("chat_reports").document(r.id).delete() }

    /// Deletes a reported channel message (moderators can't reach private ones).
    func deleteReported(_ r: Report) async -> Bool { (try? await db.document(r.path).delete()) != nil }

    func ban(uid other: String, reason: String) async -> Bool {
        guard let uid else { return false }
        return (try? await db.collection("chat_bans").document(other)
            .setData(["by": uid, "reason": reason, "at": FieldValue.serverTimestamp()])) != nil
    }

    func unban(uid other: String) async -> Bool { (try? await db.collection("chat_bans").document(other).delete()) != nil }

    func bans() async -> [(uid: String, reason: String)] {
        guard let snap = try? await db.collection("chat_bans").getDocuments() else { return [] }
        return snap.documents.map { ($0.documentID, $0["reason"] as? String ?? "") }
    }

    func setRole(_ field: String, _ on: Bool, for other: String) async -> Bool {
        (try? await db.collection("chat_members").document(other).updateData([field: on])) != nil
    }

    // MARK: Deleting

    /// Your chat profile, blocks and notification settings. Messages you
    /// sent stay unless you delete them; your username stays yours in the game.
    static func deleteChatData(uid: String) async {
        let db = Account.db
        let me = db.collection("chat_members").document(uid)
        for sub in ["blocks", "private"] {
            if let docs = try? await me.collection(sub).getDocuments() {
                for d in docs.documents { try? await d.reference.delete() }
            }
        }
        try? await me.delete()
    }
}
