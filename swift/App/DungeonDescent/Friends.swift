import SwiftUI
import GameKit
import FirebaseDatabase
import DungeonCore

/// 12.1 Friends: your Game Center friends who play Dungeon Descent, who's
/// online, their best scores, and co-op invites. Each signed-in player keeps
/// a small entry in the shared database ("pvp_rooms/gcf_<id>": a display
/// name and when they were last seen) that invites are written into. Game
/// Center ids there are the per-developer ones, not Apple IDs.
@MainActor
final class Friends: ObservableObject {
    static let shared = Friends()

    struct Friend: Identifiable, Equatable {
        let id: String
        let name: String
        var lastSeen: Double = 0
        /// What they're doing ("in co-op", "on floor 6 of Crypt of Malachar").
        var activity = ""
        var online: Bool { Date().timeIntervalSince1970 * 1000 - lastSeen < 300_000 }
    }

    struct Invite: Identifiable, Equatable {
        let id: String
        let from: String
        let fromId: String
        let code: String
    }

    enum Access: Equatable { case signedOut, asking, denied, ok }

    @Published private(set) var friends: [Friend] = []
    @Published private(set) var access: Access = .signedOut
    @Published private(set) var loading = false
    /// An invite waiting for an answer (shown over any screen).
    @Published var invite: Invite?
    /// The room code to fill in when the Co-op screen opens after Join.
    var pendingJoin: String?

    private var started = false
    private var timer: Timer?
    private var players: [String: GKPlayer] = [:]
    private var seenInvites = Set<String>()

    private static var root: DatabaseReference { Database.database().reference(withPath: "pvp_rooms") }
    static func key(_ id: String) -> String {
        "gcf_" + String(id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
    }
    private static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    var myId: String? { GKLocalPlayer.local.isAuthenticated ? GKLocalPlayer.local.teamPlayerID : nil }
    var myName: String { GKLocalPlayer.local.displayName }

    /// After Game Center signs in: show up as online, and listen for invites.
    func start() {
        guard !started, let me = myId else { return }
        started = true
        access = .ok
        let ref = Self.root.child(Self.key(me))
        func beat() { ref.updateChildValues(["kind": "friend", "n": myName, "t": Self.now, "a": activity]) }
        beat()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in Task { @MainActor in beat() } }
        ref.child("inv").observe(.value) { [weak self] snap in
            let v = snap.value as? [String: Any]
            Task { @MainActor in self?.received(v) }
        }
    }

    // MARK: What you're doing (12.1)

    private(set) var activity = "in the menus"

    /// Shown to your friends next to your name; sent when it changes.
    func doing(_ what: String) {
        guard what != activity else { return }
        activity = what
        guard started, let me = myId else { return }
        Self.root.child(Self.key(me)).updateChildValues(["a": what, "t": Self.now])
    }

    /// The screen you open says what you're doing (a dungeon run says its floor).
    func doing(screen: Router.Screen) {
        switch screen {
        case .dungeon: doing("in a dungeon")
        case .coop: doing("in co-op")
        case .spire: doing("climbing the Spire")
        case .afk: doing("in Endless Descent")
        case .worldBoss: doing("fighting the World Boss")
        case .raid: doing("in a raid")
        case .bossrush: doing("in Boss Rush")
        case .mine: doing("in the Mine")
        case .multiplayer: doing("in the PvP Arena")
        case .challenges: doing("in Challenges")
        case .siege: doing("in the Siege")
        case .shadowRealm: doing("in the Shadow Realm")
        case .chat: doing("in Global Chat")
        default: doing("in the menus")
        }
    }

    // MARK: The list

    /// Game Center asks once for permission to see your friends list.
    func load() {
        guard GKLocalPlayer.local.isAuthenticated else { access = .signedOut; return }
        start()
        loading = true
        GKLocalPlayer.local.loadFriendsAuthorizationStatus { [weak self] status, _ in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .denied, .restricted:
                    self.access = .denied
                    self.loading = false
                default:
                    self.fetch()
                }
            }
        }
    }

    private func fetch() {
        GKLocalPlayer.local.loadFriends { [weak self] list, error in
            let found = (list ?? []).map { ($0.teamPlayerID, $0.displayName, $0) }
            let denied = (error as? GKError)?.code == .friendListDenied
            Task { @MainActor in
                guard let self else { return }
                self.loading = false
                if denied { self.access = .denied; return }
                self.access = .ok
                var out: [Friend] = []
                for (id, name, p) in found where !self.isBlocked(id) {
                    self.players[id] = p
                    out.append(self.friends.first { $0.id == id } ?? Friend(id: id, name: name))
                }
                self.friends = out.sorted { $0.name.lowercased() < $1.name.lowercased() }
                self.refreshOnline()
            }
        }
    }

    /// When each friend was last seen.
    func refreshOnline() {
        for f in friends {
            let ref = Self.root.child(Self.key(f.id))
            ref.child("t").observeSingleEvent(of: .value) { [weak self] snap in
                let t = (snap.value as? NSNumber)?.doubleValue ?? 0
                Task { @MainActor in
                    guard let self, let i = self.friends.firstIndex(where: { $0.id == f.id }) else { return }
                    self.friends[i].lastSeen = t
                }
            }
            ref.child("a").observeSingleEvent(of: .value) { [weak self] snap in
                let a = String((snap.value as? String ?? "").prefix(60))
                Task { @MainActor in
                    guard let self, let i = self.friends.firstIndex(where: { $0.id == f.id }) else { return }
                    self.friends[i].activity = a
                }
            }
        }
    }

    var online: [Friend] { friends.filter(\.online) }

    func seenText(_ f: Friend) -> String {
        if f.online { return f.activity.isEmpty ? "online now" : "online, \(f.activity)" }
        guard f.lastSeen > 0 else { return "hasn't opened this version yet" }
        let mins = Int((Date().timeIntervalSince1970 * 1000 - f.lastSeen) / 60_000)
        if mins < 60 { return "seen \(mins) minutes ago" }
        if mins < 1440 { return "seen \(mins / 60) hour\(mins / 60 == 1 ? "" : "s") ago" }
        return "seen \(mins / 1440) day\(mins / 1440 == 1 ? "" : "s") ago"
    }

    // MARK: Scores

    /// A friend's best on each leaderboard (nil: no score yet).
    func scores(of f: Friend) async -> [(GameCenter.Board, Int?)] {
        guard let p = players[f.id] else { return [] }
        let boards = (try? await GKLeaderboard.loadLeaderboards(IDs: GameCenter.Board.allCases.map(\.rawValue))) ?? []
        var out: [(GameCenter.Board, Int?)] = []
        for b in GameCenter.Board.allCases {
            guard let lb = boards.first(where: { $0.baseLeaderboardID == b.rawValue }) else { out.append((b, nil)); continue }
            let entries = try? await lb.loadEntries(for: [p], timeScope: .allTime)
            out.append((b, entries?.1.first?.score))
        }
        return out
    }

    // MARK: Rankings

    struct Row: Identifiable, Equatable {
        let rank: Int
        let name: String
        let score: Int
        let me: Bool
        var id: Int { rank }
    }

    /// A leaderboard read in the game, friends or the world's top 10, plus
    /// where you are on it.
    func ranking(_ b: GameCenter.Board, friendsOnly: Bool) async -> (me: Row?, rows: [Row])? {
        guard GKLocalPlayer.local.isAuthenticated,
              let lb = (try? await GKLeaderboard.loadLeaderboards(IDs: [b.rawValue]))?.first,
              let got = try? await lb.loadEntries(for: friendsOnly ? .friendsOnly : .global, timeScope: .allTime,
                                                  range: NSRange(location: 1, length: friendsOnly ? 50 : 10))
        else { return nil }
        let mine = GKLocalPlayer.local.teamPlayerID
        func row(_ e: GKLeaderboard.Entry) -> Row {
            Row(rank: e.rank, name: e.player.displayName, score: e.score, me: e.player.teamPlayerID == mine)
        }
        let rows = got.1.filter { $0.player.teamPlayerID == mine || !isBlocked($0.player.teamPlayerID) }.map(row)
        return (got.0.map(row), rows)
    }

    // MARK: Invites

    /// Sends your co-op room's code to a friend.
    func invite(_ f: Friend, code: String) {
        guard let me = myId else { return }
        Self.root.child(Self.key(f.id)).child("inv").setValue(["from": myName, "fromId": me, "code": code, "t": Self.now]) { error, _ in
            Task { @MainActor in
                Feedback.announce(error == nil ? "Invite sent to \(f.name)." : "Couldn't send the invite. Check your connection.")
            }
        }
        Sound.sfx("sfx-confirm")
    }

    private func received(_ v: [String: Any]?) {
        guard let v, let from = v["from"] as? String, let fromId = v["fromId"] as? String,
              let code = v["code"] as? String, code.count == 4,
              let t = (v["t"] as? NSNumber)?.doubleValue else { return }
        let id = "\(fromId)-\(Int(t))"
        // Only fresh invites, once, and never from someone you blocked.
        guard Self.now - t < 600_000, !seenInvites.contains(id), !isBlocked(fromId) else { return }
        seenInvites.insert(id)
        invite = Invite(id: id, from: String(from.prefix(40)), fromId: fromId, code: code.uppercased())
        Sound.sfx("sfx-ach-silver")
        Feedback.success()
    }

    /// Answering an invite clears it, so it isn't shown again.
    func answered() {
        invite = nil
        if let me = myId { Self.root.child(Self.key(me)).child("inv").removeValue() }
    }

    // MARK: Block and report

    private var blocked: [String] { UserDefaults.standard.stringArray(forKey: "swift_friends_blocked") ?? [] }
    func isBlocked(_ id: String) -> Bool { blocked.contains(id) }

    /// Hidden from your list, and their invites are ignored.
    func block(_ f: Friend) {
        UserDefaults.standard.set(blocked + [f.id], forKey: "swift_friends_blocked")
        friends.removeAll { $0.id == f.id }
        Feedback.announce("\(f.name) is blocked. They're hidden from your friends list, and their invites won't reach you.")
    }

    func unblockAll() {
        UserDefaults.standard.removeObject(forKey: "swift_friends_blocked")
        Feedback.announce("Everyone is unblocked.")
        load()
    }

    var blockedCount: Int { blocked.count }

    func report(_ f: Friend) {
        block(f)
        Task {
            await GlobalChat.sendReport(kind: "player", id: f.id, author: f.name, content: "Friends list player",
                                        reason: "", reporter: myName)
        }
    }
}
