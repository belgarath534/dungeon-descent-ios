import SwiftUI
import FirebaseDatabase
import DungeonCore

/// CO-OP DUNGEON online (the rules are Coop.swift). The room is
/// "pvp_rooms/coop_CODE": the host's device runs the fight and writes it;
/// everyone (host included) sends their choice to "actions/{id}" and reads
/// every new line of the log aloud. The web version (js/31-coop.js) uses the
/// same room, so web and app players play together.
@MainActor
final class CoopModel: ObservableObject {
    enum Stage { case choose, lobby, playing, over }

    @Published var stage: Stage = .choose
    @Published var status = ""
    @Published private(set) var code: String?
    @Published private(set) var isHost = false
    @Published private(set) var party: [Coop.Player] = []
    @Published private(set) var foe: Coop.Foe?
    @Published private(set) var floor = 1
    @Published private(set) var dungeon = ""
    @Published private(set) var roomStatus = "lobby"
    @Published private(set) var myAction: Coop.Action?
    @Published private(set) var waitingOn: [String] = []
    @Published private(set) var log: [String] = []

    let myId = "c" + String((0..<9).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
    private(set) var character: PlayerCharacter?
    weak var game: GameModel?
    private var handle: DatabaseHandle?
    private var seenLog = Set<String>()
    private var round = 0
    private var roundStart = 0.0
    private var actions: [String: String] = [:]
    private var hostId = ""
    private var resolving = false
    private var timer: Timer?
    private var beats: [String: Double] = [:]
    private var rewarded = false
    private var dice = SystemDice()

    private var room: DatabaseReference? {
        code.map { Database.database().reference(withPath: "pvp_rooms").child("coop_" + $0) }
    }
    static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    private func say(_ text: String) {
        status = text
        Feedback.announce(text)
    }

    var me: Coop.Player? { party.first { $0.id == myId } }

    // MARK: Lobby

    func host(_ ch: PlayerCharacter, dungeon: String) {
        character = ch
        let c = Coop.code(dice: &dice)
        code = c
        isHost = true
        hostId = myId
        let p = Coop.player(ch, id: myId, platform: CloudAccount.platform)
        var pd = p.dict
        pd["joinedAt"] = Self.now
        let data: [String: Any] = [
            "kind": "coop", "code": c, "status": "lobby", "host": myId, "dungeon": dungeon,
            "floor": 1, "round": 0, "createdAt": Self.now, "players": [myId: pd], "beat": [myId: Self.now],
        ]
        room?.setValue(data) { [weak self] error, ref in
            Task { @MainActor in
                guard let self else { return }
                if error != nil { self.say("Couldn't create the room. Check your connection."); return }
                self.stage = .lobby
                Sound.sfx("sfx-confirm")
                self.say("Room created. Your code is \(c.map(String.init).joined(separator: " ")). Share it with up to three friends, then press Start when everyone is ready.")
                self.listen()
            }
        }
    }

    func join(_ raw: String, _ ch: PlayerCharacter) {
        let c = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard c.count == 4 else { say("Enter the 4 character room code."); return }
        character = ch
        code = c
        room?.observeSingleEvent(of: .value, with: { [weak self] snap in
            Task { @MainActor in
                guard let self else { return }
                guard let r = snap.value as? [String: Any], r["kind"] as? String == "coop" else {
                    self.code = nil
                    self.say("No co-op room with that code. Check it and try again.")
                    return
                }
                let players = r["players"] as? [String: Any] ?? [:]
                guard r["status"] as? String == "lobby" else { self.code = nil; self.say("That run has already started."); return }
                guard players.count < Coop.maxPlayers else { self.code = nil; self.say("That room is full."); return }
                var pd = Coop.player(ch, id: self.myId, platform: CloudAccount.platform).dict
                pd["joinedAt"] = Self.now
                self.room?.child("players").child(self.myId).setValue(pd)
                self.room?.child("beat").child(self.myId).setValue(Self.now)
                self.stage = .lobby
                Sound.sfx("sfx-confirm")
                self.say("Joined room \(c). Press Ready when you're set. The host starts the run.")
                self.listen()
            }
        }, withCancel: { [weak self] _ in
            Task { @MainActor in self?.say("Couldn't reach the room. Check your connection.") }
        })
    }

    func ready() {
        room?.child("players").child(myId).child("ready").setValue(true)
        Sound.sfx("sfx-select")
        say("Ready.")
    }

    /// The host starts the run once everyone is ready.
    func start() {
        guard isHost else { return }
        guard party.allSatisfy({ $0.ready || $0.id == myId }) else {
            say("Waiting for " + party.filter { !$0.ready && $0.id != myId }.map(\.name).joined(separator: ", ") + " to be ready.")
            return
        }
        let f = Coop.foe(dungeon: dungeon, floor: 1, party: party, dice: &dice)
        room?.updateChildValues(["status": "playing", "floor": 1, "round": 1, "roundStart": Self.now, "foe": f.dict])
        addLog(["⚔ The party descends into \(dungeon). Floor 1: \(f.icon) \(f.name) blocks the way, \(f.hp) HP."])
    }

    func leave() {
        if isHost, ["lobby", "playing"].contains(roomStatus) { room?.child("status").setValue("closed") }
        else if roomStatus == "lobby" { room?.child("players").child(myId).removeValue() }
        stop()
        stage = .choose
        code = nil
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let h = handle { room?.removeObserver(withHandle: h) }
        handle = nil
    }

    // MARK: Playing

    func act(_ a: Coop.Action) {
        guard roomStatus == "playing", let m = me, m.alive, myAction == nil else { return }
        if a == .potion && m.potions <= 0 { say("No potions left."); return }
        myAction = a
        room?.child("actions").child(myId).setValue(a.rawValue)
        Sound.sfx(a == .potion ? "sfx-potion" : a == .defend ? "sfx-select" : "sfx-attack")
        Feedback.announce("\(a.label.dropFirst(2)) chosen. Waiting for the party.")
    }

    private func addLog(_ lines: [String]) {
        guard let ref = room?.child("log") else { return }
        for l in lines { ref.childByAutoId().setValue(["text": l, "t": Self.now]) }
    }

    private func listen() {
        guard let ref = room else { return }
        stop()
        handle = ref.observe(.value) { [weak self] snap in
            let value = snap.value as? [String: Any]
            Task { @MainActor in self?.received(value) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func received(_ r: [String: Any]?) {
        guard let r else {
            if stage != .choose { say("The room is gone.") }
            stage = .over
            stop()
            return
        }
        hostId = r["host"] as? String ?? hostId
        dungeon = r["dungeon"] as? String ?? dungeon
        let newFloor = (r["floor"] as? NSNumber)?.intValue ?? floor
        if newFloor != floor && newFloor >= Coop.floors && roomStatus == "playing" {
            Sound.track(Soundtrack.bossTrack(dungeon: dungeon))
        }
        floor = newFloor
        let newRound = (r["round"] as? NSNumber)?.intValue ?? 0
        if newRound != round { round = newRound; myAction = nil }
        roundStart = (r["roundStart"] as? NSNumber)?.doubleValue ?? roundStart
        let players = (r["players"] as? [String: Any] ?? [:]).compactMap { (_, v) -> (Coop.Player, Double)? in
            guard let d = v as? [String: Any], let p = Coop.Player(d) else { return nil }
            return (p, (d["joinedAt"] as? NSNumber)?.doubleValue ?? 0)
        }.sorted { $0.1 < $1.1 }.map(\.0)
        let before = Set(party.map(\.id))
        party = players
        for p in players where !before.contains(p.id) && !before.isEmpty && p.id != myId && stage == .lobby {
            Feedback.announce("\(p.name) joined the party.")
        }
        foe = Coop.Foe(r["foe"] as? [String: Any])
        actions = (r["actions"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        if let a = actions[myId] { myAction = Coop.Action(rawValue: a) }
        waitingOn = party.filter { $0.alive && actions[$0.id] == nil }.map(\.name)
        beats = (r["beat"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        // New lines, in order, read aloud.
        let entries = (r["log"] as? [String: Any] ?? [:]).sorted { $0.key < $1.key }
        var fresh: [String] = []
        for (k, v) in entries where !seenLog.contains(k) {
            seenLog.insert(k)
            if let t = (v as? [String: Any])?["text"] as? String { fresh.append(t) }
        }
        if !fresh.isEmpty {
            log = (fresh.reversed() + log).prefix(40).map { $0 }
            Feedback.announce(fresh.joined(separator: " "))
        }
        let st = r["status"] as? String ?? "lobby"
        if st != roomStatus {
            roomStatus = st
            switch st {
            case "playing":
                stage = .playing
                Sound.track(Soundtrack.battleTrack(dungeon: dungeon))
            case "won", "lost":
                stage = .over
                payOut(won: st == "won")
            case "closed":
                stage = .over
                say("The host ended the run.")
                payOut(won: false)
            default: break
            }
        }
        if isHost { hostStep() }
    }

    private func tick() {
        room?.child("beat").child(myId).setValue(Self.now)
        if isHost { hostStep() }
        // The host's device went quiet: the run can't go on.
        if !isHost, ["lobby", "playing"].contains(roomStatus), let hb = beats[hostId], Self.now - hb > 60_000 {
            roomStatus = "closed"
            stage = .over
            say("The host left, so the run is over.")
            payOut(won: false)
            stop()
        }
    }

    // MARK: The host runs the fight

    private func hostStep() {
        guard isHost, roomStatus == "playing", !resolving, var f = foe, f.hp > 0, round > 0 else { return }
        let standing = party.filter(\.alive)
        let allIn = standing.allSatisfy { actions[$0.id] != nil }
        let timedOut = Self.now - roundStart > Coop.roundSeconds * 1000
        guard allIn || timedOut else { return }
        resolving = true
        let acts = actions.compactMapValues { Coop.Action(rawValue: $0) }
        let r = Coop.resolve(party: party, foe: f, actions: acts, dice: &dice)
        f = r.foe
        var lines = r.lines
        if timedOut && !allIn { lines.insert("⏱ Time's up — anyone who hadn't chosen attacks.", at: 0) }
        var update: [String: Any] = ["foe": f.dict, "actions": NSNull()]
        for p in r.party { update["players/\(p.id)/hp"] = p.hp; update["players/\(p.id)/potions"] = p.potions }
        if r.foeDown {
            if floor >= Coop.floors {
                lines.append("👑 \(f.name) is defeated! The party has conquered \(dungeon)!")
                update["status"] = "won"
            } else {
                lines.append("✨ Floor \(floor) cleared! Everyone heals, and the fallen get back up.")
                update["round"] = 0
                let next = floor + 1
                let rested = Coop.rest(r.party)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, self.roomStatus == "playing" else { return }
                    let nf = Coop.foe(dungeon: self.dungeon, floor: next, party: rested, dice: &self.dice)
                    var u: [String: Any] = ["floor": next, "round": 1, "roundStart": Self.now, "foe": nf.dict]
                    for p in rested { u["players/\(p.id)/hp"] = p.hp }
                    self.room?.updateChildValues(u)
                    self.addLog([nf.boss
                        ? "👑 Floor \(next): the boss, \(nf.icon) \(nf.name), \(nf.hp) HP. This is it."
                        : "⬇ Floor \(next): \(nf.icon) \(nf.name), \(nf.hp) HP."])
                }
            }
        } else if r.partyDown {
            lines.append("💀 The whole party has fallen on floor \(floor).")
            update["status"] = "lost"
        } else {
            update["round"] = round + 1
            update["roundStart"] = Self.now
        }
        room?.updateChildValues(update) { [weak self] _, _ in
            Task { @MainActor in self?.resolving = false }
        }
        addLog(lines)
    }

    // MARK: Rewards, on each player's own device

    private func payOut(won: Bool) {
        guard !rewarded, let game else { return }
        rewarded = true
        let cleared = won ? Coop.floors : max(0, floor - 1)
        let gold = Coop.gold(floorsCleared: cleared, won: won)
        if gold > 0 { game.wallet.addGold(gold) }
        if cleared > 0 {
            game.pass(.kill(elite: false, boss: false), times: won ? cleared - 1 : cleared)
            game.pass(.floor, times: cleared)
        }
        if won {
            game.pass(.kill(elite: false, boss: true))
            game.pass(.dungeonCleared)
            Sound.sfx("sfx-victory")
        }
        Sound.track("menu")
        game.refresh()
        let text = won
            ? "Victory! The party cleared all \(Coop.floors) floors. You earn \(gold) gold."
            : cleared > 0 ? "The run is over after \(cleared) floor\(cleared == 1 ? "" : "s"). You earn \(gold) gold." : "The run is over."
        status = text
        Feedback.announce(text, after: 1.5)
        // The host tidies up the room a little later.
        if isHost { let ref = room; DispatchQueue.main.asyncAfter(deadline: .now() + 120) { ref?.removeValue() } }
    }
}
