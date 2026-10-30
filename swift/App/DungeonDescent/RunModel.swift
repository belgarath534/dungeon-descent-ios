import SwiftUI
import DungeonCore

/// One dungeon run in progress. Saved after every action so it survives the
/// app being closed. Special room events, skills and spirits come later
/// (see swift/MIGRATION.md).
@MainActor
final class RunModel: ObservableObject {
    enum Phase: Equatable {
        case exploring
        case fighting
        case floorCleared
        case shopping
        case event
        case victory
        case defeat
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var run: Run
    @Published private(set) var phase: Phase = .exploring
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var roomTitle = ""
    @Published private(set) var roomText = ""
    @Published private(set) var shop: [Inventory.ShopItem] = []
    /// The room's event box (setEvent): what just happened, and its tone.
    @Published private(set) var eventText = ""
    @Published private(set) var eventTone = ""
    /// Set on a level-up until the player leaves the Level Up panel.
    @Published var levelUp: Int?
    /// The death cinematic shows before the run summary.
    @Published var showingDeathCinematic = false
    /// Floor stats as they were when the floor was finished.
    @Published private(set) var floorSummary = FloorStats()
    private var movePrefix = ""

    private let game: GameModel
    private let characterIndex: Int
    private var dice = SystemDice()

    init(game: GameModel, characterIndex: Int, resume: Bool) {
        self.game = game
        self.characterIndex = characterIndex
        if resume, let saved = game.savedRun(for: characterIndex) {
            run = saved
            phase = saved.inCombat ? .fighting
                : saved.pendingEvent != nil ? .event
                // A boss floor is never "cleared" outside a fight: past the
                // Elite Guardian, the boss is still to come.
                : saved.roomsOnFloor >= saved.floorRoomsNeeded && saved.roomsOnFloor > 0
                    && !(saved.floor >= Challenges.bossFloor(saved) && saved.difficulty != .endless) ? .floorCleared : .exploring
            roomTitle = Rooms.floorName(saved.floor, dungeon: saved.dungeon)
            add("Run resumed on floor \(saved.floor). HP \(saved.hp) of \(saved.maxHp).")
            if let e = saved.enemy, Medusa.isMedusa(e), e.isDead { medusaChoice = true }
            if let e = saved.enemy, TimeDescender.isClock(e), saved.inCombat {
                if TimeDescender.hasChronoArmor(saved) { clockWindow = true } else { clockCycle(after: 3) }
            }
            if let dir = ShadowEvents.securityDirection(saved.pendingEvent) {
                DispatchQueue.main.async { [weak self] in self?.startSecurityRoom(dir) }
            }
            bountyBanner = Bounties.banner(game.store)
            startForest()
            if let h = saved.hunter {
                add(Hunter.line(h.dist))
                startHeartbeat(h.dist)
                hunterChoice = h.dist <= 2 && phase != .fighting
            }
            playMusic()
            return
        }
        run = Self.newRun(game, characterIndex)
        begin()
    }

    /// A fresh run for the character: start bonuses, saved items and gear,
    /// starting skill and the first floor's plan (initDungeon).
    /// A Challenge to start instead of a normal run (set by the Challenges screen).
    enum Challenge { case gauntlet, daily }
    static var pendingChallenge: Challenge? = nil

    private static func newRun(_ game: GameModel, _ index: Int) -> Run {
        var r = Run(character: game.characters[index], gold: game.wallet.gold)
        // Challenges run in their own dungeon without moving the character
        // there, so nothing has to be put back afterwards.
        // Endless has no boss, so a Challenge could never end: it runs on Wanderer.
        if pendingChallenge != nil && r.difficulty == .endless {
            r.difficulty = .wanderer
            r.lives = GameData.Difficulty.wanderer.lives
            r.maxLives = r.lives
        }
        if pendingChallenge != nil && r.floor != 1 {
            r.floor = 1
            var cd = SystemDice()
            r.floorRoomsNeeded = Rooms.roomsNeeded(floor: 1, difficulty: r.difficulty, dice: &cd)
        }
        switch pendingChallenge {
        case .gauntlet:
            r.dungeon = Challenges.gauntlet[0]
            r.gauntletStage = 0
            r.lives = 1
            r.maxLives = 1
        case .daily:
            let daily = Challenges.daily()
            r.dungeon = daily.dungeon
            r.dailyMods = daily.mods.map(\.id)
            r.dailyKey = daily.key
            r.dailyStart = Date().timeIntervalSince1970
        case nil: break
        }
        pendingChallenge = nil
        // Saved items first: loading them replaces the bag, so everything
        // else that adds items (seasonal shop, Coin Shop) goes in after.
        game.globalInventory.load(into: &r)
        r.applyStartBonuses(wallet: game.wallet)
        r.startNotes += Races.start(&r, classTraits: AppSettings.classTraits, wallet: game.wallet)
        if let dc = DailyChallenge.start(&r, store: game.store, wallet: game.wallet) { r.startNotes.append(dc) }
        if let t = ClassTraits.start(&r, classTraits: AppSettings.classTraits) { r.startNotes.append(t) }
        r.applyMilestoneBuffs(game.milestoneEffects)
        r.event = Events.active()
        r.startNotes += Events.applyNextRun(&r, store: game.store)
        let brewed = Alchemy.collect(into: &r, store: game.store)
        if brewed > 0 { r.startNotes.append("🧪 \(brewed) crafted potion\(brewed == 1 ? "" : "s") from your Alchemy Table added to inventory.") }
        // Home: the active minion fights beside you, the bed is ready again,
        // and last night's dream buff applies once.
        r.minion = Home.activeMinion(game.store)
        r.skillLevels = Home.skillLevels(game.store)
        r.learnedSpells = Spells.learned(game.characters[index])
        r.worldCurse = VoidReaperLive.shared.cursed
        Home.resetSleep(store: game.store)
        if case .string(let dream)? = game.characters[index].extra["dream"] {
            if let note = Home.applyDream(dream, to: &r) { r.startNotes.append("💤 " + note) }
            game.updateCharacter(index) { $0.extra["dream"] = nil }
        }
        var cd = SystemDice()
        CoinShop.apply(CoinShop.owned(game.store), to: &r, dice: &cd, wallet: game.wallet)
        game.achievements.trackGlobal("runsStarted")
        var d = SystemDice()
        Weather.start(&r, dice: &d)
        ClassTraits.shapeWeather(&r)
        _ = RunModifiers.start(&r, store: game.store, wallet: game.wallet, dice: &d)
        Skills.start(&r, dice: &d)
        if r.floor >= Challenges.bossFloor(r) && r.difficulty != .endless { r.floorRoomsNeeded = 1 }
        Encounters.planFloor(&r, dice: &d)
        if ThreeDMode.isOn(game.store) { r.roomGraph = RoomGraph(roomsNeeded: r.floorRoomsNeeded, dice: &d) }
        r.hpAtFloorStart = r.hp
        r.startedAt = Date().timeIntervalSince1970
        // Level carried over by Continue Journey applies to this run only.
        game.updateCharacter(index) { $0.extra["carryLevel"] = nil; $0.extra["carryXp"] = nil }
        return r
    }

    private func begin() {
        journal("Descended into \(run.dungeon) on \(run.difficulty.rawValue) difficulty.")
        let r = run
        roomTitle = Rooms.floorName(r.floor, dungeon: r.dungeon)
        roomText = ""
        add("Descended into \(r.dungeon) on \(r.difficulty.rawValue) difficulty\(r.ngPlus ? ", New Game+ \(r.ngPlusCount ?? 1)" : "")\(r.hardcore ? ", Hardcore" : "").")
        add("Floor \(r.floor): \(roomTitle). \(r.lives) \(r.lives == 1 ? "life" : "lives").")
        if let s = Skills.unlocked(r).first { add("✨ Starting skill: \(s.name). \(s.desc)") }
        r.startNotes.forEach { add($0) }
        if let m = r.minion { add("👾 \(m.name) fights beside you.") }
        _ = bounty(.runStarted)
        startForest()
        if WhisperingForest.here(r) { add("🌲 The forest's corruption creeps in while you explore. Music Boxes and potions push it back.") }
        if let c = Corruption.status(r) { add(c) }
        if let w = r.weather {
            add(w.announcement)
            Feedback.announce(w.announcement, after: 4)
        }
        if let m = RunModifiers.modifier(r.modifier) {
            let line = "🎲 Run modifier: \(m.icon) \(m.name). \(m.desc)"
            add(line)
            Feedback.announce("Run modifier. \(m.name). \(m.desc) You can turn run modifiers off in Settings, Gameplay.", after: 4.5)
        }
        let hello = guideSays(.dungeonStart, r)
        if !hello.isEmpty { Feedback.announce(hello, after: 2.5) }
        if r.hunter != nil {
            add("🏹 Hunter Mode active. Something has entered the dungeon behind you. It is 10 rooms away. Keep moving.")
        }
        if let b = bountyBanner { add(b) }
        add("✦ Daily quest: \(game.dailyQuests.summary)")
        if r.dailyChallenge == nil && !DailyChallenge.isCompleted(game.store) {
            let dc = DailyChallenge.today()
            add("⚡ Today's daily challenge is \(dc.name). Register for it in Quests, Challenge tab, to play it and earn a Mystery Coin.")
        }
        persist()
        playMusic()
        if let g = r.roomGraph {
            SpatialAudio.shared.setRoom(dungeon: r.dungeon)
            add("🧊 3D Mode. \(g.exitsText)")
            SpatialAudio.shared.exitCues(g.here, after: 3)
        }
    }

    /// Set when a Hardcore death deleted the character; the screen should close.
    @Published private(set) var characterGone = false

    var canContinueJourney: Bool {
        guard let i = GameData.dungeons.firstIndex(of: run.dungeon) else { return false }
        return i < GameData.dungeons.count - 1
    }

    /// After a victory: the next dungeon with the same character, level and XP.
    func continueJourney() {
        guard phase == .victory else { return }
        let level = run.level, xp = run.xp
        var moved = false
        game.updateCharacter(characterIndex) { moved = $0.continueJourney(level: level, xp: xp) }
        guard moved else { return }
        restart("Journey continues. Entering \(game.characters[characterIndex].dungeon). Your character carries all their strength forward.")
    }

    /// After a victory: the same dungeon again with stronger enemies.
    func startNewGamePlus() {
        guard phase == .victory else { return }
        game.updateCharacter(characterIndex) { $0.startNewGamePlus() }
        let n = game.characters[characterIndex].ngPlusCount
        restart(n == 1 ? "New Game Plus! Enemies are stronger. The dungeon has not forgotten you."
                : n == 2 ? "NG+2! The dungeon is actively hostile now."
                : "NG+\(n)! You should not still be alive. The dungeon is impressed and furious.")
    }

    private func restart(_ message: String) {
        log = []
        run = Self.newRun(game, characterIndex)
        phase = .exploring
        shop = []
        begin()
        Feedback.announce(message)
    }

    /// Exploration, battle or boss music for where the run is, plus the dungeon's ambience.
    func playMusic() {
        let r = run
        if let s = r.stalker {
            Sound.track("shadow-stalker")
            if s.grid != nil {
                SpatialAudio.shared.stalkerStart(s)
                startCreeping()
            } else {
                Sound.startLoop("monster-growl.mp3", volume: s.growlVolume, pan: s.pan)
            }
            return
        }
        if let h = r.hunter, h.dist <= 3, !r.inCombat {
            Sound.track("hunter-theme")
            Sound.ambient(Soundtrack.ambientKey(dungeon: r.dungeon, difficulty: r.difficulty))
            return
        }
        if let e = r.enemy, r.inCombat {
            // The Hunter fights to the plain battle music (hunterFight).
            Sound.track(e.name == "The Hunter" ? "battle"
                        : e.isBoss ? Soundtrack.bossTrack(dungeon: r.dungeon, phase: r.bossPhase) : Soundtrack.battleTrack(dungeon: r.dungeon))
        } else {
            Sound.track(Soundtrack.exploreTrack(dungeon: r.dungeon, floor: r.floor))
        }
        Sound.ambient(Soundtrack.ambientKey(dungeon: r.dungeon, difficulty: r.difficulty))
    }

    var isBossFloor: Bool { run.floor >= Challenges.bossFloor(run) && run.difficulty != .endless }
    var isChallenge: Bool { run.gauntletStage != nil || run.dailyKey != nil }
    var bossRoomNext: Bool { isBossFloor && run.roomsOnFloor == run.floorRoomsNeeded - 1 }
    var canWander: Bool { run.floor < 9 }
    var hour: Int { Calendar.current.component(.hour, from: Date()) }

    // MARK: Exploring

    /// The compass buttons. Outside 3D Mode any direction leads to the next room.
    func move(_ dir: String) {
        guard phase == .exploring else { return }
        if threeD, let c = Compass(rawValue: dir) {
            move3D(c)
            return
        }
        guard hunterMoves() else { return }
        movePrefix = "Moving \(dir). "
        enterRoom()
        hunterAfterRoom()
    }

    // MARK: 3D Mode

    var threeD: Bool { ThreeDMode.isOn(game.store) }

    /// moveRoom3D: walls stop you; a door into a new room is enterRoom();
    /// a room you've cleared is just a room.
    private func move3D(_ d: Compass) {
        var r = run
        var dc = dice
        // Turned on mid-run: build this floor's rooms now.
        if r.roomGraph == nil {
            r.roomGraph = RoomGraph(roomsNeeded: max(1, r.floorRoomsNeeded - r.roomsOnFloor), dice: &dc)
            SpatialAudio.shared.setRoom(dungeon: r.dungeon)
        }
        var g = r.roomGraph!
        let step = g.move(d)
        if case .entered(let first) = step {
            g.ensureRooms(left: r.floorRoomsNeeded - r.roomsOnFloor - (first ? 1 : 0), dice: &dc)
        }
        r.roomGraph = g
        run = r
        dice = dc
        switch step {
        case .wall:
            SpatialAudio.shared.wallBump(d)
            Feedback.warning()
            persist()
            Feedback.announce("There is a wall to the \(d.rawValue). \(g.exitsText)")
            SpatialAudio.shared.exitCues(g.here)
        case .entered(let first):
            SpatialAudio.shared.footsteps(d)
            lastMove = d
            guard hunterMoves() else { return }
            if first {
                movePrefix = "Moving \(d.rawValue). \(g.exitsText) "
                enterRoom()
            } else {
                persist()
                roomText = "You are back in a room you already cleared."
                Feedback.announce("Moving \(d.rawValue). You are back in a room you already cleared. \(g.exitsText)" + takeHunterLine())
            }
            hunterAfterRoom()
            if run.stalker == nil && !run.inCombat { SpatialAudio.shared.exitCues(g.here) }
        }
    }

    /// Where you are and which ways are open.
    var exitsText: String? { threeD ? run.roomGraph?.exitsText : nil }

    private var echoCooldown = Date.distantPast

    /// echoLocate: a sonar pulse. Each direction answers by sound, then it's said.
    func echoLocate() {
        guard threeD else {
            Feedback.announce("Echo-location needs 3D Mode turned on in Settings, Beta Features.")
            return
        }
        guard phase == .exploring, run.stalker == nil else {
            Feedback.announce("Echo-location only works while exploring, not during combat.")
            return
        }
        guard Date() >= echoCooldown else { return }
        echoCooldown = Date().addingTimeInterval(1.4)
        if run.roomGraph == nil { move3DSetup() }
        guard let g = run.roomGraph else { return }
        let e = g.echo(ahead: RoomGraph.ahead(run))
        SpatialAudio.shared.echo(e)
        Feedback.tap()
        // Let the pulse play out before VoiceOver talks over it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { Feedback.announce(e.summary) }
    }

    private func move3DSetup() {
        var r = run
        var dc = dice
        r.roomGraph = RoomGraph(roomsNeeded: max(1, r.floorRoomsNeeded - r.roomsOnFloor), dice: &dc)
        run = r
        dice = dc
        SpatialAudio.shared.setRoom(dungeon: r.dungeon)
    }

    /// An enemy's cry: from the doorway you came through in 3D Mode.
    private func enemyCue(_ id: String) {
        if threeD, let g = run.roomGraph { SpatialAudio.shared.enemy(id, from: g.lastMove) } else { Sound.sfx(id) }
    }

    func enterRoom() {
        guard phase == .exploring, run.stalker == nil else { return }
        if !threeD { Sound.sfx("sfx-footstep") }
        var r = run
        var d = dice
        // The Shadow World: the Darkness Swallower finds you before the room does.
        if StalkerFloor.shouldStart(r, dice: &d) {
            startStalker(&r, &d)
            return
        }
        r.roomsOnFloor += 1
        r.totalRooms += 1
        r.searched = false
        r.sp = min(r.maxSp, r.sp + 2)
        if let heal = Subclasses.onRoom(&r) { add(heal) }
        if let heal = ClassTraits.onRoom(&r) { add(heal) }
        roomTitle = Rooms.floorName(r.floor, dungeon: r.dungeon)
        roomText = Rooms.description(for: r, dice: &d)
        let label = "Room \(r.roomsOnFloor) of \(r.floorRoomsNeeded)."
        // Verbose Room Descriptions (Accessibility settings) reads the room text.
        var spoken = AppSettings.verboseRooms ? "\(label) \(roomText)" : label
        // The Medusa arc: while she's with you, her father may be in this room.
        if Medusa.walksWithYou(r) && d.chance(Medusa.fatherChance(game.store)) {
            let line = Medusa.reunion(&r, store: game.store)
            game.wallet.addGold(50)
            achievements.increment("medusaReunion")
            _ = achievements.check()
            add(line)
            Sound.sfx("sfx-unlock")
            spoken += " " + line
        }

        // Tonight's conditions can cost HP every room.
        if let w = r.weather, w.roomHpLoss > 0 {
            r.hp = max(1, r.hp - w.roomHpLoss)
            let line = "🌡️ \(w.name) — minus \(w.roomHpLoss) HP from the conditions."
            add(line)
            spoken += " " + line
        }

        if r.poisonTurns > 0 {
            var lines: [String] = []
            Combat.tickEffects(&r, log: &lines)
            lines.forEach { add($0) }
            spoken += " " + lines.joined(separator: " ")
            if r.isDead {
                run = r; dice = d
                playerDied(killedBy: "poison", spoken: spoken)
                return
            }
        }

        if isBossFloor && r.roomsOnFloor >= r.floorRoomsNeeded && !r.guardianDone {
            // startEliteGauntlet: an Elite Guardian blocks the way to the boss.
            let g = Combat.eliteGuardian(for: r, dice: &d)
            Combat.begin(&r, against: g).forEach { add($0) }
            let msg = "⚡ ELITE GUARDIAN — \(g.name) stands between you and the final chamber. It is significantly stronger than its kin."
            add(msg)
            roomText = msg
            enemyCue(Soundtrack.enemyCue(dungeon: r.dungeon, boss: false))
            Sound.track(Soundtrack.battleTrack(dungeon: r.dungeon))
            spoken += " Elite Guardian encountered on floor 10. \(g.name) blocks the path to the boss. HP: \(g.hp). Defeat it to face the final boss."
            spoken += thirdEye(r)
            finish(r, d, phase: .fighting, spoken: spoken)
            return
        }

        if isBossFloor && r.roomsOnFloor >= r.floorRoomsNeeded {
            let boss = Combat.nextBoss(for: r, dice: &d)
            Combat.begin(&r, against: boss).forEach { add($0) }
            add("\(boss.icon) \(boss.name) rises before you. \(boss.hp) HP.")
            enemyCue(Soundtrack.enemyCue(dungeon: r.dungeon, boss: true))
            Sound.track(Soundtrack.bossTrack(dungeon: r.dungeon))
            spoken += " \(boss.name) rises before you. \(boss.hp) HP." + thirdEye(r) + guideSays(.bossEncounter, r)
            finish(r, d, phase: .fighting, spoken: spoken)
            return
        }

        // A wandering NPC (once a run) or Friday the 13th's Black Box.
        if !isBossFloor, let id = SpecialEncounters.npc(&r, dice: &d) ?? SpecialEncounters.blackBox(&r, dice: &d),
           let ev = Encounters.event(id) {
            r.pendingEvent = id
            add("\(label) \(ev.title) — \(ev.text)")
            if id == "black-box" { Sound.sfx("sfx-trap") }
            finish(r, d, phase: .event, spoken: spoken + " \(ev.title). \(ev.text) " + ev.choices.joined(separator: " or ") + ".")
            return
        }

        if let special = Encounters.plannedRoom(r) {
            roomTitle = "\(special.icon) \(special.name)"
            roomText = special.desc
            let out = Encounters.enterSpecial(special, &r, dice: &d, wallet: game.wallet, store: game.store)
            add("\(label) \(out.message)")
            let said = "\(label) \(special.name). \(special.desc) \(out.message)"
            if let enemy = out.enemy {
                Combat.begin(&r, against: enemy).forEach { add($0) }
                enemyCue(Soundtrack.enemyCue(dungeon: r.dungeon, boss: false))
                Sound.track(Soundtrack.battleTrack(dungeon: r.dungeon))
                finish(r, d, phase: .fighting, spoken: said + " \(enemy.hp) HP." + thirdEye(r))
            } else if out.openShop {
                shop = Inventory.shopStock(for: r, dice: &d)
                finish(r, d, phase: .shopping, spoken: said + " You have \(r.gold) gold.")
            } else {
                if out.item != nil || out.gold > 0 { Sound.sfx("sfx-loot"); Feedback.success() }
                let q = questFound(&r, item: out.item, gold: out.gold)
                finishQuietRoom(r, d, spoken: said + q)
            }
            return
        }

        switch Rooms.next(&r, dice: &d) {
        case .fight:
            // The Hollow: the Weeping Child or the Weeping Mother instead of a fight.
            let hollow = HollowEvents.encounter(&r, classTraits: AppSettings.classTraits, dice: &d)
            if let line = hollow.line {
                add("\(label) \(line)")
                achievements.increment("wepingChildSoothed")
                _ = achievements.check()
                Sound.sfx("sfx-unlock")
                finishQuietRoom(r, d, spoken: spoken + " " + line)
                return
            }
            if let id = hollow.event, let ev = Encounters.event(id) {
                r.pendingEvent = id
                add("\(label) \(ev.title) — \(ev.text)")
                finish(r, d, phase: .event,
                       spoken: spoken + " \(ev.title). \(ev.text) " + ev.choices.joined(separator: " or ") + ".")
                return
            }
            // Easter: the Easter Bunny.
            if let id = SpecialEncounters.easterBunny(r, earned: earnedSpirits, dice: &d), let ev = Encounters.event(id) {
                r.pendingEvent = id
                add("\(label) \(ev.title) — \(ev.text)")
                finish(r, d, phase: .event, spoken: spoken + " \(ev.title). \(ev.text) " + ev.choices.joined(separator: " or ") + ".")
                return
            }
            // The Chimera: three parts, each its own target.
            if let parts = Chimera.spawn(r, store: game.store, dice: &d) {
                let name = Chimera.name(parts)
                Combat.beginAmbush(&r, parts).forEach { add($0) }
                enemyCue(Soundtrack.enemyCue(dungeon: r.dungeon, boss: true))
                Sound.track(Soundtrack.battleTrack(dungeon: r.dungeon))
                let list = parts.map { "\($0.name), \($0.hp) HP, \($0.desc ?? "")" }.joined(separator: " ")
                add("\(label) \(name) appears!")
                finish(r, d, phase: .fighting,
                       spoken: spoken + " \(name) appears! Three parts, each attacks on its own. \(list) Choose a part to target with the target buttons.")
                return
            }
            // 20% of fights from floor 3 are ambushes; every fight is on Ambush Day.
            let forced = r.devAmbush
            r.devAmbush = false
            if forced || (r.floor >= 3 && (r.event == "ambushday" || d.chance(0.20))),
               let line = startAmbush(&r, &d, label: label) {
                spoken += " " + line
                finish(r, d, phase: .fighting, spoken: spoken)
                return
            }
            let enemy = Combat.nextEnemy(for: r, dice: &d)
            if let line = ClassTraits.talksDown(r, enemy, dice: &d) {
                add("\(label) \(line)")
                finish(r, d, phase: .exploring, spoken: spoken + " " + line)
                return
            }
            Combat.begin(&r, against: enemy).forEach { add($0) }
            let ability = Self.sentence(enemy.desc ?? "A powerful foe.")
            let line = enemy.isElite
                ? "\(label) ★ ELITE: \(enemy.icon) \(enemy.name) — \(ability) \(enemy.hp) HP."
                : "\(label) \(enemy.icon) A \(enemy.name) attacks! \(enemy.hp) HP."
            add(line)
            enemyCue(Soundtrack.enemyCue(dungeon: r.dungeon, boss: false))
            Sound.track(Soundtrack.battleTrack(dungeon: r.dungeon))
            spoken += enemy.isElite
                ? " Elite enemy! \(enemy.name). \(ability) \(enemy.hp) HP."
                : " A \(enemy.name) attacks! \(enemy.hp) HP."
            spoken += thirdEye(r)
            finish(r, d, phase: .fighting, spoken: spoken)
        case .loot:
            let find = Inventory.lootRoom(&r, dice: &d, wallet: game.wallet)
            add("\(label) \(find.message)")
            spoken += " " + find.message
            if find.mysteryCoin { game.addMysteryCoins(1) }
            if find.item != nil || find.gold > 0 { Feedback.success(); Sound.sfx("sfx-loot") }
            spoken += questFound(&r, item: find.item, gold: find.gold)
            finishQuietRoom(r, d, spoken: spoken)
        case .event:
            if let ev = Encounters.rollEvent(r, dice: &d) {
                r.pendingEvent = ev.id
                add("\(label) \(ev.title) — \(ev.text)")
                finish(r, d, phase: .event,
                       spoken: spoken + " Special event: \(ev.title). \(ev.text) " + ev.choices.joined(separator: " or ") + ".")
                if let dir = ShadowEvents.securityDirection(ev.id) { startSecurityRoom(dir) }
            } else {
                add("\(label) \(roomText)")
                finishQuietRoom(r, d, spoken: spoken)
            }
        }
    }

    /// Ends text with exactly one full stop.
    static func sentence(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.hasSuffix(".") || t.hasSuffix("!") || t.hasSuffix("?") ? t : t + "."
    }

    var pendingEvent: Encounters.Event? { run.pendingEvent.flatMap(Encounters.event) }

    func chooseEvent(_ choice: Int) {
        guard phase == .event else { return }
        stopSecurityRoom()
        var r = run
        var d = dice
        let levelBefore = r.level
        if r.pendingEvent == "julio" && choice == 0 { achievements.record(.julioMet) }
        let out = Encounters.choose(choice, &r, dice: &d, wallet: game.wallet)
        if out.retry {
            // A requirement wasn't met: nothing happened, choose again.
            Feedback.warning()
            Feedback.announce(out.message)
            return
        }
        add(out.message)
        if let sp = out.spirit, !earnedSpirits.contains(sp) {
            earnSpirit(sp)
            Sound.sfx("sfx-unlock")
        }
        var fragLine = ""
        if out.voidFragment {
            fragLine = " " + voidFragment()
            add(fragLine)
        }
        if let stat = out.stat {
            achievements.increment(stat)
            _ = achievements.check()
            Sound.sfx("sfx-unlock")
        }
        if let track = out.music {
            Sound.track(track)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.playMusic() }
        }
        if r.level > levelBefore {
            Sound.sfx("sfx-levelup")
            add("Level up! You are now level \(r.level). You have \(r.levelPoints) level points to spend.")
            if r.skillChoices.isEmpty { Skills.offer(&r, dice: &d) }
            levelUp = r.level
        }
        if out.playerDied {
            run = r; dice = d
            Sound.sfx("sfx-hurt")
            playerDied(killedBy: "a mimic", spoken: out.message)
            return
        }
        if let enemy = out.enemy {
            Combat.begin(&r, against: enemy).forEach { add($0) }
            enemyCue(Soundtrack.enemyCue(dungeon: r.dungeon, boss: false))
            Sound.track(Soundtrack.battleTrack(dungeon: r.dungeon))
            finish(r, d, phase: .fighting, spoken: out.message + " \(enemy.name), \(enemy.hp) HP." + thirdEye(r))
            return
        }
        if out.item != nil || out.gold > 0 { Sound.sfx("sfx-loot") }
        let q = questFound(&r, item: out.item, gold: out.gold)
        finishQuietRoom(r, d, spoken: out.message + fragLine + q)
    }

    private var achievements: AchievementBook { game.achievements }

    /// Third Eye (Coin Shop): the enemy's exact HP, attack and special ability
    /// before the fight (showEnemyPreview).
    private func thirdEye(_ r: Run) -> String {
        guard r.has("cu-third-eye"), let e = r.enemy else { return "" }
        let special = GameContent.shared.enemySpecials[e.name].map { ". \($0.name)" } ?? ""
        let line = "Third Eye. \(e.name). \(e.hp) HP. Attack \(e.atk.lowerBound) to \(e.atk.upperBound)\(special)."
        add("👁 " + line)
        return " " + line
    }

    // MARK: Daily quest

    /// Counts progress toward today's quest. When it finishes, pays the reward
    /// into the run and returns the spoken line to add.
    private func quest(_ r: inout Run, _ type: String, _ amount: Int = 1) -> String {
        questDone(&r, game.dailyQuests.report(type, amount))
    }

    private func questDone(_ r: inout Run, _ done: DailyQuest?) -> String {
        guard let q = done else { return "" }
        DailyQuests.payReward(q, &r, wallet: game.wallet)
        achievements.record(.dailyQuestCompleted)
        Sound.sfx("sfx-unlock")
        Feedback.success()
        let msg = "Daily quest complete! \(q.desc) Reward: \(q.reward)!"
        add("✦ " + msg)
        return " " + msg
    }

    /// Loot and gold found in a room, search or event.
    private func questFound(_ r: inout Run, item: Item?, gold: Int) -> String {
        var said = ""
        if let item, item.type != "gem" { said += quest(&r, "loot") }
        if gold > 0 { said += quest(&r, "gold", gold) }
        return said
    }

    /// showFloorCompleteScreen's spoken summary.
    private func floorCompleteLine(_ r: Run) -> String {
        let f = r.floorStats
        return "Floor \(r.floor) complete. Kills: \(f.kills). Best hit: \(f.bestHit). Gold earned: \(max(0, r.gold - f.goldStart)). Choose to descend or wander."
    }

    /// Achievements for finishing a floor without losing HP.
    private func floorDone(_ r: Run) {
        floorSummary = r.floorStats
        achievements.record(.floorCleared(tookNoDamage: r.hp >= r.hpAtFloorStart))
    }

    private func finishQuietRoom(_ r: Run, _ d: SystemDice, spoken: String) {
        if r.roomsOnFloor >= r.floorRoomsNeeded {
            floorDone(r)
            finish(r, d, phase: .floorCleared, spoken: spoken + " " + floorCompleteLine(r))
            add("Floor \(r.floor) complete.")
        } else {
            finish(r, d, phase: .exploring, spoken: spoken)
        }
    }

    func search() {
        guard phase == .exploring || phase == .floorCleared else { return }
        var r = run
        var d = dice
        Sound.sfx("sfx-search")
        let find = Inventory.search(&r, dice: &d, wallet: game.wallet)
        add(find.message)
        if find.trap != nil && find.trap != "avoided" { Feedback.warning(); Sound.sfx("sfx-trap") }
        else if find.item != nil || find.gold > 0 { Feedback.success(); Sound.sfx("sfx-loot") }
        let q = find.playerDied ? "" : questFound(&r, item: find.item, gold: find.gold)
        run = r
        dice = d
        if find.playerDied {
            playerDied(killedBy: find.trap ?? "a trap", spoken: find.message)
            return
        }
        persist()
        Feedback.announce(find.message + q)
    }

    // MARK: Fighting

    // MARK: The Stalker Floor

    private func startStalker(_ r: inout Run, _ d: inout SystemDice) {
        let s = StalkerFloor(dice: &d, threeD: threeD)
        r.stalker = s
        // The room it took you in doesn't count; it's still new.
        r.roomGraph?.unvisitHere()
        add("🌑 Something stirs in the darkness. The Darkness Swallower is in this room with you.")
        Sound.stopMusic()
        Sound.ambient(nil)
        Sound.track("shadow-stalker")
        if s.grid != nil {
            SpatialAudio.shared.stalkerStart(s)
            finish(r, d, phase: .exploring,
                   spoken: "Something stirs in the darkness. The music shifts. The Darkness Swallower is in this room with you — far off, in the \(s.direction == "ahead" || s.direction == "behind" ? s.direction : "corner to your \(s.direction)"). It is \(s.distance) steps away, and it is coming. It moves when you move, and it keeps coming even if you stand still. Reach the edge of the room \(StalkerFloor.escapesNeeded) times to escape. Use headphones: you will hear exactly where it is.")
            startCreeping()
            return
        }
        Sound.startLoop("monster-growl.mp3", volume: s.growlVolume, pan: s.pan)
        finish(r, d, phase: .exploring,
               spoken: "Something stirs in the darkness. The music shifts. Move carefully — the Darkness Swallower is somewhere in this room with you. It is \(s.distance) step\(s.distance != 1 ? "s" : "") away, to the \(s.direction). Reach the edge of the room \(StalkerFloor.escapesNeeded) times to escape. Use headphones: its growl tells you where it is.")
    }

    // 3D Mode: the Darkness Swallower doesn't wait for you.
    private var creepTimer: Timer?
    static let creepSeconds = 8.0

    private func startCreeping() {
        creepTimer?.invalidate()
        creepTimer = Timer.scheduledTimer(withTimeInterval: Self.creepSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.creep() }
        }
    }

    private func stopCreeping() {
        creepTimer?.invalidate()
        creepTimer = nil
    }

    private func creep() {
        guard var s = run.stalker, s.grid != nil else { stopCreeping(); return }
        guard phase == .exploring else { return }
        var r = run
        let reached = s.creep()
        r.stalker = s
        if reached {
            stalkerCaught(&r)
            return
        }
        run = r
        SpatialAudio.shared.stalkerStep(s)
        persist()
        if s.distance == 1 {
            Feedback.warning()
            Feedback.announce("It is right next to you. You can turn and fight it.")
        } else if s.distance <= 3 {
            Feedback.announce("It's closer. \(s.distance) steps, \(s.direction).")
        }
    }

    private func stalkerCaught(_ r: inout Run) {
        stopCreeping()
        Sound.stopLoop()
        if r.stalker?.grid != nil { SpatialAudio.shared.caught() } else { Sound.placed("jump-scare-v3.mp3", volume: 1, pan: 0) }
        Feedback.warning()
        let dmg = StalkerFloor.caught(&r)
        add("💀 THE DARKNESS SWALLOWER CATCHES YOU! \(dmg) shadow damage!")
        finish(r, dice, phase: .exploring, spoken: "Caught! The Darkness Swallower strikes. \(dmg) damage. You barely survive." + (exitsText.map { " " + $0 } ?? ""))
        playMusic()
    }

    /// stalkerMove
    func stalkerMove(_ dir: String) {
        guard var s = run.stalker else { return }
        var r = run
        var d = dice
        let out = s.move(dir)
        r.stalker = s
        Sound.sfx("sfx-stairs")
        if s.grid != nil {
            SpatialAudio.shared.stalkerStep(s)
        } else {
            Sound.placed("monster-footstep.mp3", volume: s.stepVolume, pan: s.pan)
            Sound.moveLoop(volume: s.growlVolume, pan: s.pan)
        }
        switch out {
        case .caught:
            dice = d
            stalkerCaught(&r)
        case .escaped:
            stopCreeping()
            SpatialAudio.shared.stopStalker()
            Sound.stopLoop()
            let item = StalkerFloor.escaped(&r, wallet: game.wallet, dice: &d)
            add("✨ You escaped the Darkness Swallower! Rare loot awarded.")
            if let item { add("📦 Found: \(item.name)!") }
            Sound.sfx("sfx-victory")
            Feedback.success()
            finish(r, d, phase: .exploring, spoken: "You escaped! The Darkness Swallower retreats into the shadows. 150 gold" + (item.map { " and \($0.name)" } ?? "") + " for your survival." + (exitsText.map { " " + $0 } ?? ""))
            playMusic()
        case .escapedOnce:
            let left = StalkerFloor.escapesNeeded - s.escapes
            add("You slip away — temporarily. \(left) more escape\(left != 1 ? "s" : "") needed.")
            finish(r, d, phase: .exploring, spoken: "You escape — for now. \(left) more needed. It is \(s.distance) steps away, to the \(s.direction).")
        case .moved:
            let line = s.report(dir)
            add(line)
            if s.distance == 1 { Feedback.warning() }
            let said = s.distance == 1 ? "It is right next to you. One step away. The darkness breathes. You can turn and fight it."
                : s.distance == 2 ? "It is 2 steps away, to the \(s.direction). Listen for the direction."
                : "You move \(dir). It is \(s.distance) steps away, to the \(s.direction)."
            finish(r, d, phase: .exploring, spoken: said)
        }
    }

    /// stalkerChooseFight
    func stalkerFight() {
        guard let s = run.stalker, s.distance <= 1 else { return }
        var r = run
        stopCreeping()
        SpatialAudio.shared.stopStalker()
        Sound.stopLoop()
        let e = StalkerFloor.fight(&r)
        Combat.begin(&r, against: e).forEach { add($0) }
        add("⚔ You turn to face the Darkness Swallower!")
        Sound.track(Soundtrack.battleTrack(dungeon: r.dungeon))
        finish(r, dice, phase: .fighting, spoken: "You face the Darkness Swallower. \(e.hp) HP. It hits hard and adds 2 corruption per hit. Use Purge.")
    }

    /// The Shadow World's Purge: 4 SP clears all corruption. A free action.
    var canPurge: Bool { phase == .fighting && run.dungeon == ShadowWorld.name }

    func purge() {
        var r = run
        let msg = ShadowWorld.purge(&r)
        run = r
        add(msg)
        persist()
        if msg.hasPrefix("✨") { Sound.sfx("sfx-unlock") }
        Feedback.announce(msg.hasPrefix("✨") ? "Purge. Corruption cleared. \(ShadowWorld.purgeCost) SP spent." : msg)
    }

    /// Bomb Thrower's once-per-floor bomb.
    var canBomb: Bool { phase == .fighting && Subclasses.canBomb(run) }

    func throwBomb() { act(.attack, bomb: true) }

    /// The level 5 subclass choice (chooseSubclass).
    func chooseSubclass(_ id: String) {
        guard let sub = Subclasses.options(for: run.cls).first(where: { $0.id == id }) else { return }
        var r = run
        let lines = Subclasses.choose(&r, id)
        guard !lines.isEmpty else { return }
        lines.forEach { add($0) }
        var d = dice
        if let line = Spells.startingScrolls(&r, dice: &d) { add(line) }
        dice = d
        journal("Chose the \(sub.name) subclass.", in: &r)
        run = r
        persist()
        Sound.sfx("sfx-unlock")
        Feedback.announce("Subclass chosen. \(sub.name). \(sub.desc) Passive: \(sub.passive)")
    }

    func act(_ action: PlayerAction, bomb: Bool = false) {
        guard phase == .fighting else { return }
        if action == .defend && RunModifiers.noDefend(run) {
            Feedback.announce("Cannot defend in Berserk Mode.")
            return
        }
        if action == .flee && !ClassTraits.canFlee(run) {
            add("No Retreat — Berserkers cannot flee.")
            Feedback.announce("No Retreat. Berserkers do not run.")
            return
        }
        if let e = run.enemy, TimeDescender.isClock(e) {
            clockHit(action)
            return
        }
        var r = run
        var d = dice
        let options = Combat.Options(classTraits: AppSettings.classTraits)
        let result = bomb ? Combat.throwBomb(&r, dice: &d, options: options) : Combat.takeTurn(&r, action, dice: &d, options: options)
        guard result.acted else { return }
        if r.fight.stolenGold > 0 {
            _ = game.wallet.spendGold(min(game.wallet.gold, r.fight.stolenGold))
            r.fight.stolenGold = 0
        }
        track(&r, result)
        result.log.forEach { add($0) }
        if result.crit { Feedback.hit(heavy: true) } else if result.playerDamage > 0 { Feedback.hit() }
        switch action {
        case _ where bomb: Sound.sfx("sfx-heavy-hit")
        case .attack: Sound.sfx(result.crit ? "sfx-crit" : "sfx-attack")
        case .heavy: Sound.sfx(result.missed ? "sfx-heavy-miss" : "sfx-heavy-hit")
        case .defend: Sound.sfx("sfx-select")
        case .flee: break
        }
        if (result.enemyDamage ?? 0) > 0 { Sound.sfx("sfx-hurt") }

        var spoken = result.log.first ?? ""
        spoken += rewardFallen(result.alsoDefeated, &r, &d)
        if result.bossPhaseMessage != nil {
            spoken = result.log.joined(separator: " ")
            Feedback.hit(heavy: true)
            run = r
            playMusic()
        }
        var questLine = ""
        if result.crit { questLine += quest(&r, "crits"); achievements.trackGlobal("totalCrits") }
        if (result.enemyDamage ?? 0) > 0 && r.hp > 0 && r.hp <= 10 { questLine += quest(&r, "survive") }
        spoken += questLine

        if result.fled {
            finish(r, d, phase: r.roomsOnFloor >= r.floorRoomsNeeded ? .floorCleared : .exploring,
                   spoken: result.announcement ?? "You fled.")
            playMusic()
            return
        }
        if result.enemyFled {
            run = r; dice = d
            enemyFled(result, spoken: spoken)
            return
        }
        if result.enemyDied, let e = result.defeated ?? r.enemy {
            run = r; dice = d
            enemyDefeated(e, spoken: spoken, result: result)
            return
        }
        if result.playerDied {
            run = r; dice = d
            playerDied(killedBy: r.enemy?.name ?? "the dungeon", spoken: spoken)
            return
        }
        if let a = result.announcement, result.bossPhaseMessage == nil { spoken += " " + a }
        // Combat Announcements off: an ordinary exchange isn't read out.
        if !AppSettings.combatAnnouncements && result.bossPhaseMessage == nil { spoken = questLine }
        finish(r, d, phase: .fighting, spoken: spoken)
    }

    /// Gold, XP and the bestiary for ambushers that fell on their own turn.
    private func rewardFallen(_ fallen: [Enemy], _ r: inout Run, _ d: inout SystemDice) -> String {
        var said = ""
        for e in fallen {
            let reward = Progression.rewardKill(&r, e, dice: &d, wallet: game.wallet)
            add(reward.message)
            said += " " + reward.message
            achievements.record(.enemyKilled(e, run: r))
            _ = game.recordBestiaryKill(e.name)
            if reward.levelsGained > 0 { levelUp = r.level; achievements.record(.levelReached(r.level)) }
            said += bountyKill(e, r)
            said += craftingDrops(e, r.floor, &d)
        }
        return said
    }

    /// Forge materials (15%) and alchemy ingredients (10%) from a kill.
    private func craftingDrops(_ e: Enemy, _ floor: Int, _ d: inout SystemDice) -> String {
        var said = ""
        if let m = WeaponForge.drop(floor: floor, store: game.store, dice: &d) {
            add("📦 Material dropped: \(m.icon) \(m.name)!")
            said += " Forge material: \(m.name)."
        }
        if let i = Alchemy.drop(e, store: game.store, dice: &d) {
            add("🧪 Found: \(i.icon) \(i.name) (Alchemy ingredient)")
            said += " Alchemy ingredient: \(i.name)."
        }
        return said
    }

    // MARK: The Witness, Void Fragments

    /// checkWitnessAfterKill: the shark was a test, and you passed.
    private func witnessChooses(_ spoken: String) {
        var r = run
        r.enemy = nil
        r.inCombat = false
        r.kills += 1
        var said = SpecialEncounters.witnessText
        add("🦈 " + said)
        if SpecialEncounters.witnessJoins(store: game.store) {
            said += " The Witness joins you as a permanent minion!"
            add("🦈 The Witness joins you as a permanent minion!")
        }
        achievements.award("ach-witness")
        Sound.sfx("sfx-unlock")
        finish(r, dice, phase: r.roomsOnFloor >= r.floorRoomsNeeded && r.roomsOnFloor > 0 ? .floorCleared : .exploring,
               spoken: spoken + " " + said + (exitsText.map { " " + $0 } ?? ""))
        playMusic()
    }

    /// addVoidFragment: a piece of the Lost Child's story (25 in all).
    private func voidFragment() -> String {
        let n = jsParseInt(game.store.getItem("dd_void_fragments")) ?? 0
        guard n < 25 else { return "👁 You already have all 25 Void Fragments. Her story is complete in the Chronicles." }
        game.store.setItem("dd_void_fragments", String(n + 1))
        game.globalInventory.add(Item(name: "Void Fragment \(n + 1) of 25", icon: "👁", type: "material", desc: "A piece of her story."))
        _ = achievements.check()
        Sound.sfx("sfx-unlock")
        return "👁 Void Fragment \(n + 1) of 25. A new chapter has been added to the Void Chronicles in your library."
    }

    // MARK: The Time Descender

    /// The Clock is striking: your buttons wait for the pause.
    @Published private(set) var clockTicking = false
    private var clockWindow = false
    private var clockTimer: Timer?

    /// timeDescenderPhaseTwo: the Descender falls and The Clock begins.
    private func startClock(_ spoken: String) {
        var r = run
        r.enemy = TimeDescender.clock
        r.inCombat = true
        r.defending = false
        run = r
        phase = .fighting
        add("⚡ Switching to Phase 2. The Clock.")
        persist()
        if TimeDescender.hasChronoArmor(r) {
            // (The web version locked every button here and never unlocked them.)
            clockWindow = true
            add("✨ Chrono Armor resonates. The clock's power is nullified.")
            Feedback.announce(spoken + " Switching to Phase 2. The Clock. Your Chrono Armor negates the clock. Strike freely.", after: 0.6)
            return
        }
        Feedback.announce(spoken + " Switching to Phase 2. The Clock. It strikes 3 times, 5 seconds apart. You cannot act until it pauses. Then strike once.", after: 0.6)
        clockCycle(after: 4)
    }

    /// Three ticks, 5 seconds apart, then the window.
    private func clockCycle(after delay: Double) {
        clockTimer?.invalidate()
        clockWindow = false
        clockTicking = true
        var ticks = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.phase == .fighting else { return }
            Sound.track("time-descender")
            self.add("⏰ The clock begins.")
            Feedback.announce("The clock begins.")
            self.clockTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] t in
                Task { @MainActor in
                    guard let self, self.phase == .fighting, let e = self.run.enemy, TimeDescender.isClock(e) else { t.invalidate(); return }
                    if ticks >= 3 {
                        t.invalidate()
                        self.clockTicking = false
                        self.clockWindow = true
                        self.playMusic()
                        self.add("⏱ The clock pauses. Attack now.")
                        Feedback.announce("The clock pauses. Your turn. Attack precisely. Heavy strike may miss.")
                        return
                    }
                    ticks += 1
                    var r = self.run
                    var d = self.dice
                    let hit = TimeDescender.tick(&r, dice: &d)
                    self.run = r
                    self.dice = d
                    let line = "⏰ Tick \(ticks) of 3. The clock strikes for \(hit). HP: \(r.hp) of \(r.maxHp)."
                    self.add(line)
                    Sound.sfx("sfx-hurt")
                    Feedback.hit(heavy: true)
                    if r.isDead {
                        t.invalidate()
                        self.clockTicking = false
                        self.playerDied(killedBy: "The Clock", spoken: line)
                        return
                    }
                    self.persist()
                    Feedback.announce(line)
                }
            }
        }
    }

    private func clockHit(_ action: PlayerAction) {
        guard clockWindow else {
            Feedback.announce(clockTicking ? "The clock is striking. Wait for it to pause." : "Wait for the clock.")
            return
        }
        if action == .flee {
            Feedback.announce("You cannot flee from The Clock.")
            return
        }
        var r = run
        var d = dice
        let line = TimeDescender.strike(&r, heavy: action == .heavy, defend: action == .defend, dice: &d)
        run = r
        dice = d
        add(line)
        Sound.sfx(line.hasPrefix("Miss") ? "sfx-heavy-miss" : action == .defend ? "sfx-select" : "sfx-attack")
        if let e = r.enemy, e.isDead {
            clockVictory(line)
            return
        }
        persist()
        if TimeDescender.hasChronoArmor(r) {
            Feedback.announce(line)
            return
        }
        Feedback.announce(line + " The clock endures. Another cycle begins.")
        clockCycle(after: 2)
    }

    /// timeDescenderVictory
    private func clockVictory(_ spoken: String) {
        clockTimer?.invalidate()
        clockTicking = false
        clockWindow = false
        var r = run
        var d = dice
        let levelBefore = r.level
        let (gold, armor) = TimeDescender.victory(&r, store: game.store, dice: &d)
        game.wallet.addGold(gold)
        r.kills += 1
        achievements.increment("timeDescenderDefeated")
        achievements.trackGlobal("totalKills")
        _ = achievements.check()
        Sound.sfx("sfx-victory")
        var msg = "⏳ The Time Descender crumbles. Time flows normally again. +\(gold) gold, +120 XP."
        if armor { msg += " ✨ LEGENDARY DROP: Chrono Armor! The clock will never bind you again." }
        add(msg)
        if r.level > levelBefore {
            levelUp = r.level
            if r.skillChoices.isEmpty { Skills.offer(&r, dice: &d) }
            msg += " Level up! You are now level \(r.level)."
        }
        finish(r, d, phase: r.roomsOnFloor >= r.floorRoomsNeeded && r.roomsOnFloor > 0 ? .floorCleared : .exploring,
               spoken: spoken + " " + msg + (exitsText.map { " " + $0 } ?? ""))
        playMusic()
    }

    // MARK: The Medusa arc

    /// showMedusaChoice: she's beaten; raise the shield or lower it.
    @Published private(set) var medusaChoice = false
    private var medusaResolved = false

    /// medusaRaiseShield: she turns to stone, and it's a normal kill.
    func medusaRaise() {
        guard medusaChoice, let e = run.enemy else { return }
        medusaChoice = false
        medusaResolved = true
        add("You raise the shield. The gaze reflects. Medusa turns to stone.")
        enemyDefeated(e, spoken: "You raise the shield. The gaze reflects. Medusa turns to stone.")
    }

    /// medusaLowerShield: mercy. She walks with you until her father is found.
    func medusaLower() {
        guard medusaChoice else { return }
        medusaChoice = false
        var r = run
        let line = Medusa.spare(&r)
        add(line)
        var said = line
        if !earnedSpirits.contains("medusa-spirit") {
            earnSpirit("medusa-spirit")
            Sound.sfx("sfx-unlock")
            add("✦ Medusa spirit unlocked permanently. She guards those who showed her mercy.")
            said += " Medusa spirit unlocked permanently. She guards those who showed her mercy."
        }
        achievements.increment("medusaMercy")
        _ = achievements.check()
        finish(r, dice, phase: r.roomsOnFloor >= r.floorRoomsNeeded && r.roomsOnFloor > 0 ? .floorCleared : .exploring,
               spoken: said + (exitsText.map { " " + $0 } ?? ""))
        playMusic()
    }

    /// She Still Looks: the run ends with Medusa still searching for her father.
    private func medusaStillLooking(_ r: Run) {
        guard Medusa.walksWithYou(r) else { return }
        achievements.increment("medusaStillLooks")
        _ = achievements.check()
        add("🐍 Medusa never found her father. She still looks for him.")
    }

    // MARK: The Whispering Forest

    private var forestTimer: Timer?

    /// startCorruptionSystem: 1% every 8 seconds spent exploring the forest.
    /// It waits while a fight, an event, the shop or a choice is open.
    private func startForest() {
        forestTimer?.invalidate()
        forestTimer = nil
        guard WhisperingForest.here(run) else { return }
        forestTimer = Timer.scheduledTimer(withTimeInterval: WhisperingForest.tickSeconds, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self, self.phase != .victory, self.phase != .defeat else { t.invalidate(); return }
                self.forestTick()
            }
        }
    }

    private func forestTick() {
        guard phase == .exploring, levelUp == nil, !hunterChoice, run.stalker == nil, run.skillChoices.isEmpty,
              !Subclasses.pending(run), blacksmith == nil, !showingHome else { return }
        var r = run
        let lines = WhisperingForest.corrupt(&r, 1)
        lines.forEach { add($0) }
        if r.hp <= 0 {
            run = r
            playerDied(killedBy: "the forest's corruption", spoken: lines.joined(separator: " "))
            return
        }
        run = r
        persist()
        if !lines.isEmpty {
            Sound.sfx(r.forestCorruption >= 75 ? "sfx-sanity-critical" : "sfx-sanity-warning")
            Feedback.announce(lines.joined(separator: " "))
        }
    }

    // MARK: The Security Room

    private var securityTimer: Timer?

    /// The growl from the Darkness Swallower's camera, in 3D, and the clock.
    /// It waits for the room's announcement before counting down.
    private func startSecurityRoom(_ dir: Compass) {
        stopSecurityRoom()
        var left = ShadowEvents.securitySeconds + 8
        SpatialAudio.shared.sound("monster-growl.mp3", at: SpatialAudio.point(dir, 3), delay: 0.5)
        securityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self, self.phase == .event, ShadowEvents.securityDirection(self.run.pendingEvent) == dir else { t.invalidate(); return }
                left -= 1
                if Int(left) % 4 == 0 { SpatialAudio.shared.sound("monster-growl.mp3", at: SpatialAudio.point(dir, 3)) }
                if left == 10 { Feedback.announce("10 seconds remaining.") }
                if left == 5 { Feedback.announce("5 seconds. Hurry.") }
                if left <= 0 { self.chooseEvent(-1) }
            }
        }
    }

    private func stopSecurityRoom() {
        securityTimer?.invalidate()
        securityTimer = nil
    }

    // MARK: Hunter Mode

    /// Fight or run: the hunter is two rooms away or less.
    @Published private(set) var hunterChoice = false
    /// The hunter's latest line, spoken after the room you walked into.
    private var hunterLine = ""
    /// It just came within two rooms: ask once the room has played out.
    private var hunterAsk = false
    /// Which way you last walked in 3D Mode: the hunter follows from behind.
    private var lastMove: Compass?
    private var heartbeatTimer: Timer?

    private func takeHunterLine() -> String {
        defer { hunterLine = "" }
        return hunterLine.isEmpty ? "" : " " + hunterLine
    }

    /// hunterTurn after a move or a won fight. False when it caught you
    /// (which has already been handled).
    private func hunterMoves(prefix: String = "") -> Bool {
        var r = run
        hunterAsk = false
        guard let step = Hunter.advance(&r) else { return true }
        run = r
        switch step {
        case .caught:
            hunterCaught(prefix)
            return false
        case .closer(let dist, let line), .choose(let dist, let line):
            add(line)
            hunterLine = line
            hunterAsk = dist <= 2
            if dist == 3 { hunterLine += guideSays(.hunterClose, r) }
            hunterSounds(dist)
            return true
        }
    }

    /// After the room: two rooms away and not in a fight means choose.
    private func hunterAfterRoom() {
        guard hunterAsk, !hunterChoice, let h = run.hunter, h.dist <= 2, phase != .fighting, phase != .defeat, phase != .victory, run.stalker == nil else { return }
        if !hunterLine.isEmpty { Feedback.announce(takeHunterLine(), after: 0.8) }
        hunterAsk = false
        hunterChoice = true
        Feedback.announce("The hunter is almost here. Choose: Fight the hunter, or Run and sprint away.", after: 1.0)
    }

    /// Where it's coming from: the door you came through in 3D Mode, otherwise behind you.
    private var hunterFrom: Compass { lastMove?.opposite ?? .south }

    private func hunterSounds(_ dist: Int) {
        SpatialAudio.shared.hunterPulse(dist, from: hunterFrom)
        if dist <= 2 { Feedback.warning() } else { Feedback.tap() }
        startHeartbeat(dist)
        if dist <= 3 && phase != .fighting { Sound.track("hunter-theme") }
    }

    /// The heartbeat from 5 rooms, faster the closer it is.
    private func startHeartbeat(_ dist: Int) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        guard let gap = Hunter.heartbeat(dist) else { return }
        SpatialAudio.shared.heartbeat(dist, from: hunterFrom)
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: gap, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self, let h = self.run.hunter, self.phase != .defeat, self.phase != .victory else { t.invalidate(); return }
                SpatialAudio.shared.heartbeat(h.dist, from: self.hunterFrom)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    /// hunterFight: stand your ground. The Hunter is a boss; there's no fleeing.
    func hunterFight() {
        guard hunterChoice else { return }
        hunterChoice = false
        stopHeartbeat()
        var r = run
        let e = Hunter.enemy(level: r.level)
        r.hunter = nil
        Combat.begin(&r, against: e).forEach { add($0) }
        let msg = "🏹 THE HUNTER attacks! HP: \(e.hp). ATK: \(e.atk.lowerBound)-\(e.atk.upperBound). This is the fight of your life."
        add(msg)
        setEvent(msg, tone: "danger")
        SpatialAudio.shared.hunterScare(close: false)
        hunterLine = ""
        finish(r, dice, phase: .fighting, spoken: msg)
        playMusic()
    }

    /// hunterRun: sprint into the next room with it one room behind you.
    func hunterRun() {
        guard hunterChoice else { return }
        hunterChoice = false
        var r = run
        let msg = Hunter.sprint(&r)
        run = r
        add(msg)
        hunterSounds(1)
        if phase == .exploring && !threeD {
            movePrefix = msg + " "
            enterRoom()
        } else {
            persist()
            Feedback.announce(msg + (exitsText.map { " " + $0 } ?? ""))
        }
    }

    /// hunterCatch: a life lost and it circles back, or the end.
    private func hunterCaught(_ prefix: String) {
        var r = run
        stopHeartbeat()
        hunterChoice = false
        hunterLine = ""
        SpatialAudio.shared.hunterScare(close: true)
        Sound.sfx("sfx-death")
        Feedback.warning()
        let msg = "🏹 The hunter reaches you. There is nowhere left to run. You have been defeated."
        add(msg)
        achievements.record(.died)
        let said = (prefix.isEmpty ? "" : prefix + " ") + msg + corruptionLifeLost(&r)
        guard Hunter.caught(&r) else {
            runOver(r, killedBy: "The Hunter", spoken: said + " Defeated. The hunter claims you. All lives lost.")
            return
        }
        let back = "🏹 The hunter circles back. It is 8 rooms away. Do not waste this chance. Lives remaining: \(r.lives)."
        add(back)
        finish(r, dice, phase: r.roomsOnFloor >= r.floorRoomsNeeded && r.roomsOnFloor > 0 ? .floorCleared : .exploring,
               spoken: said + " " + back + (exitsText.map { " " + $0 } ?? ""))
        hunterSounds(8)
        playMusic()
    }

    /// hunterSlain: Hunter Mode is over for this run.
    private func hunterSlain(_ spoken: String) {
        var r = run
        stopHeartbeat()
        let (xp, gold) = Hunter.slain(&r)
        r.enemy = nil
        r.inCombat = false
        r.gold += gold
        game.wallet.addGold(gold)
        r.kills += 1
        let levels = Progression.gainXP(&r, xp)
        achievements.record(.enemyKilled(Hunter.enemy(level: r.level), run: r))
        Sound.sfx("sfx-victory")
        Feedback.success()
        var msg = "🏹 THE HUNTER IS DEAD. You stood your ground and won. The dungeon is yours. Hunter Mode deactivated. Hunter's Trophy, \(gold) gold and \(xp) XP."
        add(msg)
        setEvent(msg, tone: "good")
        if levels > 0 {
            var d = dice
            if r.skillChoices.isEmpty { Skills.offer(&r, dice: &d) }
            dice = d
            levelUp = r.level
            achievements.record(.levelReached(r.level))
            msg += " Level up! You are now level \(r.level)."
        }
        finish(r, dice, phase: r.roomsOnFloor >= r.floorRoomsNeeded && r.roomsOnFloor > 0 ? .floorCleared : .exploring,
               spoken: spoken + " " + msg + (exitsText.map { " " + $0 } ?? ""))
        playMusic()
    }

    // MARK: Shake to Attack

    /// A shake attacks; a hard shake uses the first skill you can afford.
    func shakeAttack(hard: Bool) {
        guard phase == .fighting, levelUp == nil, !hunterChoice else { return }
        Feedback.hit()
        if hard, let s = skills.first(where: { skillCost($0) <= run.sp }) {
            add("📳 Shake attack! Unleashing \(s.name)!")
            Feedback.announce("Shake attack! Unleashing \(s.name)!")
            useSkill(s.effect)
        } else {
            act(.attack)
        }
    }

    // MARK: Your guide

    var guideName: String { Guide.name(game.store) }

    /// A line from your guide, logged and returned to be said with the moment.
    private func guideSays(_ m: Guide.Moment, _ r: Run) -> String {
        guard let p = r.guide else { return "" }
        var d = SystemDice()
        guard let line = Guide.line(m, personality: p, level: r.level, dice: &d) else { return "" }
        add("💬 \(guideName): \(line)")
        return " \(guideName) says — \(line)"
    }

    /// The pause menu's Guide switch (toggleGuideFromPause), kept on the character.
    func toggleGuide() {
        var r = run
        let on = r.guide == nil
        r.guide = on ? game.characters[characterIndex].guidePersonality : nil
        run = r
        game.updateCharacter(characterIndex) { $0.guideEnabled = on }
        persist()
        Feedback.announce("Guide " + (on ? "enabled. \(guideName) will speak again." : "disabled. \(guideName) is silent."))
    }

    /// The pause menu's Hunter switch (toggleHunterMode).
    func toggleHunter() {
        var r = run
        let on = r.hunter == nil
        if on {
            r.hunter = Hunter.State()
            add("🏹 Hunter Mode enabled. Something stirs in the dark. It is 10 rooms behind you.")
        } else {
            r.hunter = nil
            stopHeartbeat()
            hunterChoice = false
            add("🏹 Hunter Mode disabled. The dungeon is silent again.")
        }
        run = r
        game.updateCharacter(characterIndex) { $0.hunterMode = on }
        persist()
        playMusic()
        Feedback.announce(on ? "Hunter Mode enabled. Something stirs in the dark. It is 10 rooms behind you."
                             : "Hunter Mode disabled. The dungeon is silent again.")
    }

    // MARK: Corruption Mode

    /// A life lost darkens the character's soul (saved on the character).
    private func corruptionLifeLost(_ r: inout Run) -> String {
        guard let (total, lines) = Corruption.lifeLost(&r) else { return "" }
        game.updateCharacter(characterIndex) { $0.corruption = total }
        lines.forEach { add($0) }
        if total >= 50 { Sound.sfx("sfx-sanity-critical") } else { Sound.sfx("sfx-sanity-warning") }
        return " " + lines.joined(separator: " ")
    }

    // MARK: Bounties

    /// The active bounty while it's running, for the dungeon banner.
    @Published private(set) var bountyBanner: String? = nil

    /// Counts a kill toward the active bounty; pays it out when done.
    private func bountyKill(_ e: Enemy, _ r: Run) -> String {
        bounty(.kill(name: e.name, elite: e.isElite, boss: e.isBoss, dungeon: r.dungeon))
    }

    private func bounty(_ ev: Bounties.Event) -> String {
        let done = Bounties.record(ev, store: game.store)
        defer { bountyBanner = Bounties.banner(game.store) }
        guard let b = done else { return "" }
        Bounties.complete(b, store: game.store, wallet: game.wallet)
        _ = achievements.check()
        add("📋 Bounty Complete! \(b.title). +\(b.gold) gold, +\(b.trophies) trophies.")
        Sound.sfx("sfx-purchase")
        return " Bounty complete! \(b.title) finished. You earned \(b.gold) gold and \(b.trophies) \(b.trophies == 1 ? "trophy" : "trophies")."
    }

    /// The ambush: two or three enemies at once (startMultiCombat).
    private func startAmbush(_ r: inout Run, _ d: inout SystemDice, label: String) -> String? {
        let foes = Combat.ambushers(for: r, dice: &d)
        guard foes.count >= 2 else { return nil }
        let lines = Combat.beginAmbush(&r, foes)
        add(label)
        lines.forEach { add($0) }
        enemyCue(Soundtrack.enemyCue(dungeon: r.dungeon, boss: false))
        Sound.track(Soundtrack.battleTrack(dungeon: r.dungeon))
        let names = foes.map { "\($0.name), \($0.hp) HP" }.joined(separator: ". ")
        return "Ambush! \(foes.count) enemies. \(names). Your attacks hit your target; switch targets with the target buttons."
    }

    /// Switch which ambusher your attacks hit.
    func target(_ index: Int) {
        guard phase == .fighting, run.foes.indices.contains(index) else { return }
        var r = run
        Combat.retarget(&r, to: index)
        run = r
        if let e = r.enemy { Feedback.announce("Targeting \(e.name), \(e.hp) HP.") }
    }

    private func enemyDefeated(_ e: Enemy, spoken: String, result: TurnResult? = nil) {
        // Medusa falls: raise the shield or lower it.
        if Medusa.isMedusa(e) && !medusaResolved {
            medusaChoice = true
            persist()
            Feedback.announce(spoken + " Medusa is defeated. You have a choice. Raise the shield and end it. Or lower the shield and wait. What do you do?", after: 0.6)
            return
        }
        medusaResolved = false
        if TimeDescender.isDescender(e) {
            if TimeDescender.isClock(e) { clockVictory(spoken) } else { startClock(spoken) }
            return
        }
        if SpecialEncounters.isWitness(e) {
            witnessChooses(spoken)
            return
        }
        if Hunter.isHunter(e) {
            hunterSlain(spoken)
            return
        }
        var r = run
        var d = dice
        let reward = Progression.rewardKill(&r, e, dice: &d, wallet: game.wallet)
        add(reward.message)
        var dropLine = ""
        if let w = r.weather, w.hpPerKill > 0, r.hp < r.maxHp {
            r.hp = min(r.maxHp, r.hp + w.hpPerKill)
            add("\(w.icon) \(w.name) — plus \(w.hpPerKill) HP from the kill.")
        }
        if let line = HollowEvents.onKill(e, &r) {
            add(line)
            dropLine += " " + line
            achievements.increment("musicBoxDefeated")
        }
        if let drop = Inventory.equipmentDrop(&r, dice: &d) {
            add("🎁 Found: \(drop.icon) \(drop.name) Level \(drop.level ?? 1)! Check inventory.")
            dropLine = " Item found. \(drop.name) Level \(drop.level ?? 1). Open inventory to equip it."
        }
        if let part = Guns.drop(store: game.store, dice: &d) {
            add("\(part.icon) \(e.name) drops a \(part.name)!")
            dropLine += " \(e.name) dropped a \(part.name). Gun crafting part collected."
        }
        GunBelt.shared.killed()
        dropLine += craftingDrops(e, r.floor, &d)
        if let scroll = Spells.drop(&r, dice: &d) {
            let rarity = { if case .string(let x)? = scroll.extra["rarity"] { return x }; return "common" }()
            add("📜 \(scroll.name) dropped! [\(rarity.uppercased())]")
            dropLine += " Spell scroll dropped! \(scroll.name). \(rarity) rarity. Check your inventory."
            Sound.sfx("sfx-loot")
        }
        Sound.sfx("sfx-enemy-die")
        achievements.record(.enemyKilled(e, run: r))
        if reward.gold > 0 { achievements.trackGlobal("totalGold", Double(reward.gold)) }
        game.checkLegends(r)
        if let milestone = game.recordBestiaryKill(e.name) {
            Sound.sfx("sfx-unlock")
            add("✦ " + milestone)
            Feedback.announce(milestone)
        }
        if reward.levelsGained > 0 { achievements.record(.levelReached(r.level)) }
        dropLine += bountyKill(e, r)
        var said = spoken + " " + reward.message + dropLine
        HighScore.add("enemy_kills", 10, store: game.store)
        if e.isElite { HighScore.add("elite_kills", 150, store: game.store) }
        if e.isBoss {
            HighScore.add("boss_kills", 500, store: game.store)
            HighScore.add("dungeon_clears", 1000, store: game.store)
        }
        said += quest(&r, "kills")
        if e.isElite { said += quest(&r, "elite") }
        if reward.gold > 0 { said += quest(&r, "gold", reward.gold) }
        if r.fight.damageTaken == 0 { said += quest(&r, "nodmg") }
        if e.isBoss {
            journal("Defeated \(e.name) — the dungeon boss falls. Gold: \(r.gold). Enemies slain: \(r.kills).", in: &r)
        } else if r.kills % 5 == 0 {
            journal("Reached \(r.kills) kills. Still standing. HP: \(r.hp)/\(r.maxHp).", in: &r)
        }
        if e.isBoss {
            said += quest(&r, "boss")
            if r.dungeon == "The Hollow" { said += quest(&r, "hollow") }
        }
        if reward.levelsGained > 0 {
            add("Level up! You are now level \(r.level). You have \(r.levelPoints) level points to spend.")
            Sound.sfx("sfx-levelup")
            said += " Level up! You are now level \(r.level). You have \(r.levelPoints) Level Points. Spend them to increase your stats. Unspent points carry over."
            said += guideSays(.levelUp, r)
            if r.skillChoices.isEmpty { Skills.offer(&r, dice: &d) }
            levelUp = r.level
        }
        // Spirit on-kill effects, and the 30% chance of an elite spirit.
        var spiritLines: [String] = []
        let found = Spirits.kill(&r, dice: &d, log: &spiritLines)
        if found > 0 { game.wallet.addGold(found) }
        spiritLines.forEach { add($0) }
        if let cur = Events.awardOnKill(r, store: game.store, dice: &d) {
            add("\(cur.icon) +1 \(cur.name)")
            said += " Plus one \(cur.name)."
        }
        if e.isElite, let sp = Spirits.eliteReward(earned: earnedSpirits, dice: &d) {
            earnSpirit(sp.id)
            Sound.sfx("sfx-unlock")
            add("★ Elite Spirit: \(sp.icon) \(sp.name) unlocked! \(sp.ability)")
            said += " Elite Spirit unlocked! \(sp.name) has joined you. \(sp.ability)"
        }
        r.floorStats.kills += 1
        Feedback.success()
        // An ambush fights on: the core already brought the next enemy up and
        // let the rest strike.
        if let res = result, res.ambushContinues {
            if res.playerDied {
                run = r; dice = d
                playerDied(killedBy: r.enemy?.name ?? "the ambush", spoken: said)
                return
            }
            finish(r, d, phase: .fighting, spoken: said + " " + (res.announcement ?? ""))
            return
        }
        // Killed outside a turn (a thrown item) with ambushers left: the next one steps up.
        if !r.foes.isEmpty {
            r.enemy = r.foes.removeFirst()
            r.inCombat = true
            finish(r, d, phase: .fighting, spoken: said + " \(r.enemy?.name ?? "The next enemy") steps up.")
            return
        }
        r.enemy = nil
        r.inCombat = false
        if Chimera.isPart(e) {
            let corrupted = e.flag("corrupted")
            let levels = r.level
            let (g, xp) = Chimera.victory(&r, corrupted: corrupted, dice: &d)
            game.wallet.addGold(g)
            _ = Progression.gainXP(&r, xp)
            achievements.increment("chimeraKills")
            _ = game.recordBestiaryKill(corrupted ? "The Corrupted Chimera" : "The Chimera")
            _ = achievements.check()
            Sound.sfx("sfx-victory")
            let line = "🐉 \(corrupted ? "The Corrupted Chimera" : "The Chimera") collapses. All parts destroyed. +\(g) gold and \(xp) XP."
            add(line)
            said += " " + line
            if r.level > levels { levelUp = r.level; if r.skillChoices.isEmpty { Skills.offer(&r, dice: &d) } }
        }
        // killing an enemy = one turn passed: the hunter comes closer.
        if r.hunter != nil {
            run = r
            dice = d
            guard hunterMoves(prefix: said) else { return }
            r = run
        }
        if e.mechanics["guardian"] == .bool(true) {
            r.guardianDone = true
            // 3D Mode: the final chamber is a room of its own beyond this one.
            r.roomGraph?.ensureRooms(left: 1, dice: &d)
            said += " The Elite Guardian falls. The final chamber is open."
            finish(r, d, phase: .exploring, spoken: said + (exitsText.map { " " + $0 } ?? ""))
            playMusic()
            return
        }
        if e.isBoss {
            run = r
            dice = d
            victory(said)
        } else if r.roomsOnFloor >= r.floorRoomsNeeded {
            add("Floor \(r.floor) complete.")
            floorDone(r)
            finish(r, d, phase: .floorCleared, spoken: said + " " + floorCompleteLine(r))
            playMusic()
        } else {
            finish(r, d, phase: .exploring, spoken: said + (exitsText.map { " " + $0 } ?? ""))
            playMusic()
        }
    }

    /// A coward ran off, dropping gold. The room counts as cleared.
    // MARK: Blacksmith

    @Published var blacksmith: BlacksmithModel?

    /// openBlacksmith from the dungeon: run gold, your bag and your gear.
    func openBlacksmith() {
        let f = Forge(weapon: run.equippedWeapon, armor: run.equippedArmor, bag: run.inventory, gold: run.gold, prof: run.prof)
        blacksmith = BlacksmithModel(game: game, forge: f, fromMenu: false, sp: run.sp, maxSp: run.maxSp) { [weak self] f, sp in
            guard let self else { return }
            self.run.equippedWeapon = f.weapon
            self.run.equippedArmor = f.armor
            self.run.inventory = f.bag
            self.run.gold = f.gold
            self.run.sp = sp
            // Like the web version, gear bought or upgraded here is saved right away.
            f.stashed.forEach { self.game.globalInventory.add($0) }
            self.game.globalInventory.saveEquipped(weapon: f.weapon, armor: f.armor)
            self.persist()
        }
    }

    func closeBlacksmith() {
        blacksmith = nil
        playMusic()
        Feedback.announce("Blacksmith closed.")
    }

    // MARK: Spirits

    /// Spirits this character has earned (earnedSpirits).
    var earnedSpirits: Set<String> {
        guard game.characters.indices.contains(characterIndex),
              case .array(let a)? = game.characters[characterIndex].extra["earnedSpirits"] else { return [] }
        return Set(a.compactMap { if case .string(let s) = $0 { return s }; return nil })
    }

    private func earnSpirit(_ id: String) {
        game.updateCharacter(characterIndex) { ch in
            var list: [JSONValue] = []
            if case .array(let a)? = ch.extra["earnedSpirits"] { list = a }
            if !list.contains(.string(id)) { list.append(.string(id)) }
            ch.extra["earnedSpirits"] = .array(list)
        }
        achievements.setGlobalMax("spiritsEarned", Double(earnedSpirits.count))
    }

    /// The pause menu's spirit list: switch your companion. The Market
    /// Sprite costs 50 gold to bring back once its discount has been used.
    func switchSpirit(_ id: String) {
        guard let sp = Spirits.spirit(id), run.spirit != id else { return }
        let used = game.characters[characterIndex].extra["marketSpriteUsed"] == .bool(true)
        if id == "market-sprite" && used {
            guard run.gold >= 50, game.wallet.spendGold(50) else {
                Feedback.announce("Not enough gold to reactivate the Market Sprite. You need 50 gold.")
                return
            }
            run.gold -= 50
            add("Paid 50g to reactivate Market Sprite.")
        }
        run.spirit = id
        game.updateCharacter(characterIndex) { $0.lastSpirit = id }
        persist()
        Feedback.announce("You chose \(sp.name). \(sp.ability)")
    }

    // MARK: Home (#ov-home)

    @Published var showingHome = false
    /// The dream from the last sleep, shown until you wake up.
    @Published var dream: Home.Dream?

    func openHome() {
        showingHome = true
        Sound.track("home")
        Feedback.announce("Home. Your dwelling on the edge of the dungeon. Rest, store gold, and upgrade your skills here.")
    }

    func closeHome() {
        showingHome = false
        dream = nil
        playMusic()
    }

    /// Home spends and stores your global gold; the run's gold mirrors it.
    // MARK: Forge, Alchemy and the Elixir Vendor (Home tabs)

    /// The weapon on the anvil, waiting to be kept or rerolled.
    @Published var forged: Item?

    func forgeCraft(_ id: String) -> String {
        var d = dice
        guard let w = WeaponForge.craft(id, store: game.store, dice: &d) else { return "Not enough materials." }
        dice = d
        forged = w
        Sound.sfx("sfx-confirm")
        let range = w.weaponAttack
        let fx = w.forgeEffect.flatMap(WeaponForge.effect)
        let said = "Crafted \(w.name)! ATK \(range.lowerBound) to \(range.upperBound). " + (fx.map { "Special effect: \($0.name). \($0.desc)" } ?? "No special effect.")
        Feedback.announce(said)
        return ""
    }

    func forgeReroll() -> String {
        guard let w = forged else { return "" }
        var d = dice
        guard let out = WeaponForge.reroll(w, store: game.store, dice: &d) else {
            Feedback.announce("Not enough Iron Scraps to reroll. Need 2.")
            return "Need 2 Iron Scraps to reroll."
        }
        dice = d
        forged = out
        if let fx = out.forgeEffect.flatMap(WeaponForge.effect) { Feedback.announce("Rerolled! New effect: \(fx.name). \(fx.desc)") }
        return ""
    }

    func forgeKeep() -> String {
        guard let w = forged else { return "" }
        let kept = WeaponForge.keep(w, store: game.store)
        // Into this run's pack too, so it can be equipped now.
        run.inventory.append(kept)
        forged = nil
        _ = achievements.check()
        persist()
        Sound.sfx("sfx-loot")
        Feedback.announce("\(kept.name) added to your inventory and your stash. Equip it from your inventory.")
        return "\(kept.name) added to your inventory!"
    }

    func buyIngredient(_ id: String) -> String {
        let msg = Alchemy.buy(id, store: game.store, wallet: game.wallet)
        syncGold()
        if msg.hasPrefix("Bought") { Sound.sfx("sfx-select") }
        Feedback.announce(msg)
        return msg
    }

    func brew(_ id: String) -> String {
        var d = dice
        let alch = run.cls == "Alchemist"
        guard let b = Alchemy.craft(id, alchemist: alch, store: game.store, dice: &d) else {
            Feedback.announce("Not enough ingredients.")
            return "Not enough ingredients."
        }
        dice = d
        run.inventory.append(b.potion)
        persist()
        Sound.sfx("sfx-confirm")
        let p = b.potion
        if b.mishap {
            Feedback.announce("Unstable brew! You got a \(p.name) instead.")
            return "Something went wrong with the brew... You got: \(p.icon) \(p.name). \(p.desc)"
        }
        Feedback.announce("Crafted \(p.name)!" + (alch ? " Alchemist bonus applied." : ""))
        return "Crafted: \(p.icon) \(p.name). \(p.desc)" + (alch ? " (Alchemist bonus applied!)" : "")
    }

    func sellElixir(_ name: String) {
        var r = run
        guard let msg = ElixirVendor.sell(name, &r, wallet: game.wallet) else { return }
        run = r
        syncGold()
        Sound.sfx("sfx-select")
        Feedback.announce(msg)
    }

    func buyDailyElixir() -> String {
        var r = run
        let msg = ElixirVendor.buy(&r, store: game.store, wallet: game.wallet)
        run = r
        syncGold()
        if msg.hasPrefix("Bought") { Sound.sfx("sfx-confirm") }
        Feedback.announce(msg)
        return msg
    }

    private func syncGold() {
        run.gold = game.wallet.gold
        persist()
    }

    func buyHome() -> String {
        guard Home.buyHome(store: game.store, wallet: game.wallet) else {
            Feedback.announce("Not enough gold.")
            return "Not enough gold. Need \(Home.cost)g, have \(game.wallet.gold)g."
        }
        syncGold()
        Sound.sfx("sfx-unlock")
        Feedback.announce("Home purchased! Your dwelling is now available from the dungeon action buttons.")
        return ""
    }

    func buyBed() -> String {
        guard Home.buyBed(store: game.store, wallet: game.wallet) else {
            Feedback.announce("Not enough gold.")
            return "Need \(Home.bedCost)g."
        }
        syncGold()
        Sound.sfx("sfx-confirm")
        Feedback.announce("Bed purchased! Sleep at home to restore HP and SP fully.")
        return ""
    }

    func sleep() {
        var r = run
        var d = dice
        guard let dr = Home.sleep(&r, store: game.store, dice: &d) else {
            Feedback.announce("Not enough rooms explored to sleep yet.")
            return
        }
        run = r
        dice = d
        game.updateCharacter(characterIndex) { $0.extra["dream"] = .string(dr.id) }
        persist()
        Sound.sfx("sfx-confirm")
        dream = dr
        Feedback.announce("You sleep deeply. HP and SP fully restored. \(dr.title). \(dr.story) \(dr.buff)")
    }

    func deposit(_ amount: Int) -> String {
        guard amount > 0 else { return "Enter a valid amount." }
        guard amount <= game.wallet.gold else { return "Only have \(game.wallet.gold)g." }
        _ = Home.deposit(amount, store: game.store, wallet: game.wallet)
        syncGold()
        let safe = Home.safe(game.store)
        Feedback.announce("Deposited \(amount) gold. Safe holds \(safe) gold.")
        return "Deposited \(amount)g. Safe: \(safe)g."
    }

    func withdraw(_ amount: Int) -> String {
        guard amount > 0 else { return "Enter a valid amount." }
        let safe = Home.safe(game.store)
        guard amount <= safe else { return "Safe only has \(safe)g." }
        _ = Home.withdraw(amount, store: game.store, wallet: game.wallet)
        syncGold()
        Feedback.announce("Withdrew \(amount) gold from the safe.")
        return "Withdrew \(amount)g. Safe remaining: \(safe - amount)g."
    }

    func upgradeSkill(_ name: String) -> String {
        let msg = Home.upgradeSkill(cls: run.cls, name: name, store: game.store, wallet: game.wallet)
        if msg.contains("upgraded") {
            run.skillLevels = Home.skillLevels(game.store)
            syncGold()
            Sound.sfx("sfx-unlock")
            Feedback.announce(msg)
            return msg.replacingOccurrences(of: ".", with: "!")
        }
        return msg
    }

    /// Activate or deactivate a minion; it joins the fight right away.
    func toggleMinion(_ m: Minion) -> String {
        if Home.activeMinion(game.store)?.id == m.id {
            Home.setActive(nil, store: game.store)
            run.minion = nil
            persist()
            return "Minion deactivated."
        }
        Home.setActive(m.id, store: game.store)
        run.minion = m
        persist()
        Feedback.announce("\(m.name) activated. They will fight alongside you.")
        return "\(m.name) will fight with you!"
    }

    func releaseMinion(_ m: Minion) {
        Home.release(m.id, store: game.store)
        if run.minion?.id == m.id { run.minion = nil; persist() }
        Feedback.announce("\(m.name) released.")
    }

    /// Shown in combat when a Soul Trap is in the bag and the enemy isn't a boss.
    var canSoulTrap: Bool {
        phase == .fighting && run.enemy?.isBoss == false && run.foes.isEmpty && run.inventory.contains { $0.type == "soul-trap" }
    }

    /// doFight('soul-trap'): capture the enemy as a minion; the fight ends.
    func soulTrap() {
        guard phase == .fighting, let e = run.enemy else { return }
        var r = run
        switch Home.capture(&r, store: game.store) {
        case .boss: Feedback.announce("You cannot capture bosses.")
        case .noTrap: Feedback.announce("No Soul Trap in inventory.")
        case .duplicate: Feedback.announce("You already have a \(e.name) as a minion.")
        case .full: Feedback.announce("You already have \(Home.maxMinions) minions. Release one at Home first.")
        case .captured(let m):
            add("🪤 \(e.name) captured as a minion!")
            Sound.sfx("sfx-unlock")
            let done = r.roomsOnFloor >= r.floorRoomsNeeded
            if done { floorDone(r) }
            finish(r, dice, phase: done ? .floorCleared : .exploring,
                   spoken: "🪤 \(e.name) has been captured. It is now your minion. You captured \(m.tier == "elite" ? "an Elite " : "a ")\(m.name)! Find them in your Home under Minions."
                       + (done ? " " + floorCompleteLine(r) : ""))
            playMusic()
        }
    }

    private func enemyFled(_ result: TurnResult, spoken: String) {
        var r = run
        r.gold += result.goldGained
        game.wallet.addGold(result.goldGained)
        let msg = (result.log.last ?? "") + quest(&r, "gold", result.goldGained)
        let done = r.roomsOnFloor >= r.floorRoomsNeeded
        if done { floorDone(r) }
        finish(r, dice, phase: done ? .floorCleared : .exploring,
               spoken: spoken + " " + msg + (done ? " " + floorCompleteLine(r) : ""))
        playMusic()
    }

    private func playerDied(killedBy: String, spoken: String) {
        var r = run
        Feedback.warning()
        let outcome = Progression.handleDeath(&r)
        // logDeath writes every lost life into the journal.
        if outcome != .gearSaved && outcome != .phoenix {
            journal("Fell to \(killedBy) on floor \(r.floor).", in: &r)
        }
        var spoken = spoken
        if outcome == .runOver { spoken += corruptionLifeLost(&r) + guideSays(.death, r) }
        if case .revived = outcome { spoken += corruptionLifeLost(&r) + guideSays(.death, r) }
        if outcome == .runOver && r.bargainStrike > 0 {
            // Death's Bargain (Coin Shop): the final strike lands before the end.
            let name = r.enemy?.name ?? "the enemy"
            add("⚰️ Death's Bargain — final strike for \(r.bargainStrike) damage!")
            spoken += " Death's Bargain activates! Final strike — \(r.bargainStrike) damage to \(name)!"
            if let e = r.enemy, e.isDead {
                add("\(e.name) falls with you.")
                spoken += " \(e.name) falls with you."
                r.kills += 1
                achievements.record(.enemyKilled(e, run: r))
                _ = game.recordBestiaryKill(e.name)
            }
            r.bargainStrike = 0
        }
        achievements.record(.died)
        Sound.sfx(outcome == .runOver ? "sfx-gameover" : "sfx-death")
        switch outcome {
        case .gearSaved:
            if r.enemy != nil { r.inCombat = true }
            let what = r.equippedWeapon?.rarityEffect == "undying" ? "Your Undying blade" : "Your Sanctuary armor"
            let msg = "\(what) refuses death — you survive at 1 HP! It won't save you again on this floor."
            add("💜 " + msg)
            finish(r, dice, phase: r.inCombat ? .fighting : .exploring, spoken: spoken + " " + msg)
        case .resurrected:
            if r.enemy != nil { r.inCombat = true }
            let msg = "Resurrection! You rise again with 50 percent HP."
            add("✨ " + msg)
            finish(r, dice, phase: r.inCombat ? .fighting : .exploring, spoken: spoken + " " + msg)
        case .phoenix:
            // The fight goes on if there was one.
            if r.enemy != nil { r.inCombat = true }
            let msg = "The Phoenix Feather ignites! You rise again at 30 percent HP. The feather crumbles to ash."
            add("🔥 " + msg)
            finish(r, dice, phase: r.inCombat ? .fighting : .exploring, spoken: spoken + " " + msg)
        case .secondWind:
            let msg = "Second Wind! You cling to life with 1 HP. The upgrade has been consumed."
            add("💨 " + msg)
            setEvent(msg, tone: "good")
            finish(r, dice, phase: r.roomsOnFloor >= r.floorRoomsNeeded ? .floorCleared : .exploring,
                   spoken: spoken + " Second Wind activated! You survived with 1 HP. This can only happen once per run.")
            playMusic()
        case .revived(let left):
            let msg = "You died. \(left) \(left == 1 ? "life" : "lives") remaining. Restored to 40 percent health."
            add(msg)
            finish(r, dice, phase: r.roomsOnFloor >= r.floorRoomsNeeded ? .floorCleared : .exploring,
                   spoken: spoken + " " + msg)
            playMusic()
        case .runOver:
            runOver(r, killedBy: killedBy, spoken: spoken)
        }
    }

    /// All lives gone (showDefeat), or the character itself in Hardcore.
    private func runOver(_ r: Run, killedBy: String, spoken: String) {
        stopHeartbeat()
        medusaStillLooking(r)
        if r.hardcore {
            run = r
            phase = .defeat
            game.deleteCharacter(at: characterIndex)
            characterGone = true
            let msg = "💀 HARDCORE — \(r.name) has fallen. This character is gone forever. There are no second chances in Hardcore Mode."
            add(msg)
            Feedback.announce(spoken + " " + msg)
            return
        }
        run = r
        phase = .defeat
        add("Defeated. All lives lost. \(r.name) fell on floor \(r.floor).")
        let floor = r.floor
        game.updateCharacter(characterIndex) {
            $0.logDeath(floor: floor, killedBy: killedBy, run: r)
            $0.floor = 1
            // Classic runs start over at level 1; Legacy keeps the level
            // but its dungeon tier goes back to 1 (showDefeat).
            if $0.runMode == "legacy" { $0.dungeonTier = 1 } else { $0.persistLevel = 1 }
        }
        game.recordDeath(r, killedBy: killedBy)
        game.clearRun(for: characterIndex)
        killer = killedBy
        Sound.ambient(nil)
        showingDeathCinematic = true
        Feedback.announce(spoken + " " + deathCinematicSpoken)
    }

    private func victory(_ spoken: String) {
        medusaStillLooking(run)
        if let stage = run.gauntletStage, stage + 1 < Challenges.gauntlet.count {
            gauntletNext(stage + 1, spoken)
            return
        }
        phase = .victory
        achievements.record(.runWon(run, diedThisRun: run.diedThisRun,
                                    seconds: Date().timeIntervalSince1970 - run.startedAt))
        Sound.sfx("sfx-victory")
        Sound.ambient(nil)
        summaryMusic(victory: true)
        add("Victory! You have conquered \(run.dungeon).")
        var d = dice
        if let sp = Spirits.victoryReward(run, earned: earnedSpirits, dice: &d) {
            earnSpirit(sp.id)
            add("✦ Rare Spirit Unlocked: \(sp.icon) \(sp.name)! Saved forever.")
            Feedback.announce("Rare Spirit unlocked: \(sp.name)! Saved to your character forever. Requires level 5 to use.")
        }
        if let prize = RunModifiers.bossPrize(&run, dice: &d) {
            add("💀 Death March reward: \(prize.icon) \(prize.name)! Check your inventory.")
            Feedback.announce("Death March reward: a legendary \(prize.name).", after: 1.5)
        }
        if let prize = Corruption.bossPrize(&run, dice: &d) {
            add("☠ Corruption Run reward: \(prize.icon) \(prize.name)! Check your inventory.")
            Feedback.announce("Corruption Run reward: a legendary \(prize.name).", after: 1)
        }
        dice = d
        game.globalInventory.keep(from: run)
        game.checkLegends(run)
        game.recordFirstClear(run)
        if !isChallenge { game.updateCharacter(characterIndex) { $0.completed = true; $0.floor = 10 } }
        game.clearRun(for: characterIndex)
        if let dc = DailyChallenge.complete(run, store: game.store) {
            let line = "⚡ Daily Challenge complete: \(dc.name)! You earned 1 Mystery Coin."
            add(line)
            Sound.sfx("sfx-unlock")
            Feedback.announce(line, after: 3)
        }
        if let line = challengeDone() {
            add(line)
            Feedback.announce(spoken + " " + line + " Return to the menu when you're ready.")
            return
        }
        let next = game.unlockedDungeons().last ?? ""
        let unlock = next != run.dungeon && !next.isEmpty ? " \(next) is unlocked." : ""
        Feedback.announce(spoken + " Victory! You have conquered \(run.dungeon).\(unlock)" + guideSays(.victory, run)
            + (canContinueJourney ? " Continue your journey, start New Game Plus, or return." : " Start New Game Plus, or return."))
    }

    /// buildRunSummary: a clean cut from the fight, 1.2 seconds of silence,
    /// then the victory music or the menu's.
    func summaryMusic(victory: Bool) {
        Sound.ambient(nil)
        Sound.stopMusic()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            // Not if you've already left the summary.
            guard let self, self.phase == .victory || self.phase == .defeat else { return }
            Sound.track(victory ? "raid-victory" : "menu")
        }
    }

    // MARK: Developer Tools

    /// devGodMode
    func devGodMode() {
        var r = run
        r.maxHp = 1_000_000
        r.hp = 1_000_000
        run = r
        persist()
        setEvent("🔧 Dev: God Mode — HP set to 1,000,000.", tone: "good")
        Feedback.announce("God Mode active. HP set to 1 million.")
    }

    /// devJumpFloor10: the boss floor, the Elite Guardian first.
    func devJumpFloor10() {
        var r = run
        r.inCombat = false
        r.enemy = nil
        r.foes = []
        r.floor = Challenges.bossFloor(r)
        r.roomsOnFloor = 0
        r.floorRoomsNeeded = 1
        r.guardianDone = false
        r.upcomingRooms = []
        run = r
        phase = .exploring
        persist()
        setEvent("🔧 Dev: Floor \(r.floor). Move to start the boss sequence.", tone: "good")
        Feedback.announce("Jumped to floor \(r.floor). Move to trigger the elite guardian then the boss.")
    }

    /// devForceAmbush / devForceMedusa: the next room is that fight.
    func devForce(medusa: Bool) {
        var r = run
        if medusa {
            r.medusa.met = false
            r.devMedusa = true
            r.floor = max(r.floor, 4)
        } else {
            r.devAmbush = true
        }
        r.upcomingRooms.insert(.fight, at: 0)
        run = r
        persist()
        let msg = medusa ? (r.dungeon == Medusa.hollow ? "Medusa will spawn in the next room. Navigate to a new room."
                                                         : "Medusa only lives in The Hollow. She'll spawn in the next fight there.")
                         : "Ambush forced. Enter the next room to trigger it."
        setEvent("🔧 Dev: " + msg, tone: "good")
        Feedback.announce(msg)
    }

    // MARK: Challenges

    /// The Gauntlet: the next dungeon at once, same character, HP as it is.
    private func gauntletNext(_ stage: Int, _ spoken: String) {
        var r = run
        var d = dice
        achievements.record(.runWon(r, diedThisRun: r.diedThisRun, seconds: Date().timeIntervalSince1970 - r.startedAt))
        game.recordFirstClear(r)
        Sound.sfx("sfx-victory")
        let next = Challenges.gauntlet[stage]
        r.gauntletStage = stage
        r.dungeon = next
        r.weather = Weather.roll(for: next, dice: &d)
        r.floor = 1
        r.roomsOnFloor = 0
        r.floorRoomsNeeded = RunModifiers.rooms(Rooms.roomsNeeded(floor: 1, difficulty: r.difficulty, dice: &d), r)
        r.upcomingRooms = []
        r.guardianDone = false
        r.enemy = nil
        r.foes = []
        r.inCombat = false
        r.hpAtFloorStart = r.hp
        r.floorStats = FloorStats(goldStart: r.gold)
        Encounters.planFloor(&r, dice: &d)
        r.roomGraph = threeD ? RoomGraph(roomsNeeded: r.floorRoomsNeeded, dice: &d) : nil
        run = r
        dice = d
        shop = []
        phase = .exploring
        roomTitle = Rooms.floorName(1, dungeon: next)
        roomText = ""
        let left = Challenges.gauntlet.count - stage
        add("⚔ Dungeon \(stage) of \(Challenges.gauntlet.count) cleared! Entering \(next). HP carries over.")
        persist()
        playMusic()
        if let g = r.roomGraph { SpatialAudio.shared.setRoom(dungeon: next); add("🧊 3D Mode. \(g.exitsText)") }
        Feedback.announce(spoken + " Dungeon \(stage) cleared! Entering \(next). \(left) \(left == 1 ? "dungeon remains" : "dungeons remain"). HP \(r.hp) of \(r.maxHp) carries over.", after: 0.6)
    }

    /// The end of a Challenge: the Gauntlet's crown or the Daily Dungeon's time.
    private func challengeDone() -> String? {
        if run.gauntletStage != nil {
            achievements.trackGlobal("gauntletClears")
            achievements.award("gauntlet_champion")
            game.store.setItem("dd_gauntlet_best", String(Int(Date().timeIntervalSince1970 * 1000)))
            return "THE GAUNTLET IS COMPLETE! All \(Challenges.gauntlet.count) dungeons cleared. You are the Gauntlet Champion."
        }
        if let key = run.dailyKey {
            let time = Challenges.time(Date().timeIntervalSince1970 - run.dailyStart)
            guard game.store.getItem(key) == nil else { return "Daily Dungeon cleared again in \(time). Your first time today stands." }
            game.store.setItem(key, time)
            achievements.trackGlobal("dailyDungeonClears")
            achievements.award("ach-daily-dungeon")
            return "Daily Dungeon complete! Time: \(time). Come back tomorrow for a new challenge."
        }
        return nil
    }

    // MARK: Skills

    var skills: [Skill] { Skills.unlocked(run) }
    func skillCost(_ s: Skill) -> Int { Skills.cost(s, run) }

    func useSkill(_ effect: String) {
        guard phase == .fighting else { return }
        if let e = run.enemy, TimeDescender.isClock(e) {
            Feedback.announce("Only Attack, Heavy Strike and Defend work against The Clock.")
            return
        }
        var r = run
        var d = dice
        let newSkill = !r.skillsUsed.contains(effect)
        let result = Skills.use(&r, effect, dice: &d, options: .init(classTraits: AppSettings.classTraits))
        guard result.acted else {
            Feedback.announce(result.announcement ?? "You can't use that now.")
            return
        }
        result.log.forEach { add($0) }
        track(&r, result)
        var questLine = newSkill ? quest(&r, "skilluse") : ""
        if (result.enemyDamage ?? 0) > 0 && r.hp > 0 && r.hp <= 10 { questLine += quest(&r, "survive") }
        if result.playerDamage > 0 { Feedback.hit(heavy: result.playerDamage >= 30); Sound.sfx(result.playerDamage >= 30 ? "sfx-crit" : "sfx-attack") }
        else { Sound.sfx("sfx-confirm") }
        if (result.enemyDamage ?? 0) > 0 { Sound.sfx("sfx-hurt") }
        var spoken = result.log.joined(separator: " ") + questLine
        spoken += rewardFallen(result.alsoDefeated, &r, &d)
        if result.fled {
            finish(r, d, phase: r.roomsOnFloor >= r.floorRoomsNeeded ? .floorCleared : .exploring, spoken: spoken)
            playMusic()
            return
        }
        if result.enemyFled {
            run = r; dice = d
            enemyFled(result, spoken: spoken)
            return
        }
        if result.enemyDied, let e = result.defeated ?? r.enemy {
            run = r; dice = d
            enemyDefeated(e, spoken: spoken, result: result)
            return
        }
        if result.playerDied {
            run = r; dice = d
            playerDied(killedBy: r.enemy?.name ?? "the dungeon", spoken: spoken)
            return
        }
        if result.enemyDamage != nil, let a = result.announcement { spoken += " " + a }
        finish(r, d, phase: .fighting, spoken: spoken)
    }

    // MARK: Guns

    var gun: Gun? { phase == .fighting ? Guns.equipped(game.store) : nil }

    /// gunAction's shot: your turn's attack; the enemy answers.
    func shoot(_ g: Gun) {
        guard phase == .fighting else { return }
        var r = run
        var d = dice
        let result = Guns.shoot(&r, g, dice: &d, options: .init(classTraits: AppSettings.classTraits))
        achievements.trackGlobal("totalDmgDealt", Double(result.playerDamage))
        spellDone(result, r, d)
    }

    // MARK: Spells

    var canCast: Bool { phase == .fighting && !run.learnedSpells.isEmpty }

    /// castSpell from the Spell Book: a free action with a cooldown.
    func castSpell(_ id: String) {
        guard phase == .fighting else { return }
        var r = run
        var d = dice
        let result = Spells.cast(&r, id, dice: &d, wallet: game.wallet, options: .init(classTraits: AppSettings.classTraits))
        spellDone(result, r, d)
    }

    /// A spell scroll from the bag: one cast, no cooldown. Outside a fight a
    /// magic class with a Spell Book tries to learn it instead.
    func readScroll(at index: Int) {
        guard run.inventory.indices.contains(index) else { return }
        if !run.inCombat {
            learnScroll(at: index)
            return
        }
        var r = run
        var d = dice
        let result = Spells.read(&r, at: index, dice: &d, wallet: game.wallet, options: .init(classTraits: AppSettings.classTraits))
        spellDone(result, r, d)
    }

    private func learnScroll(at index: Int) {
        let item = run.inventory[index]
        guard case .string(let id)? = item.extra["spellId"], let entry = Spells.entry(id) else { return }
        let ch = game.characters[characterIndex]
        guard Spells.hasBook(ch), Spells.isMagic(ch.cls) || run.subclass == "pure-magic" else {
            Feedback.announce("\(item.name). Read it in combat to cast it once." + (Spells.isMagic(ch.cls) ? " With a Spell Book you could learn it." : ""))
            return
        }
        var r = run
        var d = dice
        r.inventory.remove(at: index)
        var copy = ch
        // A scroll in hand costs nothing more to try.
        let (res, _) = Spells.buy(entry, character: &copy, gold: entry.cost, subclass: r.subclass, dice: &d)
        let msg: String
        switch res {
        case .learned:
            game.updateCharacter(characterIndex) { Spells.setLearned(Spells.learned(copy), on: &$0) }
            r.learnedSpells = Spells.learned(copy)
            msg = "✨ \(entry.name) learned permanently! It is now in your spell book."
            Sound.sfx("sfx-unlock")
        case .alreadyKnown:
            r.inventory.insert(item, at: index)
            msg = "You already know \(entry.name). Read it in combat to cast it once."
        default:
            msg = "📜 Failed to learn \(entry.name). The scroll dissolved."
            Sound.sfx("sfx-select")
        }
        add(msg)
        run = r
        dice = d
        persist()
        Feedback.announce(msg)
    }

    private func spellDone(_ result: TurnResult, _ r0: Run, _ d0: SystemDice) {
        var r = r0, d = d0
        guard result.acted else {
            Feedback.announce(result.announcement ?? "You can't cast that now.")
            return
        }
        result.log.forEach { add($0) }
        track(&r, result)
        Sound.sfx(result.playerDamage > 0 ? "sfx-crit" : "sfx-unlock")
        if result.playerDamage > 0 { Feedback.hit(heavy: true) }
        var spoken = result.announcement ?? result.log.joined(separator: " ")
        if r.spellCooldown > 0 { spoken += " Spells ready again in \(r.spellCooldown) turns." }
        spoken += rewardFallen(result.alsoDefeated, &r, &d)
        if r.fight.loseRealityUntil > 0 { startRealityClock() }
        if result.fled {
            finish(r, d, phase: r.roomsOnFloor >= r.floorRoomsNeeded ? .floorCleared : .exploring, spoken: spoken)
            playMusic()
            return
        }
        if result.enemyDied, let e = result.defeated ?? r.enemy {
            run = r; dice = d
            enemyDefeated(e, spoken: spoken, result: result)
            return
        }
        if result.playerDied || r.isDead {
            run = r; dice = d
            playerDied(killedBy: "a spell gone wrong", spoken: spoken)
            return
        }
        if let b = result.bossPhaseMessage, !spoken.contains(b) { spoken += " " + b }
        if result.bossPhaseMessage != nil { run = r; playMusic() }
        finish(r, d, phase: .fighting, spoken: spoken)
    }

    /// Lose Reality: a minute-by-minute warning, and the end when time's up.
    private var realityTimer: Timer?

    private func startRealityClock() {
        guard realityTimer == nil else { return }
        realityTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.realityTick() }
        }
    }

    private func realityTick() {
        let until = run.fight.loseRealityUntil
        guard until > 0, run.inCombat else {
            realityTimer?.invalidate()
            realityTimer = nil
            return
        }
        let left = Int(((until - Date().timeIntervalSince1970) / 60).rounded(.up))
        if left > 0 {
            add("🌀 Reality slipping. \(left) minute\(left == 1 ? "" : "s") remaining.")
            Feedback.announce("Reality slipping. \(left) minute\(left == 1 ? "" : "s") remaining.")
            return
        }
        realityTimer?.invalidate()
        realityTimer = nil
        var r = run
        r.hp = 0
        r.inCombat = false
        add("🌀 You ceased to exist.")
        run = r
        playerDied(killedBy: "Lose Reality", spoken: "Time is up. You ceased to exist.")
    }

    /// The Arcane Shop during a run: run gold (and your saved gold with it).
    func buySpell(_ entry: SpellEntry) -> String {
        var r = run
        var d = dice
        var ch = game.characters[characterIndex]
        let (res, item) = Spells.buy(entry, character: &ch, gold: r.gold, subclass: r.subclass, dice: &d)
        let msg: String
        switch res {
        case .tooPoor: msg = "Not enough gold. Need \(entry.cost) gold."
        case .alreadyHaveBook: msg = "You already have a Spell Book."
        case .alreadyKnown: msg = "You already know \(entry.name)."
        case .book: msg = "📖 Spell Book acquired. Magic classes can now learn spells permanently."
        case .learned: msg = "✨ \(entry.name) learned permanently! It is now in your spell book."
        case .failedToLearn: msg = "📜 Failed to learn \(entry.name). The scroll dissolved."
        case .scroll: msg = "\(entry.name) added to inventory. One time use in combat."
        }
        if ![.tooPoor, .alreadyHaveBook, .alreadyKnown].contains(res) {
            r.gold -= entry.cost
            _ = game.wallet.spendGold(entry.cost)
            if let item { r.inventory.append(item) }
            r.learnedSpells = Spells.learned(ch)
            let saved = ch
            game.updateCharacter(characterIndex) { $0.extra["spellBook"] = saved.extra["spellBook"]; $0.extra["learnedSpells"] = saved.extra["learnedSpells"] }
            Sound.sfx("sfx-purchase")
            add(msg)
        } else {
            Sound.sfx("sfx-select")
        }
        run = r
        dice = d
        persist()
        return msg
    }

    var character: PlayerCharacter { game.characters[characterIndex] }

    func pickSkill(_ effect: String) {
        var r = run
        guard let s = Skills.pick(&r, effect) else { return }
        Sound.sfx("sfx-unlock")
        run = r
        persist()
        add("✨ You unlocked \(s.name). \(s.desc)")
        Feedback.announce("You unlocked: \(s.name). \(s.desc) Continuing your descent.")
    }

    // MARK: Items

    /// Gambler's Spirit is waiting for Double or Halve.
    @Published var gambling = false

    func useItem(at index: Int) {
        guard phase != .victory && phase != .defeat else { return }
        if run.inCombat && run.fight.noItems > 0 {
            Feedback.announce("The Void Anchor holds you too. No items for \(run.fight.noItems) more turn\(run.fight.noItems == 1 ? "" : "s").")
            return
        }
        if run.inventory.indices.contains(index) && run.inventory[index].type == "spell-scroll" {
            readScroll(at: index)
            return
        }
        if run.inventory.indices.contains(index) && run.inventory[index].type == "gamblers-spirit" {
            startGamble(at: index)
            return
        }
        var r = run
        var d = dice
        let isReveal = r.inventory.indices.contains(index) && r.inventory[index].id == "scroll-reveal"
        let item = r.inventory.indices.contains(index) ? r.inventory[index] : nil
        let hpBefore = r.hp
        let out = Inventory.use(&r, at: index)
        if r.hp > hpBefore { r.floorStats.hpHealed += r.hp - hpBefore }
        if out.used, let item, ["potion", "elixir", "heal"].contains(item.type) {
            r.potionsUsed += 1
            achievements.trackGlobal("totalPotions")
        }
        if out.used, let item, item.type == "elixir" || item.type == "heal" { achievements.record(.elixirUsed) }
        if out.used, let item, WhisperingForest.isMusicBox(item) {
            Sound.track("music-box")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.playMusic() }
        }
        if out.used, let item {
            Sound.sfx(item.isWeapon || item.isArmor ? "sfx-confirm"
                      : ["potion", "elixir", "heal", "sp-potion", "atk-potion", "def-potion", "luck-potion", "swift-potion"].contains(item.type)
                        || Alchemy.tacticalTypes.contains(item.type) ? "sfx-potion"
                      : "sfx-unlock")
        }
        var msg = out.message
        if out.used && isReveal { msg += " " + Inventory.reveal(&r, dice: &d) }
        add(msg)
        run = r
        dice = d
        if out.used { saveGear() }
        if out.enemyDied, let e = r.enemy {
            enemyDefeated(e, spoken: msg)
            return
        }
        persist()
        Feedback.announce(msg)
    }

    /// Gambler's Spirit (Coin Shop): once per run, outside combat.
    private func startGamble(at index: Int) {
        if run.gamblerUsed { Feedback.announce("Gambler's Spirit already used this run."); return }
        if run.inCombat { Feedback.announce("Cannot gamble during combat."); return }
        var r = run
        r.gamblerUsed = true
        r.inventory.remove(at: index)
        run = r
        persist()
        gambling = true
    }

    func gamble(double: Bool) {
        guard gambling else { return }
        gambling = false
        var r = run
        let before = r.gold
        r.gold = double ? before * 2 : before / 2
        if r.gold > before { game.wallet.addGold(r.gold - before) } else { _ = game.wallet.spendGold(before - r.gold) }
        run = r
        persist()
        if double {
            add("🎲 Gambler's Spirit — DOUBLED! \(r.gold) gold!")
            setEvent("🎲 Gambler's Spirit — Fortune smiles. Gold doubled!", tone: "good")
            Feedback.announce("Gambler's Spirit. You doubled your gold. \(r.gold) gold.")
        } else {
            add("🎲 Gambler's Spirit — HALVED. \(r.gold) gold.")
            setEvent("🎲 Gambler's Spirit — The dice were cruel. Gold halved.", tone: "danger")
            Feedback.announce("Gambler's Spirit. You halved your gold. \(r.gold) gold.")
        }
    }

    func unequipWeapon() {
        var r = run
        let msg = Inventory.unequipWeapon(&r)
        run = r
        saveGear()
        persist()
        add(msg)
        Feedback.announce(msg)
    }

    func unequipArmor() {
        var r = run
        let msg = Inventory.unequipArmor(&r)
        run = r
        saveGear()
        persist()
        add(msg)
        Feedback.announce(msg)
    }

    /// Gear is saved as soon as it changes, like equipWeapon() in the web version.
    private func saveGear() {
        game.globalInventory.saveEquipped(weapon: run.equippedWeapon, armor: run.equippedArmor)
    }

    // MARK: Floors and the shop

    func descend() {
        guard phase == .floorCleared else { return }
        var r = run
        var d = dice
        r.floor += 1
        r.roomsOnFloor = 0
        r.floorRoomsNeeded = RunModifiers.rooms(Rooms.roomsNeeded(floor: r.floor, difficulty: r.difficulty, bossFloor: Challenges.bossFloor(r), dice: &d), r)
        r.upcomingRooms = []
        r.gearSavedThisFloor = false
        r.guardianDone = false
        // advanceFloor heals 35% of max HP on the way down.
        r.hp = min(r.maxHp, r.hp + jsRound(Double(r.maxHp) * 0.35))
        // Endless milestones (advanceFloor): every 25 floors a full heal and +5
        // max HP, every 10 a 30% heal.
        var milestone = ""
        if r.difficulty == .endless && r.floor > 1 {
            if r.floor % 25 == 0 {
                r.hp = r.maxHp
                r.maxHp += 5
                setEvent("⬇ Floor \(r.floor) — Endless Milestone! Full heal granted. Max HP increased by 5. The darkness deepens.", tone: "good")
                milestone = " Endless milestone! Floor \(r.floor). Full heal. Max HP increased. Keep going."
                HighScore.add("dungeon_clears", 500, store: game.store)
            } else if r.floor % 10 == 0 {
                r.hp = min(r.maxHp, r.hp + jsRound(Double(r.maxHp) * 0.30))
                setEvent("⬇ Floor \(r.floor) — Milestone! You feel stronger in the dark.", tone: "good")
                milestone = " Floor \(r.floor) milestone. Bonus heal."
                HighScore.add("dungeon_clears", 200, store: game.store)
            }
        }
        if let line = Subclasses.onFloor(&r, dice: &d) { add(line) }
        ClassTraits.onFloor(&r).forEach { add($0) }
        if let line = Blacksmith.onFloor(&r) { add(line) }
        var hunterFloor = ""
        if let line = WhisperingForest.onFloor(&r) {
            add(line)
            hunterFloor += " " + line
        }
        if let line = Hunter.newFloor(&r) {
            add(line)
            hunterFloor = " " + line
            hunterSounds(r.hunter?.dist ?? 10)
        }
        r.worldCurse = VoidReaperLive.shared.cursed
        if r.voidCurse {
            r.voidCurse = false
            add("⚗️ The Void Curse lifts on the new floor.")
        }
        r.event = Events.active()
        if r.xpBoostFloors > 0 {
            r.xpBoostFloors -= 1
            if r.xpBoostFloors == 0 { add("Your XP boost has worn off.") }
        }
        // Warm Blood (Coin Shop): 1 HP on each new floor.
        if r.has("cu-warm-blood") && r.hp > 0 { r.hp = min(r.maxHp, r.hp + 1) }
        r.hpAtFloorStart = r.hp
        r.floorStats = FloorStats(goldStart: r.gold)
        Encounters.planFloor(&r, dice: &d)
        r.roomGraph = threeD ? RoomGraph(roomsNeeded: r.floorRoomsNeeded, dice: &d) : nil
        if threeD { SpatialAudio.shared.descent() }
        let floor = r.floor
        game.updateCharacter(characterIndex) { $0.floor = max($0.floor, floor) }
        shop = Inventory.shopStock(for: r, dice: &d)
        roomTitle = Rooms.floorName(floor, dungeon: r.dungeon)
        add("You descend to floor \(floor): \(roomTitle).")
        achievements.record(.floorReached(floor))
        achievements.setGlobalMax("bestFloor", Double(floor))
        journal("Descended to floor \(r.floor). Kills so far: \(r.kills). HP: \(r.hp)/\(r.maxHp).", in: &r)
        let questLine = milestone + questDone(&r, game.dailyQuests.reachedFloor(floor, usedPotion: r.usedPotion))
            + bounty(.floor(floor, dungeon: r.dungeon, diedThisRun: r.diedThisRun)) + hunterFloor
        Sound.sfx("sfx-stairs")
        Sound.track(Soundtrack.exploreTrack(dungeon: r.dungeon, floor: floor))
        // Daily Dungeon's Stripped: no merchant on the stairs.
        if Challenges.has(r, "no-shop") {
            shop = []
            run = r
            dice = d
            phase = .exploring
            if threeD, let g = r.roomGraph {
                persist()
                Feedback.announce("Floor \(floor) of \(Challenges.bossFloor(r)). No merchant today. \(roomTitle). \(g.exitsText)" + questLine, after: 0.6)
                SpatialAudio.shared.exitCues(g.here)
                return
            }
            movePrefix = "Floor \(floor) of \(Challenges.bossFloor(r)). No merchant today. " + questLine + " "
            enterRoom()
            return
        }
        finish(r, d, phase: .shopping,
               spoken: "Floor \(floor) of \(Challenges.bossFloor(r)). You reach the stairs. A merchant waits in the passage. Shop open. The Wandering Merchant. You have \(r.gold) gold. \(shop.count) items available." + questLine)
    }

    func wander() {
        guard phase == .floorCleared, canWander else { return }
        var r = run
        var d = dice
        r.floorRoomsNeeded += 3
        r.floorStats = FloorStats(goldStart: r.gold)
        if threeD {
            if r.roomGraph == nil { r.roomGraph = RoomGraph(roomsNeeded: 3, dice: &d) } else { r.roomGraph?.extend(3, dice: &d) }
            dice = d
        }
        add("🗺 You wander further. The floor opens up with more rooms to explore.")
        finish(r, dice, phase: .exploring, spoken: "Wandering floor \(r.floor). 3 more rooms added. Explore carefully.")
    }

    func price(_ entry: Inventory.ShopItem) -> Int {
        Races.shopPrice(Spirits.shopPrice(RunModifiers.potionCost(entry.item, Inventory.price(entry.item, hour: hour), run), run), run)
    }

    func buy(_ id: Int) {
        guard phase == .shopping, let i = shop.firstIndex(where: { $0.id == id }) else { return }
        var r = run
        var entry = shop[i]
        let out = Inventory.buy(&r, &entry, wallet: game.wallet, hour: hour)
        shop[i] = entry
        run = r
        add(out.message)
        if out.used {
            Feedback.success()
            Sound.sfx("sfx-purchase")
            // The Market Sprite's discount is spent once it's used.
            if r.spirit == "market-sprite" { game.updateCharacter(characterIndex) { $0.extra["marketSpriteUsed"] = .bool(true) } }
        }
        persist()
        Feedback.announce(out.message)
    }

    func refreshShop() {
        guard phase == .shopping else { return }
        guard run.gold >= Inventory.refreshCost, game.wallet.spendGold(Inventory.refreshCost) else {
            Feedback.announce("Not enough gold. Refresh costs \(Inventory.refreshCost) gold.")
            return
        }
        var r = run
        var d = dice
        r.gold -= Inventory.refreshCost
        shop = Inventory.shopStock(for: r, dice: &d)
        run = r
        dice = d
        persist()
        Feedback.announce("Shop refreshed. New items available. You have \(r.gold) gold remaining.")
    }

    /// closeShop: "Continue Descent" leaves the merchant and walks on.
    func leaveShop() {
        guard phase == .shopping else { return }
        let left = max(0, run.floorRoomsNeeded - run.roomsOnFloor)
        if left == 0 && run.roomsOnFloor > 0 {
            phase = .floorCleared
            persist()
            Feedback.announce("You leave the merchant. " + floorCompleteLine(run))
            return
        }
        phase = .exploring
        // 3D Mode: you're standing in the floor's first room; walk on yourself.
        if threeD, let g = run.roomGraph {
            persist()
            Feedback.announce("You leave the merchant. \(roomTitle). \(g.exitsText)")
            SpatialAudio.shared.exitCues(g.here)
            return
        }
        movePrefix = "You leave the merchant. Continuing your descent. "
        enterRoom()
    }

    /// The character this run belongs to, by creation time.
    var characterID: Double {
        game.characters.indices.contains(characterIndex) ? game.characters[characterIndex].created : 0
    }

    /// Selling to the Wandering Merchant (renderShopSell).
    func sell(at index: Int) {
        guard phase == .shopping, run.inventory.indices.contains(index) else { return }
        var r = run
        let name = r.inventory[index].name
        guard let price = Inventory.sell(&r, at: index, wallet: game.wallet, store: game.store) else { return }
        run = r
        achievements.check()
        persist()
        Sound.sfx("sfx-purchase")
        Feedback.success()
        Feedback.announce("Sold \(name) for \(price) gold. You now have \(r.gold) gold.")
    }

    func drop(at index: Int) {
        guard run.inventory.indices.contains(index) else { return }
        var r = run
        r.inventory.remove(at: index)
        run = r
        persist()
        Feedback.announce("Item dropped.")
    }

    /// autoSortInventory: favorites first, then by type.
    func sortInventory(favorites: [String]) {
        let order = ["weapon": 1, "armor": 2, "potion": 3, "soul-trap": 4, "enchanter": 5, "rune": 6, "scroll": 7,
                     "skill-orb": 8, "sp-potion": 9, "material": 10, "music-player": 11]
        var r = run
        let indexed = r.inventory.enumerated().map { ($0.offset, $0.element) }
        r.inventory = indexed.sorted { a, b in
            let fa = favorites.contains(a.1.name) ? 0 : 1, fb = favorites.contains(b.1.name) ? 0 : 1
            if fa != fb { return fa < fb }
            let oa = order[a.1.type] ?? 99, ob = order[b.1.type] ?? 99
            return oa != ob ? oa < ob : a.0 < b.0
        }.map { $0.1 }
        run = r
        persist()
    }

    // MARK: Level points

    func spend(_ stat: Progression.Stat) {
        var r = run
        guard Progression.spend(&r, on: stat) else { return }
        run = r
        persist()
        add("\(stat.label) increased. \(r.levelPoints) level points left.", speak: true)
    }

    // MARK: Helpers

    private func finish(_ r: Run, _ d: SystemDice, phase newPhase: Phase, spoken: String) {
        // When the screen changes (a fight starts, a floor ends …) the button
        // you pressed disappears and VoiceOver moves to a new one, which cut
        // this announcement off after its first words. Wait for that move.
        let screenChanges = newPhase != phase
        // Dropping to a quarter of your health: the guide speaks up.
        let lowHp = r.hp > 0 && r.hp * 4 <= r.maxHp && run.hp * 4 > run.maxHp ? guideSays(.lowHp, r) : ""
        run = r
        dice = d
        phase = newPhase
        persist()
        setEvent(spoken, tone: newPhase == .fighting ? "danger" : newPhase == .floorCleared || newPhase == .shopping ? "good" : "")
        var whisper = ""
        if !movePrefix.isEmpty && newPhase == .exploring {
            var wd = SystemDice()
            if let w = Corruption.whisper(r, dice: &wd) {
                add("👁 " + w)
                whisper = " " + w
            }
        }
        Feedback.announce(movePrefix + spoken + whisper + lowHp + takeHunterLine(), after: screenChanges ? 0.6 : 0)
        movePrefix = ""
        if newPhase == .exploring || newPhase == .floorCleared { hunterAfterRoom() }
    }

    func setEvent(_ text: String, tone: String = "") {
        eventText = text
        eventTone = tone
    }

    /// Floor and run numbers for the Floor Complete panel and the summary.
    private func track(_ r: inout Run, _ result: TurnResult) {
        if result.playerDamage > 0 {
            r.floorStats.damageDealt += result.playerDamage
            r.floorStats.bestHit = max(r.floorStats.bestHit, result.playerDamage)
            r.bestHit = max(r.bestHit, result.playerDamage)
            achievements.trackGlobal("totalDmgDealt", Double(result.playerDamage))
        }
        if let taken = result.enemyDamage, taken > 0 { r.floorStats.damageTaken += taken }
    }

    // MARK: Level up and skills (triggerLevelUp, closeLevelUp, showSkillChoice)

    func continueAfterLevelUp() {
        levelUp = nil
        let c = run.skillChoices
        if c.isEmpty {
            Feedback.announce("Continuing your descent. No more skills available.")
        } else {
            let names = c.compactMap { Skills.skill($0, cls: run.cls)?.name }
            Feedback.announce("New skill available! Level \(run.level). Choose one of \(c.count) skills. " + names.joined(separator: ", ") + ".")
        }
    }

    // MARK: Run end

    /// What killed the hero, for the death cinematic.
    @Published private(set) var killer = ""

    var deathCinematicLine: String { UIText.shared.deathLine(killer: killer, floor: run.floor, dungeon: run.dungeon) }

    var deathCinematicSpoken: String {
        "\(deathCinematicLine) \(run.name) — \(run.race) \(run.cls). Slain by \(killer) on floor \(run.floor). Tap to continue."
    }

    /// Seconds since the run began, for the summary.
    var elapsed: Int { max(0, Int(Date().timeIntervalSince1970 - run.startedAt)) }

    /// Leaves the dungeon with the run saved (confirmFlee and the pause menu).
    func fleeDungeon() {
        persist()
        game.saveNow()
        Sound.ambient(nil)
        Sound.track("menu")
    }

    /// manualSave: not during a fight.
    func manualSave() {
        if phase == .fighting {
            Feedback.announce("Cannot save during combat.")
            setEvent("The dungeon will not pause for paperwork. Finish the fight first.")
            return
        }
        persist()
        game.saveNow()
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let time = "\(c.hour ?? 0):" + String(format: "%02d", c.minute ?? 0)
        setEvent("Progress saved at floor \(run.floor). \(time). The dungeon acknowledges your caution.", tone: "good")
        Sound.sfx("sfx-confirm")
        Feedback.announce("Progress saved. Floor \(run.floor).")
    }

    /// addJournalEntry: the line goes in the run's journal and the character's.
    private func journal(_ text: String, in r: inout Run) {
        let c = Calendar.current.dateComponents([.month, .day], from: Date())
        r.journalLog.append(JournalEntry(time: "\(c.month ?? 1)/\(c.day ?? 1) Floor \(r.floor)", text: text))
        let entries: [JSONValue] = r.journalLog.map { .object(["time": .string($0.time), "text": .string($0.text)]) }
        game.updateCharacter(characterIndex) { $0.extra["journal"] = .array(entries) }
    }

    private func journal(_ text: String) {
        var r = run
        journal(text, in: &r)
        run = r
    }

    private func persist() {
        guard phase != .victory && phase != .defeat, !characterGone else { return }
        game.saveRun(run, for: characterIndex)
    }

    private func add(_ text: String, speak: Bool = false) {
        log.insert(LogLine(text: text), at: 0)
        if log.count > 200 { log.removeLast() }
        if speak { Feedback.announce(text) }
    }
}
