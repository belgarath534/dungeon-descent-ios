import SwiftUI
import FirebaseDatabase
import DungeonCore

/// CO-OP 2.0 online (the rules are Coop.swift). The room is
/// "pvp_rooms/coop_CODE", kind "coop2": the host's device runs the fight and writes it;
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
    /// Which fight of the floor (1 or 2), and the merchant between floors.
    @Published private(set) var fight = 1
    @Published private(set) var shopOpen = false
    @Published private(set) var bought = 0
    @Published private(set) var waitingOn: [String] = []
    /// The newest first; each line keeps its number, so VoiceOver focus on
    /// a line stays put when new lines arrive.
    @Published private(set) var log: [(n: Int, text: String)] = []
    private var logCount = 0

    let myId = "c" + String((0..<9).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
    private(set) var character: PlayerCharacter?
    weak var game: GameModel?
    private var handle: DatabaseHandle?
    private var seenLog = Set<String>()
    private var round = 0
    private var roundStart = 0.0
    private var actions: [String: String] = [:]
    private var buys: [String: Int] = [:]
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

    /// A fresh run: nothing left from the last room. (After Play Again, the
    /// next run paid nothing: "rewarded" was still set from the first.)
    private func resetRun() {
        rewarded = false
        roomStatus = "lobby"
        party = []
        foe = nil
        floor = 1
        round = 0
        actions = [:]
        myAction = nil
        fight = 1
        shopOpen = false
        bought = 0
        buys = [:]
        waitingOn = []
        log = []
        seenLog = []
        status = ""
    }

    /// Your co-op self: the run your character would start a dungeon with
    /// (gear, Legacy level, spent level points, prestige stars) and your gun.
    private func makePlayer(_ ch: PlayerCharacter) -> Coop.Player {
        var run = Run(character: ch)
        if let game {
            game.globalInventory.load(into: &run)
            _ = Legacy.start(&run, ch)
            if run.level > 1 { Progression.restore(&run, Progression.savedSpend(ch)) }
            _ = Prestige.start(&run, ch)
            return Coop.player(run, character: ch, id: myId, platform: CloudAccount.platform, gun: Guns.equipped(game.store))
        }
        return Coop.player(run, character: ch, id: myId, platform: CloudAccount.platform)
    }

    func host(_ ch: PlayerCharacter, dungeon: String) {
        resetRun()
        character = ch
        let c = Coop.code(dice: &dice)
        code = c
        isHost = true
        hostId = myId
        let p = makePlayer(ch)
        var pd = p.dict
        pd["joinedAt"] = Self.now
        let data: [String: Any] = [
            "kind": Coop.kind, "version": 2, "code": c, "status": "lobby", "host": myId, "dungeon": dungeon,
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
        resetRun()
        character = ch
        code = c
        room?.observeSingleEvent(of: .value, with: { [weak self] snap in
            Task { @MainActor in
                guard let self else { return }
                guard let r = snap.value as? [String: Any], r["kind"] as? String == Coop.kind else {
                    self.code = nil
                    if (snap.value as? [String: Any])?["kind"] as? String == "coop" {
                        self.say("That room is from an older version of Dungeon Descent. Ask the host to update, then make a new room.")
                    } else {
                        self.say("No co-op room with that code. Check it and try again.")
                    }
                    return
                }
                let players = r["players"] as? [String: Any] ?? [:]
                guard r["status"] as? String == "lobby" else { self.code = nil; self.say("That run has already started."); return }
                guard players.count < Coop.maxPlayers else { self.code = nil; self.say("That room is full."); return }
                var pd = self.makePlayer(ch).dict
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
        room?.updateChildValues(["status": "playing", "floor": 1, "fight": 1, "round": 1, "roundStart": Self.now, "foe": f.dict])
        addLog(["⚔ The party descends into \(dungeon). Floor 1, fight 1 of \(Coop.fightsPerFloor): \(f.icon) \(f.name) blocks the way, \(f.hp) HP."])
    }

    func leave() {
        if isHost, ["lobby", "playing"].contains(roomStatus) { room?.child("status").setValue("closed") }
        else if roomStatus == "lobby" { room?.child("players").child(myId).removeValue() }
        stop()
        // Out of a fight and back to the tavern.
        if stage == .playing || stage == .over { Sound.track("tavern") }
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
        guard roomStatus == "playing", !shopOpen, let m = me, m.alive, myAction == nil else { return }
        switch a {
        case .potion where m.potions <= 0, .revive where m.potions <= 0: say("No potions left."); return
        case .gun where m.shots <= 0: say("Your gun is empty until the next fight."); return
        case .skill(let id):
            guard let s = m.skills.first(where: { $0.id == id }) else { return }
            if m.sp < s.sp { say("Not enough SP: \(s.name) needs \(s.sp), you have \(m.sp).") ; return }
        default: break
        }
        myAction = a
        room?.child("actions").child(myId).setValue(a.raw)
        Sound.sfx(a == .potion ? "sfx-potion" : a == .defend ? "sfx-select" : "sfx-attack")
        Feedback.announce("\(name(of: a)) chosen. Waiting for the party.")
    }

    /// What an action is called, for the buttons and VoiceOver.
    func name(of a: Coop.Action) -> String {
        switch a {
        case .attack: return "Attack"
        case .heavy: return "Heavy strike"
        case .defend: return "Defend"
        case .potion: return "Potion"
        case .gun: return me?.gunName.isEmpty == false ? "Fire \(me!.gunName)" : "Fire your gun"
        case .skill(let id): return me?.skills.first { $0.id == id }?.name ?? "Skill"
        case .revive(let id): return "Revive \(party.first { $0.id == id }?.name ?? "a friend")"
        case .protect(let id): return "Protect \(party.first { $0.id == id }?.name ?? "a friend")"
        }
    }

    /// The merchant between floors: a potion for your own gold, added when
    /// the next floor starts.
    func buyPotion() {
        guard shopOpen, let game, let m = me else { return }
        guard m.potions + bought < Coop.maxPotions else { say("You can carry \(Coop.maxPotions) potions."); return }
        guard game.wallet.spendGold(Coop.potionPrice) else { say("Not enough gold. A potion is \(Coop.potionPrice) gold, you have \(game.wallet.gold).") ; return }
        bought += 1
        room?.child("buys").child(myId).setValue(bought)
        game.refresh()
        Sound.sfx("sfx-purchase")
        say("Potion bought for \(Coop.potionPrice) gold. You'll have \(m.potions + bought). \(game.wallet.gold) gold left.")
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
        if newRound != round {
            round = newRound; myAction = nil
            if stage == .playing, me?.alive == true { WatchBridge.shared.alert(.coopTurn, "Your move in co-op — floor \(floor).") }
        }
        roundStart = (r["roundStart"] as? NSNumber)?.doubleValue ?? roundStart
        let newFight = max(1, (r["fight"] as? NSNumber)?.intValue ?? 1)
        if fight != newFight { fight = newFight }
        let shop = r["shop"] as? Bool ?? false
        if shop != shopOpen {
            shopOpen = shop
            if !shop { bought = 0 }
        }
        buys = (r["buys"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.intValue }
        let players = (r["players"] as? [String: Any] ?? [:]).compactMap { (_, v) -> (Coop.Player, Double)? in
            guard let d = v as? [String: Any], let p = Coop.Player(d) else { return nil }
            return (p, (d["joinedAt"] as? NSNumber)?.doubleValue ?? 0)
        }.sorted { $0.1 < $1.1 }.map(\.0)
        let before = Set(party.map(\.id))
        // Only what changed is set again: the room updates every few seconds
        // (each player's heartbeat), and redrawing unchanged views made
        // VoiceOver lose its place.
        if party != players { party = players }
        for p in players where !before.contains(p.id) && !before.isEmpty && p.id != myId && stage == .lobby {
            Feedback.announce("\(p.name) joined the party.")
        }
        let newFoe = Coop.Foe(r["foe"] as? [String: Any])
        if foe != newFoe { foe = newFoe }
        actions = (r["actions"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        if let a = actions[myId], myAction != Coop.Action(a) { myAction = Coop.Action(a) }
        let waiting = party.filter { $0.alive && actions[$0.id] == nil }.map(\.name)
        if waitingOn != waiting { waitingOn = waiting }
        beats = (r["beat"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        // New lines, in order, read aloud.
        let entries = (r["log"] as? [String: Any] ?? [:]).sorted { $0.key < $1.key }
        var fresh: [String] = []
        for (k, v) in entries where !seenLog.contains(k) {
            seenLog.insert(k)
            if let t = (v as? [String: Any])?["text"] as? String { fresh.append(t) }
        }
        if !fresh.isEmpty {
            let numbered = fresh.map { t -> (n: Int, text: String) in logCount += 1; return (logCount, t) }
            log = Array((numbered.reversed() + log).prefix(40))
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
        guard isHost, roomStatus == "playing", !resolving, !shopOpen, var f = foe, f.hp > 0, round > 0 else { return }
        let standing = party.filter(\.alive)
        let allIn = standing.allSatisfy { actions[$0.id] != nil }
        let timedOut = Self.now - roundStart > Coop.roundSeconds * 1000
        guard allIn || timedOut else { return }
        resolving = true
        let r = Coop.resolve(party: party, foe: f, actions: actions, dice: &dice)
        f = r.foe
        var lines = r.lines
        if timedOut && !allIn { lines.insert("⏱ Time's up — anyone who hadn't chosen attacks.", at: 0) }
        var update: [String: Any] = ["foe": f.dict, "actions": NSNull()]
        write(r.party, into: &update)
        if r.foeDown {
            if floor >= Coop.floors {
                lines.append("👑 \(f.name) is defeated! The party has conquered \(dungeon)!")
                update["status"] = "won"
            } else if fight < Coop.fightsPerFloor {
                // The next fight on this floor, after a short breath.
                lines.append("✨ Fight won! Everyone catches their breath and heals a little.")
                update["round"] = 0
                let rested = Coop.rest(r.party, floor: false)
                let nextFight = fight + 1, fl = floor
                after(3) { [weak self] in
                    guard let self else { return }
                    self.startFight(floor: fl, fight: nextFight, party: rested)
                }
            } else {
                // Floor cleared: the merchant opens for 15 seconds.
                lines.append("✨ Floor \(floor) cleared! Everyone heals, and the fallen get back up.")
                lines.append("🛒 The merchant is here for 15 seconds: potions are \(Coop.potionPrice) gold each, with your own gold.")
                update["round"] = 0
                update["shop"] = true
                let rested = Coop.rest(r.party, floor: true)
                write(rested, into: &update)
                let next = floor + 1
                after(15) { [weak self] in
                    guard let self else { return }
                    var party = self.party
                    for i in party.indices {
                        let n = self.buys[party[i].id] ?? 0
                        party[i].potions = min(Coop.maxPotions, party[i].potions + n)
                    }
                    self.room?.updateChildValues(["shop": false, "buys": NSNull()])
                    self.startFight(floor: next, fight: 1, party: party)
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

    /// The players' changing numbers, as room paths.
    private func write(_ players: [Coop.Player], into u: inout [String: Any]) {
        for p in players {
            for (k, v) in ["hp": p.hp, "potions": p.potions, "sp": p.sp, "shield": p.shield, "shots": p.shots, "dealt": p.dealt] {
                u["players/\(p.id)/\(k)"] = v
            }
        }
    }

    private func after(_ seconds: Double, _ f: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.roomStatus == "playing" else { return }
                f()
            }
        }
    }

    /// The host sets up a fight: its enemy and everyone's numbers.
    private func startFight(floor next: Int, fight n: Int, party: [Coop.Player]) {
        let nf = Coop.foe(dungeon: dungeon, floor: next, party: party, dice: &dice)
        var u: [String: Any] = ["floor": next, "fight": n, "round": 1, "roundStart": Self.now, "foe": nf.dict]
        write(party, into: &u)
        room?.updateChildValues(u)
        addLog([nf.boss
            ? "👑 Floor \(next): the boss, \(nf.icon) \(nf.name), \(nf.hp) HP. It changes when it's hurt. This is it."
            : "⬇ Floor \(next), fight \(n) of \(Coop.fightsPerFloor): \(nf.icon) \(nf.name)\(nf.elite ? ", an elite," : ""), \(nf.hp) HP."])
    }

    // MARK: Rewards, on each player's own device

    private func payOut(won: Bool) {
        guard !rewarded, let game else { return }
        rewarded = true
        let cleared = won ? Coop.floors : max(0, floor - 1)
        let gold = Coop.gold(floorsCleared: cleared, won: won)
        if gold > 0 { game.wallet.addGold(gold) }
        // XP for your real level, on the Endless Descent curve (never lower).
        let xp = Coop.xp(floorsCleared: cleared, won: won)
        var levelLine = ""
        if xp > 0, let ch = character, let i = game.characters.firstIndex(where: { $0.created == ch.created }) {
            game.updateCharacter(i) { c in
                var level = max(1, c.persistLevel ?? 1)
                var have: Int = { if case .number(let n)? = c.extra["persistXp"] { return Int(n) }; return 0 }() + xp
                let start = level
                while let need = AFKRun.xpToLevelUp(from: level), have >= need { have -= need; level += 1 }
                if level >= AFKRun.maxLevel { have = 0 }
                c.persistLevel = level
                c.extra["persistXp"] = .number(Double(have))
                if level > start { levelLine = " \(c.name) reaches level \(level)!" }
            }
        }
        if cleared > 0 {
            game.pass(.kill(elite: false, boss: false), times: won ? cleared - 1 : cleared)
            game.pass(.floor, times: cleared)
        }
        if won {
            game.pass(.kill(elite: false, boss: true))
            game.pass(.dungeonCleared)
            Sound.sfx("sfx-victory")
        }
        Sound.track("tavern")
        game.refresh()
        let text = won
            ? "Victory! The party cleared all \(Coop.floors) floors. You earn \(gold) gold and \(xp) XP.\(levelLine)"
            : cleared > 0 ? "The run is over after \(cleared) floor\(cleared == 1 ? "" : "s"). You earn \(gold) gold and \(xp) XP.\(levelLine)" : "The run is over."
        status = text
        Feedback.announce(text, after: 1.5)
        // The host tidies up the room a little later.
        if isHost { let ref = room; DispatchQueue.main.asyncAfter(deadline: .now() + 120) { ref?.removeValue() } }
    }
}
