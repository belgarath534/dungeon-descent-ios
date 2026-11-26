import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import DungeonCore

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let uid: String
    let username: String
    let text: String
    let date: Date
    let replyTo: String?
    /// One emoji per person (uid → emoji).
    var reactions: [String: String] = [:]
    var pinned = false

    /// "2 👍, 1 🔥", most first.
    var reactionSummary: String {
        Dictionary(grouping: reactions.values, by: { $0 }).map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }.map { "\($0.1) \($0.0)" }.joined(separator: ", ")
    }

    /// Whether the text @mentions this username (any letter case).
    func mentions(_ name: String) -> Bool {
        text.range(of: "@" + name + "\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// What a player profile shows.
struct Profile {
    let uid: String
    let username: String
    let joined: Date?
    let role: String
    let online: Bool
    let highScore: Int?
    var bio = ""
    var favClass = ""
    /// Endless Descent's best floor and this week's Weekly Ladder score.
    var endlessFloor: Int? = nil
    var weeklyScore: Int? = nil
}

/// Something aimed at you: a mention, a reply or a reaction (written by the push server).
struct ActivityItem: Identifiable, Equatable {
    enum Kind: String { case mention, reply, reaction }
    let id: String
    let type: Kind
    let from: String
    let fromUID: String
    let text: String
    let emoji: String
    let roomKind: String
    let room: String
    let whereName: String
    let messageID: String
    let date: Date

    /// "Sebastian mentioned you in #general" (for lists and VoiceOver).
    var headline: String {
        switch type {
        case .mention: return "\(from) mentioned you in \(whereName)"
        case .reply: return roomKind == "dm" ? "\(from) replied to you" : "\(from) replied to you in \(whereName)"
        case .reaction: return "\(from) reacted \(emoji) to your message" + (roomKind == "dm" ? "" : " in \(whereName)")
        }
    }
    var spokenHeadline: String {
        type == .reaction ? headline.replacingOccurrences(of: emoji, with: ChatService.reactionNames[emoji] ?? emoji) : headline
    }
}

/// One line on a leaderboard.
struct BoardEntry: Identifiable, Equatable {
    let id: String      // the player's uid
    let rank: Int
    let name: String
    let score: Int
    var detail = ""
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
    var bio = ""
    var favClass = ""
    /// The rules allow a message every 2 seconds, counted from this.
    var lastPostAt: Date? = nil
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
    /// Who's online now: members who checked in within the last 2.5 minutes.
    @Published private(set) var online: [String] = []
    /// "Show me as online" (Settings); off: you never check in.
    @Published var showOnline = UserDefaults.standard.object(forKey: "chat.showOnline") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showOnline, forKey: "chat.showOnline")
            Task { await beat() }
        }
    }
    private var presenceTimer: Timer?
    /// New messages per channel id since you last read it.
    @Published private(set) var unread: [String: Int] = [:]
    /// When you last read each room (by path), kept on this device.
    private var lastRead: [String: Double] = (UserDefaults.standard.dictionary(forKey: "chat.lastRead") as? [String: Double]) ?? [:]

    /// Mentions, replies and reactions to you, newest first.
    @Published private(set) var activity: [ActivityItem] = []
    /// When you last looked at Activity (this device).
    @Published private(set) var activitySeen = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "chat.activitySeen"))

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
                let first = self?.member == nil
                self?.member = snap.flatMap { Self.member($0) }
                self?.memberLoaded = true
                if first, self?.member != nil { self?.presence(active: true) }
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
        listeners.append(db.collection("chat_members").document(uid).collection("activity")
            .order(by: "ts", descending: true).limit(to: 100).addSnapshotListener { [weak self] snap, _ in
                let items = (snap?.documents ?? []).compactMap { d -> ActivityItem? in
                    guard let type = ActivityItem.Kind(rawValue: d["type"] as? String ?? "") else { return nil }
                    return ActivityItem(id: d.documentID, type: type, from: d["from"] as? String ?? "Someone",
                                        fromUID: d["fromUid"] as? String ?? "", text: d["text"] as? String ?? "",
                                        emoji: d["emoji"] as? String ?? "", roomKind: d["kind"] as? String ?? "channel",
                                        room: d["room"] as? String ?? "", whereName: d["where"] as? String ?? "",
                                        messageID: d["mid"] as? String ?? "",
                                        date: (d["ts"] as? Timestamp)?.dateValue() ?? Date())
                }
                Task { @MainActor in self?.activity = items }
            })
        Task {
            let profile = try? await db.collection("users").document(uid).getDocument().data()
            gameUsername = profile?["username"] as? String
        }
    }

    // MARK: Online

    /// While the app is open: check in now and every minute, and refresh
    /// who's online. Called when the app comes to the front or goes away.
    func presence(active: Bool) {
        presenceTimer?.invalidate()
        presenceTimer = nil
        guard active, uid != nil else { return }
        Task { await beat() }
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.beat() }
        }
    }

    // MARK: Reactions, pins, your own channel order, reading aloud

    static let reactionEmojis = ["👍", "❤️", "😂", "🔥", "😮", "😢"]
    static let reactionNames = ["👍": "thumbs up", "❤️": "heart", "😂": "laughing", "🔥": "fire", "😮": "wow", "😢": "sad"]

    /// Sets your reaction (nil removes it).
    func react(_ m: ChatMessage, in room: Room, _ emoji: String?) async -> Bool {
        guard let uid else { return false }
        let ref = db.collection(room.path + "/messages").document(m.id)
        guard (try? await ref.updateData([FieldPath(["reactions", uid]): emoji ?? FieldValue.delete()])) != nil else { return false }
        await Push.call("react", ["kind": room.kind.rawValue, "room": room.id, "mid": m.id])
        return true
    }

    /// Moderators pin a channel message to the top.
    func pin(_ m: ChatMessage, in room: Room, _ on: Bool) async -> Bool {
        (try? await db.collection(room.path + "/messages").document(m.id).updateData(["pinned": on])) != nil
    }

    func pinnedMessages(_ room: Room) async -> [ChatMessage] {
        guard let snap = try? await db.collection(room.path + "/messages").whereField("pinned", isEqualTo: true).limit(to: 20).getDocuments() else { return [] }
        return snap.documents.map { d in
            ChatMessage(id: d.documentID, uid: d["uid"] as? String ?? "", username: d["username"] as? String ?? "Player",
                        text: d["text"] as? String ?? "", date: (d["ts"] as? Timestamp)?.dateValue() ?? Date(), replyTo: nil, pinned: true)
        }.sorted { $0.date > $1.date }
    }

    /// Channels you pinned to the top of your own list (this device).
    @Published var myPinned: [String] = UserDefaults.standard.stringArray(forKey: "chat.myPinned") ?? [] {
        didSet { UserDefaults.standard.set(myPinned, forKey: "chat.myPinned") }
    }

    func togglePinned(_ c: Channel) {
        if let i = myPinned.firstIndex(of: c.id) { myPinned.remove(at: i) } else { myPinned.append(c.id) }
    }

    /// The channels you can see, your pinned ones first (in the order you pinned them).
    var visibleChannels: [Channel] {
        let all = channels.filter { !$0.testersOnly || isTester }
        let pinned = myPinned.compactMap { id in all.first { $0.id == id } }
        return pinned + all.filter { !myPinned.contains($0.id) }
    }

    /// Read new messages aloud while you're in a conversation.
    @Published var readAloud = UserDefaults.standard.object(forKey: "chat.readAloud") as? Bool ?? true {
        didSet { UserDefaults.standard.set(readAloud, forKey: "chat.readAloud") }
    }

    // MARK: Profiles

    func profile(uid other: String) async -> Profile? {
        guard let d = try? await db.collection("chat_members").document(other).getDocument(), let m = Self.member(d) else { return nil }
        let seen = (d["lastSeen"] as? Timestamp)?.dateValue()
        let board = try? await db.collection("leaderboard").document(other).getDocument()
        let role = other == Self.developerUID ? "Developer" : m.mod ? "Moderator" : m.tester ? "Tester" : "Member"
        let tournament = db.collection("tournament")
        let endless = try? await tournament.document(AFKRivals.season).collection("scores").document(other).getDocument()
        let weekly = try? await tournament.document(Challenges.weekly().season).collection("scores").document(other).getDocument()
        return Profile(uid: other, username: m.username, joined: m.createdAt, role: role,
                       online: seen.map { Date().timeIntervalSince($0) < 150 } ?? false,
                       highScore: board?.data()?["score"] as? Int, bio: m.bio, favClass: m.favClass,
                       endlessFloor: endless?.data()?["score"] as? Int, weeklyScore: weekly?.data()?["score"] as? Int)
    }

    /// Your "about me" and favorite class; returns why not when refused.
    func saveProfile(bio raw: String, favClass: String) async -> String? {
        guard let uid else { return "You're not signed in." }
        let bio = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if bio.count > 160 { return "About me can have up to 160 characters." }
        if Self.hasBadWord(bio) { return "About me has a word that isn't allowed here." }
        do {
            try await db.collection("chat_members").document(uid).updateData(["bio": bio, "favClass": favClass])
            return nil
        } catch { return "Couldn't save. Check your connection." }
    }

    /// The game's classes, for "favorite class" (the rules accept these).
    static let classes = ["Warrior", "Monk", "Assassin", "Paladin", "Naturalist", "Sorcerer", "Necromancer", "Berserker", "Bard",
                          "Alchemist", "BloodKnight", "Druid", "Warlock", "DeathKnight", "Ranger", "Sentinel", "Cleric", "Wizard",
                          "Elementalist", "VoidWalker", "ShadowMage", "TimeMage", "Shaman", "Arcanist"]
    /// "BloodKnight" → "Blood Knight".
    static func className(_ id: String) -> String {
        id.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    }

    // MARK: Activity

    var unreadActivity: Int { activity.filter { $0.date > activitySeen && blocked[$0.fromUID] == nil }.count }

    func markActivitySeen() {
        activitySeen = Date()
        UserDefaults.standard.set(activitySeen.timeIntervalSince1970, forKey: "chat.activitySeen")
    }

    func removeActivity(_ item: ActivityItem) async {
        guard let uid else { return }
        try? await db.collection("chat_members").document(uid).collection("activity").document(item.id).delete()
    }

    func clearActivity() async {
        guard let uid else { return }
        let col = db.collection("chat_members").document(uid).collection("activity")
        guard let docs = try? await col.getDocuments() else { return }
        let batch = db.batch()
        for d in docs.documents.prefix(450) { batch.deleteDocument(d.reference) }
        try? await batch.commit()
    }

    /// The room a kind ("channel", "dm", "group") and id point to, when you can open it.
    func room(kind: String, id: String) -> Room? {
        switch kind {
        case "channel":
            guard let c = channels.first(where: { $0.id == id }), !c.testersOnly || isTester else { return nil }
            return Room(kind: .channel, id: c.id, title: c.name, path: "chat_channels/\(c.id)", canPost: !c.modsPost || isMod)
        case "dm": return dms.first { $0.id == id }
        case "group": return groups.first { $0.id == id }
        default: return nil
        }
    }

    // MARK: Leaderboards (the game's own)

    private func entries(_ snap: QuerySnapshot?, name: (DocumentSnapshot) -> String, detail: (DocumentSnapshot) -> String = { _ in "" }) -> [BoardEntry] {
        (snap?.documents ?? []).enumerated().map { i, d in
            BoardEntry(id: d["uid"] as? String ?? d.documentID, rank: i + 1, name: name(d),
                       score: (d["score"] as? NSNumber)?.intValue ?? 0, detail: detail(d))
        }.filter { blocked[$0.id] == nil }
    }

    /// A name from a tournament entry: older ones hold an email address, so only the part before @ shows.
    nonisolated private static func boardName(_ d: DocumentSnapshot, _ field: String = "email") -> String {
        let n = (d[field] as? String) ?? "Anonymous"
        if n.contains("@") { return String(String(n.split(separator: "@").first ?? "Player").prefix(3)) + "***" }
        return n
    }

    func highScores() async -> [BoardEntry] {
        let snap = try? await db.collection("leaderboard").order(by: "score", descending: true).limit(to: 25).getDocuments()
        return entries(snap) { d in
            let full = d["username"] as? String ?? "Anonymous"
            return full.components(separatedBy: " · ").first ?? full
        } detail: { d in d["tag"] as? String ?? "" }
    }

    /// The Weekly Ladder, an Endless Descent board ("afk-rivals"), a Tournament season or a World Boss day.
    func board(_ season: String, limit: Int = 25) async -> [BoardEntry] {
        let snap = try? await db.collection("tournament").document(season).collection("scores")
            .order(by: "score", descending: true).limit(to: limit).getDocuments()
        return entries(snap) { Self.boardName($0) } detail: { d in d["character"] as? String ?? "" }
    }

    /// Everyone's World Boss damage today, added up.
    func worldBossTotal(_ season: String) async -> Int? {
        guard let snap = try? await db.collection("tournament").document(season).collection("scores").getDocuments() else { return nil }
        return snap.documents.reduce(0) { $0 + (($1["score"] as? NSNumber)?.intValue ?? 0) }
    }

    /// The newest Hall of Legends posts.
    func legends(limit: Int = 15) async -> [ChatMessage] {
        guard let snap = try? await db.collection("chat_channels/hall-of-legends/messages").order(by: "ts", descending: true)
            .limit(to: limit).getDocuments() else { return [] }
        return snap.documents.map { d in
            ChatMessage(id: d.documentID, uid: d["uid"] as? String ?? "", username: d["username"] as? String ?? "Hall of Legends",
                        text: d["text"] as? String ?? "", date: (d["ts"] as? Timestamp)?.dateValue() ?? Date(), replyTo: nil)
        }
    }

    /// Whether a uid belongs to a chat member (for opening profiles from a leaderboard).
    func isChatMember(_ other: String) async -> Bool {
        (try? await db.collection("chat_members").document(other).getDocument())?.exists == true
    }

    // MARK: Unread

    private func readMark(_ path: String) -> Date {
        let joined = member?.createdAt ?? Date()
        guard let t = lastRead[path] else { return joined }
        return max(joined, Date(timeIntervalSince1970: t))
    }

    func markRead(_ room: Room) {
        lastRead[room.path] = Date().timeIntervalSince1970
        UserDefaults.standard.set(lastRead, forKey: "chat.lastRead")
        if room.kind == .channel { unread[room.id] = 0 }
        objectWillChange.send()
    }

    func isNew(_ room: Room) -> Bool {
        guard let at = room.lastAt else { return false }
        return at > readMark(room.path).addingTimeInterval(1)
    }

    var unreadChannels: Int { unread.values.reduce(0, +) }
    var unreadDMs: Int { dms.filter { isNew($0) && !$0.members.keys.contains { blocked[$0] != nil } }.count }
    var unreadGroups: Int { groups.filter(isNew).count }

    /// Counts new messages in each channel you can see.
    func refreshUnread() async {
        guard member != nil else { return }
        var out: [String: Int] = [:]
        for c in channels where !c.testersOnly || isTester {
            let q = db.collection("chat_channels/\(c.id)/messages").whereField("ts", isGreaterThan: Timestamp(date: readMark("chat_channels/\(c.id)")))
            if let n = try? await q.count.getAggregation(source: .server).count.intValue, n > 0 { out[c.id] = n }
        }
        unread = out
    }

    private func beat() async {
        await refreshUnread()
        guard let uid, member != nil else { return }
        let me = db.collection("chat_members").document(uid)
        try? await me.updateData(["lastSeen": showOnline ? FieldValue.serverTimestamp() : FieldValue.delete()])
        await refreshOnline()
    }

    func refreshOnline() async {
        let cutoff = Timestamp(date: Date().addingTimeInterval(-150))
        guard let snap = try? await db.collection("chat_members").whereField("lastSeen", isGreaterThan: cutoff)
            .order(by: "lastSeen", descending: true).limit(to: 200).getDocuments() else { return }
        online = snap.documents.compactMap { $0["username"] as? String }
            .filter { name in !blocked.values.contains(name) }
            .sorted { $0.lowercased() < $1.lowercased() }
    }

    func stop() {
        presenceTimer?.invalidate()
        presenceTimer = nil
        online = []
        listeners.forEach { $0.remove() }
        listeners = []
        member = nil; channels = []; dms = []; groups = []; blocked = [:]; banned = false; activity = []
        uid = nil
    }

    nonisolated static func member(_ d: DocumentSnapshot) -> Member? {
        guard d.exists, let name = d["username"] as? String else { return nil }
        return Member(uid: d.documentID, username: name,
                      createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                      agreed: d["agreedAt"] is Timestamp, mod: d["mod"] as? Bool ?? false,
                      tester: d["tester"] as? Bool ?? false, trusted: d["trusted"] as? Bool ?? false,
                      dmOff: d["dmOff"] as? Bool ?? false,
                      bio: d["bio"] as? String ?? "", favClass: d["favClass"] as? String ?? "",
                      lastPostAt: (d["lastPostAt"] as? Timestamp)?.dateValue())
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
                                replyTo: d["replyTo"] as? String, reactions: d["reactions"] as? [String: String] ?? [:],
                                pinned: d["pinned"] as? Bool ?? false)
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
        // At most a message every 2 seconds, counted from your last post (or
        // from joining): wait out what's left instead of failing.
        let wait = 2.3 - Date().timeIntervalSince(max(lastSent, me.lastPostAt ?? .distantPast))
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

    // MARK: Channels (the developer only; the rules allow nobody else)

    nonisolated static func channelID(_ name: String) -> String {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(slug).split(separator: "-").joined(separator: "-")
    }

    func saveChannel(id: String?, name raw: String, topic: String, modsPost: Bool, testersOnly: Bool) async -> String? {
        guard isDeveloper else { return "Only the developer can change channels." }
        let name = Self.channelID(raw)
        if name.isEmpty || name.count > 40 { return "A channel name needs 1 to 40 letters or numbers." }
        let cid = id ?? name
        if id == nil, channels.contains(where: { $0.id == cid }) { return "There's already a channel called \(name)." }
        var data: [String: Any] = ["name": name, "topic": String(topic.prefix(120)), "modsPost": modsPost, "testersOnly": testersOnly]
        if id == nil { data["order"] = (channels.map(\.order).max() ?? 0) + 1 }
        do {
            try await db.collection("chat_channels").document(cid).setData(data, merge: true)
            return nil
        } catch {
            return "Couldn't save the channel. Check your connection."
        }
    }

    func deleteChannel(_ c: Channel) async -> Bool {
        guard isDeveloper else { return false }
        return (try? await db.collection("chat_channels").document(c.id).delete()) != nil
    }

    /// Moves a channel up (-1) or down (+1) in the list.
    func moveChannel(_ c: Channel, by dir: Int) async {
        guard isDeveloper, let i = channels.firstIndex(of: c), channels.indices.contains(i + dir) else { return }
        let other = channels[i + dir]
        let batch = db.batch()
        batch.updateData(["order": other.order == c.order ? c.order + dir : other.order], forDocument: db.collection("chat_channels").document(c.id))
        batch.updateData(["order": c.order], forDocument: db.collection("chat_channels").document(other.id))
        try? await batch.commit()
    }

    // MARK: Deleting

    /// Your chat profile, blocks and notification settings. Messages you
    /// sent stay unless you delete them; your username stays yours in the game.
    static func deleteChatData(uid: String) async {
        let db = Account.db
        let me = db.collection("chat_members").document(uid)
        for sub in ["blocks", "private", "activity"] {
            if let docs = try? await me.collection(sub).getDocuments() {
                for d in docs.documents { try? await d.reference.delete() }
            }
        }
        try? await me.delete()
    }
}
