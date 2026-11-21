import SwiftUI
import FirebaseDatabase
import DungeonCore

/// Hide and Seek with up to 5 players (hs_rooms in the web version's
/// Realtime Database, the same layout, so Swift and web players share a
/// house). Every move and hide is a transaction on the shared state, so two
/// players moving at once can't overwrite each other.
@MainActor
final class HideSeekMultiplayer: ObservableObject {
    enum Stage { case lobby, room, playing, ended }

    struct Player: Identifiable {
        let id, name: String
        let x, y: Int
        let caught, escaped: Bool
    }

    @Published var stage: Stage = .lobby
    @Published var status = ""
    @Published private(set) var code: String?
    @Published private(set) var isHost = false
    @Published private(set) var lobby: [(id: String, name: String, ready: Bool)] = []
    @Published private(set) var readyPressed = false
    @Published private(set) var players: [Player] = []
    @Published private(set) var items = 0
    @Published private(set) var monster = (x: 6, y: 6)
    @Published var desc = "You stand still, listening."

    let myId = String((0..<8).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
    var myName = "Player\(Int.random(in: 100...999))"
    private var handle: DatabaseHandle?
    private var lastSeq = -1
    private var lobbyNames: [String: String] = [:]
    private var soloConfirmed = false
    private var chasing = false

    private var rooms: DatabaseReference { Database.database().reference(withPath: "hs_rooms") }
    private var room: DatabaseReference? { code.map { rooms.child($0) } }

    private func say(_ text: String) {
        status = text
        Feedback.announce(text)
    }

    var me: Player? { players.first { $0.id == myId } }

    /// Rooms between you and it, and where it is, for the growl.
    var distance: Int { me.map { abs($0.x - monster.x) + abs($0.y - monster.y) } ?? 99 }
    var pan: Double {
        guard let me else { return 0 }
        let dx = monster.x - me.x, dy = monster.y - me.y
        guard dx != 0 || dy != 0, abs(dx) >= abs(dy) else { return 0 }
        return dx > 0 ? 0.8 : -0.8
    }
    var volume: Double { max(0.15, 1 - Double(distance) * 0.08) }

    // MARK: Lobby

    /// hsMpCreateRoom
    func create() {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let c = String((0..<4).map { _ in chars.randomElement()! })
        code = c
        isHost = true
        rooms.child(c).setValue([
            "code": c, "hostId": myId, "createdAt": (Date().timeIntervalSince1970 * 1000).rounded(), "status": "waiting",
            "lobby": [myId: ["name": myName, "ready": false]],
        ]) { [weak self] error, ref in
            Task { @MainActor in
                guard let self else { return }
                if error != nil { self.code = nil; self.say("Failed to create room. Check your connection."); return }
                self.stage = .room
                Sound.sfx("sfx-confirm")
                self.say("Room created. Your code is \(c.map(String.init).joined(separator: " ")). Share it with up to four friends.")
                self.listen()
                DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
                    ref.observeSingleEvent(of: .value) { snap in
                        if (snap.value as? [String: Any])?["status"] as? String == "waiting" { ref.removeValue() }
                    }
                }
            }
        }
    }

    /// hsMpJoinRoom
    func join(_ raw: String) {
        let c = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard c.count == 4 else { say("Enter a valid 4 character room code."); return }
        rooms.child(c).observeSingleEvent(of: .value, with: { [weak self] snap in
            let r = snap.value as? [String: Any]
            Task { @MainActor in
                guard let self else { return }
                guard let r else { self.say("Room not found."); return }
                if r["status"] as? String != "waiting" { self.say("That run already started."); return }
                if ((r["lobby"] as? [String: Any])?.count ?? 0) >= 5 { self.say("Room is full (5 players)."); return }
                self.code = c
                self.isHost = false
                self.rooms.child(c).child("lobby").child(self.myId).setValue(["name": self.myName, "ready": false])
                self.stage = .room
                Sound.sfx("sfx-confirm")
                self.say("Joined room \(c).")
                self.listen()
            }
        }, withCancel: { [weak self] _ in
            Task { @MainActor in self?.say("Failed to join room. Check your connection.") }
        })
    }

    private func listen() {
        guard let ref = room else { return }
        if let h = handle { ref.removeObserver(withHandle: h) }
        handle = ref.observe(.value) { [weak self] snap in
            let r = snap.value as? [String: Any]
            Task { @MainActor in self?.update(r) }
        }
    }

    func ready() {
        room?.child("lobby").child(myId).child("ready").setValue(true)
        readyPressed = true
        Sound.sfx("sfx-confirm")
    }

    /// hsMpHostStart: everyone starts in the corner; starting alone takes a second press.
    func start() {
        guard isHost, let ref = room else { return }
        if lobby.count == 1 && !soloConfirmed {
            soloConfirmed = true
            say("Starting alone. Hide and Seek is built for playing with friends. Press Start again to go anyway.")
            return
        }
        var ps: [String: Any] = [:]
        for p in lobby {
            ps[p.id] = ["name": p.name, "x": 0, "y": 0, "caught": false, "escaped": false, "hiddenUntil": 0, "hideCooldownUntil": 0]
        }
        let starts = [(6, 0), (0, 6), (6, 6), (6, 3), (3, 6)]
        let m = starts.randomElement()!
        ref.updateChildValues([
            "status": "started",
            "state": ["players": ps, "monster": ["x": m.0, "y": m.1], "items": 0, "moveSeq": 0, "status": "active"],
        ])
    }

    /// hsMpLeaveLobby / leaving mid-run.
    func leave() {
        if let ref = room {
            if let h = handle { ref.removeObserver(withHandle: h) }
            ref.child("lobby").child(myId).removeValue()
            if isHost {
                ref.observeSingleEvent(of: .value) { snap in
                    if (snap.value as? [String: Any])?["status"] as? String == "waiting" { ref.removeValue() }
                }
            }
        }
        handle = nil
        code = nil
        stage = .lobby
        players = []
        lobby = []
        readyPressed = false
        lastSeq = -1
        Sound.stopLoop()
    }

    // MARK: Room updates

    nonisolated private static func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

    /// hsMpHandleRoomUpdate
    private func update(_ r: [String: Any]?) {
        guard let r else {
            if stage != .lobby { say("The room was closed."); leave() }
            return
        }
        if r["status"] as? String == "waiting" {
            let l = (r["lobby"] as? [String: Any]) ?? [:]
            let list = l.keys.sorted().compactMap { id -> (id: String, name: String, ready: Bool)? in
                guard let p = l[id] as? [String: Any] else { return nil }
                return (id, (p["name"] as? String) ?? "Player", (p["ready"] as? Bool) ?? false)
            }
            for p in list where p.id != myId && lobbyNames[p.id] == nil { Feedback.announce("\(p.name) joined the lobby.") }
            for (id, name) in lobbyNames where id != myId && !list.contains(where: { $0.id == id }) {
                Feedback.announce("\(name) left the lobby.")
            }
            lobbyNames = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0.name) })
            lobby = list
            status = "\(list.count) of 5 players — \(list.filter { $0.ready }.count) ready."
            return
        }
        guard let state = r["state"] as? [String: Any] else { return }
        let ps = (state["players"] as? [String: Any]) ?? [:]
        players = ps.keys.sorted().compactMap { id in
            guard let p = ps[id] as? [String: Any] else { return nil }
            return Player(id: id, name: (p["name"] as? String) ?? "A player", x: Self.int(p["x"]), y: Self.int(p["y"]),
                          caught: (p["caught"] as? Bool) ?? false, escaped: (p["escaped"] as? Bool) ?? false)
        }
        items = Self.int(state["items"])
        if let m = state["monster"] as? [String: Any] { monster = (Self.int(m["x"]), Self.int(m["y"])) }

        if stage == .room || stage == .lobby {
            stage = .playing
            chasing = false
            Sound.track("hideseek-explore")
            Sound.sfx("sfx-select")
            Feedback.announce("Hide and Seek begins. \(players.count) players. Find the way out together — walk onto a caught teammate to rescue them.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.stage == .playing else { return }
                Sound.startLoop("monster-growl.mp3", volume: self.volume, pan: self.pan)
            }
        }
        if state["status"] as? String == "over" {
            if stage != .ended { end() }
            return
        }
        if let ev = state["lastEvent"] as? [String: Any] { event(ev) }
        Sound.moveLoop(volume: volume, pan: pan)
        // The music turns to the chase as soon as anyone still in the house is close.
        let closest = players.filter { !$0.caught && !$0.escaped }
            .map { abs($0.x - monster.x) + abs($0.y - monster.y) }.min() ?? 99
        let chase = closest <= HideAndSeek.chaseDistance
        if chase != chasing {
            chasing = chase
            Sound.track(chase ? "hideseek-chase" : "hideseek-explore")
        }
    }

    private func name(_ id: String?) -> String { players.first { $0.id == id }?.name ?? "A player" }

    /// hsMpHandleNewEvent: what happened, read out.
    private func event(_ ev: [String: Any]) {
        let seq = Self.int(ev["seq"])
        guard seq != lastSeq else { return }
        lastSeq = seq
        let by = ev["by"] as? String
        let isMe = by == myId
        var said: [String] = []
        switch ev["type"] as? String {
        case "wall": if isMe { said.append("There is a wall that way.") }
        case "move":
            if isMe {
                desc = HideAndSeek.roomDescs.randomElement()!
                said.append("Moving \((ev["dir"] as? String) ?? "on"). \(desc)")
                if (ev["foundItem"] as? Bool) == true { said.append("You spot something that will help you hide.") }
                if (ev["escaped"] as? Bool) == true { said.append("You made it to the exit! You escaped.") }
                else {
                    let warn = [6: "You can hear it somewhere behind you.", 4: "It is getting closer.",
                                2: "It is right behind you. Hide, or run.", 1: "It is almost on you."]
                    if let w = warn[distance] { said.append(w) }
                }
            } else if (ev["escaped"] as? Bool) == true {
                said.append("\(name(by)) escaped!")
            }
            if let rescued = ev["rescued"] as? String {
                said.append(rescued == myId ? "You were rescued\(isMe ? "" : " by \(name(by))")."
                            : "\(name(rescued)) was rescued\(isMe ? "" : " by \(name(by))").")
            }
        case "hide-cooldown": if isMe { said.append("Still catching your breath from last time.") }
        case "hide-success": if isMe { said.append("You hid successfully. The next advance will pass you by.") }
        case "hide-fail": if isMe { said.append("It sensed you.") }
        default: break
        }
        for id in (ev["caught"] as? [String]) ?? [] {
            said.append(id == myId ? "It caught you! Wait for a teammate to reach you." : "\(name(id)) was caught!")
            if id == myId { Feedback.warning() }
        }
        if !said.isEmpty { Feedback.announce(said.joined(separator: " ")) }
    }

    private func end() {
        stage = .ended
        Sound.stopLoop()
        Sound.track("menu")
        let escaped = players.filter(\.escaped).count
        Sound.sfx(escaped == 0 ? "sfx-death" : "sfx-confirm")
        Feedback.announce((escaped == 0 ? "Everyone was caught. " : "Run over. ") + "\(escaped) of \(players.count) players escaped.")
    }

    // MARK: Moving and hiding (the shared state transactions)

    /// _hsMpComputeNearestTarget + _hsMpAdvanceMonsterToward on the raw state.
    nonisolated private static func advance(_ state: inout [String: Any], seq: Int) -> [String] {
        var ps = (state["players"] as? [String: Any]) ?? [:]
        var mo = (state["monster"] as? [String: Any]) ?? [:]
        var mx = int(mo["x"]), my = int(mo["y"])
        var target: (Int, Int)?
        var best = Int.max
        for id in ps.keys.sorted() {
            guard let p = ps[id] as? [String: Any] else { continue }
            if (p["caught"] as? Bool) == true || (p["escaped"] as? Bool) == true { continue }
            if int(p["hiddenUntil"]) > seq { continue }
            let d = abs(int(p["x"]) - mx) + abs(int(p["y"]) - my)
            if d < best { best = d; target = (int(p["x"]), int(p["y"])) }
        }
        var caught: [String] = []
        guard let t = target else { return caught }
        let dx = t.0 - mx, dy = t.1 - my
        if dx != 0 || dy != 0 {
            if abs(dx) >= abs(dy) { mx += dx > 0 ? 1 : -1 } else { my += dy > 0 ? 1 : -1 }
        }
        mo["x"] = mx
        mo["y"] = my
        state["monster"] = mo
        for id in ps.keys {
            guard var p = ps[id] as? [String: Any] else { continue }
            if (p["escaped"] as? Bool) != true && (p["caught"] as? Bool) != true && int(p["x"]) == mx && int(p["y"]) == my {
                p["caught"] = true
                ps[id] = p
                caught.append(id)
            }
        }
        state["players"] = ps
        return caught
    }

    nonisolated private static func stillPlaying(_ state: [String: Any]) -> Bool {
        ((state["players"] as? [String: Any]) ?? [:]).values.contains {
            guard let p = $0 as? [String: Any] else { return false }
            return (p["caught"] as? Bool) != true && (p["escaped"] as? Bool) != true
        }
    }

    /// hsMpMove
    func move(_ dir: HideAndSeek.Direction) {
        guard stage == .playing, let ref = room?.child("state") else { return }
        if let me, me.caught || me.escaped { return }
        Sound.sfx("sfx-footstep")
        let myId = self.myId
        ref.runTransactionBlock { data in
            guard var state = data.value as? [String: Any], var ps = state["players"] as? [String: Any],
                  var me = ps[myId] as? [String: Any], state["status"] as? String != "over",
                  (me["caught"] as? Bool) != true, (me["escaped"] as? Bool) != true else { return .success(withValue: data) }
            var nx = Self.int(me["x"]), ny = Self.int(me["y"])
            var moved = true
            switch dir {
            case .north: if ny > 0 { ny -= 1 } else { moved = false }
            case .south: if ny < 6 { ny += 1 } else { moved = false }
            case .west: if nx > 0 { nx -= 1 } else { moved = false }
            case .east: if nx < 6 { nx += 1 } else { moved = false }
            }
            let seq = Self.int(state["moveSeq"]) + 1
            state["moveSeq"] = seq
            guard moved else {
                state["lastEvent"] = ["type": "wall", "by": myId, "seq": seq]
                data.value = state
                return .success(withValue: data)
            }
            me["x"] = nx
            me["y"] = ny
            var rescued: String?
            for id in ps.keys where id != myId {
                guard var p = ps[id] as? [String: Any] else { continue }
                if (p["caught"] as? Bool) == true && (p["escaped"] as? Bool) != true && Self.int(p["x"]) == nx && Self.int(p["y"]) == ny {
                    p["caught"] = false
                    ps[id] = p
                    rescued = id
                }
            }
            var found = false
            if Self.int(state["items"]) < 5 && Double.random(in: 0..<1) < 0.20 {
                state["items"] = Self.int(state["items"]) + 1
                found = true
            }
            let escaped = nx == 6 && ny == 6
            if escaped { me["escaped"] = true }
            ps[myId] = me
            state["players"] = ps
            let caught = Self.advance(&state, seq: seq)
            if !Self.stillPlaying(state) { state["status"] = "over" }
            var ev: [String: Any] = ["type": "move", "by": myId, "dir": dir.rawValue, "seq": seq,
                                     "foundItem": found, "escaped": escaped, "caught": caught]
            if let rescued { ev["rescued"] = rescued }
            state["lastEvent"] = ev
            data.value = state
            return .success(withValue: data)
        }
    }

    /// hsMpHide: shared hiding spots; a good hide skips you on the next advance.
    func hide() {
        guard stage == .playing, let ref = room?.child("state") else { return }
        Sound.sfx("sfx-select")
        let myId = self.myId
        ref.runTransactionBlock { data in
            guard var state = data.value as? [String: Any], var ps = state["players"] as? [String: Any],
                  var me = ps[myId] as? [String: Any], state["status"] as? String != "over",
                  (me["caught"] as? Bool) != true, (me["escaped"] as? Bool) != true else { return .success(withValue: data) }
            let current = Self.int(state["moveSeq"])
            if Self.int(me["hideCooldownUntil"]) >= current && Self.int(me["hideCooldownUntil"]) > 0 {
                state["lastEvent"] = ["type": "hide-cooldown", "by": myId, "seq": current]
                data.value = state
                return .success(withValue: data)
            }
            let seq = current + 1
            state["moveSeq"] = seq
            me["hideCooldownUntil"] = seq
            let usedItem = Self.int(state["items"]) > 0
            if usedItem { state["items"] = Self.int(state["items"]) - 1 }
            if Double.random(in: 0..<1) < 0.55 + (usedItem ? 0.25 : 0) {
                me["hiddenUntil"] = seq + 1
                ps[myId] = me
                state["players"] = ps
                state["lastEvent"] = ["type": "hide-success", "by": myId, "usedItem": usedItem, "seq": seq]
            } else {
                ps[myId] = me
                state["players"] = ps
                let caught = Self.advance(&state, seq: seq)
                state["lastEvent"] = ["type": "hide-fail", "by": myId, "seq": seq, "caught": caught]
            }
            if !Self.stillPlaying(state) { state["status"] = "over" }
            data.value = state
            return .success(withValue: data)
        }
    }
}
