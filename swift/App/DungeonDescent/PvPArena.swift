import SwiftUI
import FirebaseDatabase
import DungeonCore

/// The PVP Arena (pvp_rooms in the web version's Realtime Database). Rooms
/// use exactly the web version's layout, so a Swift player and a web player
/// can fight each other.
@MainActor
final class PvPArena: ObservableObject {
    enum Stage { case lobby, room, battle, over }

    struct Fighter: Identifiable {
        let id: String
        let name, cls: String
        let hp, maxHp: Int
        let defending, alive, isMe: Bool
    }

    @Published var stage: Stage = .lobby
    @Published var status = ""
    @Published private(set) var code: String?
    @Published private(set) var fighters: [Fighter] = []
    @Published private(set) var log: [String] = []
    @Published private(set) var myTurn = false
    @Published private(set) var readyPressed = false
    @Published private(set) var mySp = 20

    let myId = String((0..<8).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
    private(set) var character: PlayerCharacter?
    private var role: String?
    private var handle: DatabaseHandle?
    private var hadBattle = false
    private var lastLog: [String] = []

    private var rooms: DatabaseReference { Database.database().reference(withPath: "pvp_rooms") }
    private var room: DatabaseReference? { code.map { rooms.child($0) } }

    private func say(_ text: String) {
        status = text
        Feedback.announce(text)
    }

    func select(_ ch: PlayerCharacter) {
        character = ch
        Sound.sfx("sfx-select")
        Feedback.announce("\(ch.name) selected. Create a room or join a friend.")
    }

    /// mpGetCharData: the class's base stats.
    private func charData(_ ch: PlayerCharacter) -> [String: Any] {
        let info = GameData.classInfo(ch.cls)
        let lvl: Int = { if case .number(let n)? = ch.extra["level"] { return Int(n) }; return 1 }()
        return [
            "name": ch.name.isEmpty ? "Warrior" : ch.name, "cls": ch.cls, "race": ch.race, "level": lvl,
            "maxHp": info.maxHp, "hp": info.maxHp, "maxSp": 20, "sp": 20,
            "atk": (info.atk.lowerBound + info.atk.upperBound) / 2, "def": info.def,
            "alive": true, "defending": false, "dungeon": ch.dungeon,
        ]
    }

    // MARK: Rooms

    /// mpCreateRoom: a 4-character code to share.
    func create() {
        guard let ch = character else { say("Select a character first."); return }
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let c = String((0..<4).map { _ in chars.randomElement()! })
        code = c
        role = "p1"
        let data: [String: Any] = [
            "code": c, "status": "waiting",
            "p1": ["id": myId, "char": charData(ch), "ready": false],
            "createdAt": Self.now,
        ]
        rooms.child(c).setValue(data) { [weak self] error, ref in
            Task { @MainActor in
                guard let self else { return }
                if error != nil { self.say("Failed to create room. Check your connection."); return }
                self.stage = .room
                Sound.sfx("sfx-confirm")
                self.say("Room created! Share code \(c.map(String.init).joined(separator: " ")) with your opponent. Then both press Ready.")
                self.listen()
                // An unused room is removed after 10 minutes, like the web version.
                DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
                    ref.observeSingleEvent(of: .value) { snap in
                        if (snap.value as? [String: Any])?["status"] as? String == "waiting" { ref.removeValue() }
                    }
                }
            }
        }
    }

    /// mpJoinRoom
    func join(_ raw: String) {
        guard let ch = character else { say("Select a character first."); return }
        let c = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard c.count == 4 else { say("Enter a valid 4 character room code."); return }
        rooms.child(c).observeSingleEvent(of: .value, with: { [weak self] snap in
            Task { @MainActor in
                guard let self else { return }
                guard let r = snap.value as? [String: Any] else { self.say("Room not found. Check the code and try again."); return }
                if r["status"] as? String != "waiting" || r["p2"] is [String: Any] {
                    self.say("Room is already full or in progress.")
                    return
                }
                self.code = c
                self.role = "p2"
                let ref = self.rooms.child(c)
                ref.child("p2").setValue(["id": self.myId, "char": self.charData(ch), "ready": false])
                ref.child("status").setValue("full")
                self.stage = .room
                Sound.sfx("sfx-confirm")
                self.say("Joined room \(c)! Press Ready when prepared to fight!")
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
            let value = snap.value as? [String: Any]
            Task { @MainActor in
                guard let self else { return }
                guard let r = value else {
                    if self.stage != .lobby { self.say("Room no longer exists.") }
                    return
                }
                self.update(r)
            }
        }
    }

    /// The room entry: before the battle it's {id, char, ready}; during it
    /// the character's numbers sit right on the entry.
    private func fighter(_ entry: Any?, isMe: Bool) -> Fighter? {
        guard let e = entry as? [String: Any] else { return nil }
        let c = (e["char"] as? [String: Any]) ?? e
        func i(_ k: String, _ d: Int) -> Int { (c[k] as? NSNumber)?.intValue ?? d }
        return Fighter(id: (e["id"] as? String) ?? (isMe ? "me" : "them"), name: (c["name"] as? String) ?? "Player",
                       cls: (c["cls"] as? String) ?? "", hp: i("hp", 0), maxHp: i("maxHp", 100),
                       defending: (c["defending"] as? Bool) ?? false, alive: (c["alive"] as? Bool) ?? true, isMe: isMe)
    }

    private static func logLines(_ v: Any?) -> [String] {
        if let a = v as? [Any] { return a.compactMap { $0 as? String } }
        if let d = v as? [String: Any] {
            return d.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }.compactMap { d[$0] as? String }
        }
        return []
    }

    /// The lines at the end of `new` that weren't in `old`. The log keeps
    /// only its last 30 lines, so this finds where the old one's end overlaps.
    static func added(from old: [String], to new: [String]) -> [String] {
        guard !old.isEmpty else { return new }
        for k in stride(from: min(old.count, new.count), through: 1, by: -1)
        where Array(old.suffix(k)) == Array(new.prefix(k)) {
            return Array(new.dropFirst(k))
        }
        return new
    }

    /// mpHandleRoomUpdate
    private func update(_ r: [String: Any]) {
        guard let role else { return }
        let other = role == "p1" ? "p2" : "p1"
        let roomStatus = r["status"] as? String
        let started = (r["battleStarted"] as? Bool) ?? false
        fighters = [fighter(r[role], isMe: true), fighter(r[other], isMe: false)].compactMap { $0 }
        if let me = (r[role] as? [String: Any]) {
            mySp = (((me["char"] as? [String: Any]) ?? me)["sp"] as? NSNumber)?.intValue ?? 20
        }

        let lines = Self.logLines(r["log"])
        // The opponent's moves and emotes are read out as they arrive.
        if stage == .battle || stage == .over {
            for l in Self.added(from: lastLog, to: lines) { Feedback.announce(l) }
        }
        lastLog = lines
        log = lines

        let p1 = r["p1"] as? [String: Any], p2 = r["p2"] as? [String: Any]
        if roomStatus == "full", let p1, let p2, !started,
           (p1["ready"] as? Bool) == true, (p2["ready"] as? Bool) == true {
            // Only p1 starts the battle, so the two players can't both do it.
            if role == "p1" {
                var a = (p1["char"] as? [String: Any]) ?? [:]; a["id"] = p1["id"]; a["ready"] = true
                var b = (p2["char"] as? [String: Any]) ?? [:]; b["id"] = p2["id"]; b["ready"] = true
                room?.updateChildValues([
                    "battleStarted": true, "turn": (Bool.random() ? p1["id"] : p2["id"]) ?? myId,
                    "log": ["⚔️ The battle begins!"], "p1": a, "p2": b,
                ])
            }
            return
        }

        if roomStatus == "over" {
            if stage != .over { over(r) }
            return
        }

        if started {
            if stage != .battle {
                stage = .battle
                hadBattle = true
                Sound.track("boss")
                Feedback.announce("The battle begins!")
            }
            let mine = (r["turn"] as? String) == myId
            if mine && !myTurn { Feedback.announce("Your turn! Attack, Heavy Attack, Skill, Defend or Taunt.") }
            myTurn = mine
            return
        }

        if roomStatus == "full" {
            if hadBattle && stage != .room {
                // The web version also said this when an opponent first joined.
                stage = .room
                readyPressed = false
                myTurn = false
                say("Your opponent wants a rematch! Press Ready when you are prepared to fight again.")
            } else if let them = fighters.first(where: { !$0.isMe }), status.hasPrefix("Room created") {
                say("\(them.name) the \(them.cls) joined. Press Ready when prepared to fight!")
            }
        }
    }

    /// mpReady
    func ready() {
        guard let role, let ref = room else { Feedback.announce("Not in a room."); return }
        readyPressed = true
        ref.child(role).child("ready").setValue(true)
        Sound.sfx("sfx-confirm")
        say("Ready! Waiting for opponent...")
    }

    // MARK: Fighting

    enum Action: String { case attack, heavy, skill, defend, taunt }

    /// mpAction: reads the room, works out the hit, writes both fighters,
    /// the log and the next turn back, like the web version.
    func act(_ action: Action) {
        guard myTurn else { status = "Not your turn!"; Sound.sfx("sfx-select"); return }
        guard let role, let ref = room, let ch = character else { return }
        if action == .skill && mySp < 5 { Feedback.announce("Not enough SP. A skill costs 5."); return }
        myTurn = false
        let other = role == "p1" ? "p2" : "p1"
        ref.observeSingleEvent(of: .value, with: { [weak self] snap in
            let value = snap.value as? [String: Any]
            Task { @MainActor in
                guard let self, let r = value, var me = r[role] as? [String: Any], var them = r[other] as? [String: Any] else { return }
                let atk = GameData.classInfo(ch.cls).atk
                let dmg = Int.random(in: atk)
                let theyDefend = (them["defending"] as? Bool) ?? false
                let myName = (me["name"] as? String) ?? ch.name
                var theirHp = (them["hp"] as? NSNumber)?.intValue ?? 0
                func hit(_ d: Int) -> Int { theyDefend ? d * 4 / 10 : d }
                var line = ""
                switch action {
                case .attack:
                    let f = hit(dmg)
                    theirHp = max(0, theirHp - f)
                    line = "⚔️ \(myName) attacks for \(f) damage!\(theyDefend ? " (blocked!)" : "")"
                case .heavy:
                    let f = hit(dmg * 18 / 10)
                    theirHp = max(0, theirHp - f)
                    line = "💥 \(myName) heavy strikes for \(f)!"
                case .skill:
                    let f = hit(dmg * 2)
                    theirHp = max(0, theirHp - f)
                    me["sp"] = max(0, ((me["sp"] as? NSNumber)?.intValue ?? 0) - 5)
                    line = "✨ \(myName) uses a skill for \(f) damage!"
                case .defend:
                    me["defending"] = true
                    line = "🛡️ \(myName) braces for the next hit."
                case .taunt:
                    line = "😤 \(myName) taunts: \"You have been defeated!\""
                }
                if action != .defend {
                    me["defending"] = false
                    them["defending"] = false
                }
                them["hp"] = theirHp
                var lines = Self.logLines(r["log"])
                lines.append(line)
                var updates: [String: Any] = [role: me, other: them]
                if theirHp <= 0 {
                    them["alive"] = false
                    updates[other] = them
                    lines.append("💀 \((them["name"] as? String) ?? "Your opponent") has been defeated!")
                    updates["status"] = "over"
                    updates["winnerId"] = self.myId
                    updates["winnerName"] = myName
                    updates["loserName"] = them["name"] ?? "Your opponent"
                } else {
                    updates["turn"] = them["id"] ?? ""
                }
                updates["log"] = Array(lines.suffix(30))
                // Our own line is read out here, not again when it comes back.
                self.lastLog = Array(lines.suffix(30))
                Feedback.announce(line)
                ref.updateChildValues(updates)
                Sound.sfx(action == .attack ? "sfx-attack" : action == .heavy ? "sfx-heavy-hit" : action == .skill ? "sfx-crit" : "sfx-select")
            }
        }, withCancel: { [weak self] _ in
            Task { @MainActor in
                self?.myTurn = true
                self?.say("Action failed — check your connection and try again.")
            }
        })
    }

    /// mpEmote
    func emote(_ text: String) {
        guard let ref = room?.child("log") else { return }
        let name = character?.name ?? "Player"
        ref.observeSingleEvent(of: .value) { snap in
            var lines = Self.logLines(snap.value)
            lines.append("💬 \(name): \(text)")
            ref.setValue(lines)
        }
        Sound.sfx("sfx-select")
    }

    /// mpHandleBattleOver. The web version told you that you'd lost when your
    /// opponent left mid-battle; leaving now counts as their loss.
    private func over(_ r: [String: Any]) {
        stage = .over
        myTurn = false
        Sound.track("menu")
        if (r["opponentLeft"] as? Bool) == true && r["winnerId"] == nil {
            Sound.sfx("sfx-victory")
            say("Your opponent left the arena. You win!")
        } else if (r["winnerId"] as? String) == myId {
            Sound.sfx("sfx-victory")
            say("🏆 YOU WIN! \((r["loserName"] as? String) ?? "Your opponent") has been defeated!")
        } else {
            Sound.sfx("sfx-gameover")
            say("💀 You have been defeated by \((r["winnerName"] as? String) ?? "your opponent")...")
        }
    }

    /// mpRematch: both entries go back to the pre-battle shape, full health.
    func rematch() {
        guard let role, let ref = room, let ch = character else { return }
        let other = role == "p1" ? "p2" : "p1"
        ref.observeSingleEvent(of: .value) { [weak self] snap in
            let value = snap.value as? [String: Any]
            Task { @MainActor in
                guard let self, let r = value else { return }
                var updates: [String: Any] = [
                    role: ["id": self.myId, "char": self.charData(ch), "ready": false],
                    "status": "full", "battleStarted": false, "turn": NSNull(),
                    "log": ["🔄 Rematch requested! Both players press Ready to begin."],
                    "winnerId": NSNull(), "winnerName": NSNull(), "loserName": NSNull(),
                ]
                if let e = r[other] as? [String: Any] {
                    var c = (e["char"] as? [String: Any]) ?? e
                    c["hp"] = c["maxHp"] ?? 100
                    c["sp"] = c["maxSp"] ?? 20
                    c["alive"] = true
                    c["defending"] = false
                    c["id"] = nil
                    c["ready"] = nil
                    updates[other] = ["id": e["id"] ?? "", "char": c, "ready": false]
                }
                ref.updateChildValues(updates)
            }
        }
        stage = .room
        readyPressed = false
        myTurn = false
        hadBattle = false
        Sound.sfx("sfx-confirm")
        say("Rematch! Press Ready when you are prepared to fight again.")
    }

    /// mpLeave: an unstarted or finished room is removed; mid-battle the
    /// opponent is told you left.
    func leave() {
        if let ref = room {
            if let h = handle { ref.removeObserver(withHandle: h) }
            ref.observeSingleEvent(of: .value) { snap in
                guard let r = snap.value as? [String: Any] else { return }
                if !((r["battleStarted"] as? Bool) ?? false) || r["status"] as? String == "over" {
                    ref.removeValue()
                } else {
                    ref.updateChildValues(["status": "over", "opponentLeft": true])
                }
            }
        }
        handle = nil
        code = nil
        role = nil
        stage = .lobby
    }

    private static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }
}
