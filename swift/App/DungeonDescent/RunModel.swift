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
                : saved.roomsOnFloor >= saved.floorRoomsNeeded && saved.roomsOnFloor > 0 ? .floorCleared : .exploring
            roomTitle = Rooms.floorName(saved.floor, dungeon: saved.dungeon)
            add("Run resumed on floor \(saved.floor). HP \(saved.hp) of \(saved.maxHp).")
            playMusic()
            return
        }
        run = Self.newRun(game, characterIndex)
        begin()
    }

    /// A fresh run for the character: start bonuses, saved items and gear,
    /// starting skill and the first floor's plan (initDungeon).
    private static func newRun(_ game: GameModel, _ index: Int) -> Run {
        var r = Run(character: game.characters[index], gold: game.wallet.gold)
        // Saved items first: loading them replaces the bag, so everything
        // else that adds items (seasonal shop, Coin Shop) goes in after.
        game.globalInventory.load(into: &r)
        r.applyStartBonuses(wallet: game.wallet)
        r.applyMilestoneBuffs(game.milestoneEffects)
        r.event = Events.active()
        r.startNotes += Events.applyNextRun(&r, store: game.store)
        // Home: the active minion fights beside you, the bed is ready again,
        // and last night's dream buff applies once.
        r.minion = Home.activeMinion(game.store)
        r.skillLevels = Home.skillLevels(game.store)
        Home.resetSleep(store: game.store)
        if case .string(let dream)? = game.characters[index].extra["dream"] {
            if let note = Home.applyDream(dream, to: &r) { r.startNotes.append("💤 " + note) }
            game.updateCharacter(index) { $0.extra["dream"] = nil }
        }
        var cd = SystemDice()
        CoinShop.apply(CoinShop.owned(game.store), to: &r, dice: &cd, wallet: game.wallet)
        game.achievements.trackGlobal("runsStarted")
        var d = SystemDice()
        Skills.start(&r, dice: &d)
        if r.floor >= 10 && r.difficulty != .endless { r.floorRoomsNeeded = 1 }
        Encounters.planFloor(&r, dice: &d)
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
        add("✦ Daily quest: \(game.dailyQuests.summary)")
        persist()
        playMusic()
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
            Sound.startLoop("monster-growl.mp3", volume: s.growlVolume, pan: s.pan)
            return
        }
        if let e = r.enemy, r.inCombat {
            Sound.track(e.isBoss ? Soundtrack.bossTrack(dungeon: r.dungeon) : Soundtrack.battleTrack(dungeon: r.dungeon))
        } else {
            Sound.track(Soundtrack.exploreTrack(dungeon: r.dungeon, floor: r.floor))
        }
        Sound.ambient(Soundtrack.ambientKey(dungeon: r.dungeon, difficulty: r.difficulty))
    }

    var isBossFloor: Bool { run.floor >= 10 && run.difficulty != .endless }
    var bossRoomNext: Bool { isBossFloor && run.roomsOnFloor == run.floorRoomsNeeded - 1 }
    var canWander: Bool { run.floor < 9 }
    var hour: Int { Calendar.current.component(.hour, from: Date()) }

    // MARK: Exploring

    /// The compass buttons. Outside 3D Mode any direction leads to the next room.
    func move(_ dir: String) {
        guard phase == .exploring else { return }
        movePrefix = "Moving \(dir)... "
        enterRoom()
    }

    func enterRoom() {
        guard phase == .exploring, run.stalker == nil else { return }
        Sound.sfx("sfx-footstep")
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
        roomTitle = Rooms.floorName(r.floor, dungeon: r.dungeon)
        roomText = Rooms.description(for: r, dice: &d)
        let label = "Room \(r.roomsOnFloor) of \(r.floorRoomsNeeded)."
        // Verbose Room Descriptions (Accessibility settings) reads the room text.
        var spoken = AppSettings.verboseRooms ? "\(label) \(roomText)" : label

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
            Sound.sfx(Soundtrack.enemyCue(dungeon: r.dungeon, boss: false))
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
            Sound.sfx(Soundtrack.enemyCue(dungeon: r.dungeon, boss: true))
            Sound.track(Soundtrack.bossTrack(dungeon: r.dungeon))
            spoken += " \(boss.name) rises before you. \(boss.hp) HP." + thirdEye(r)
            finish(r, d, phase: .fighting, spoken: spoken)
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
                Sound.sfx(Soundtrack.enemyCue(dungeon: r.dungeon, boss: false))
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
            // 20% of fights from floor 3 are ambushes; every fight is on Ambush Day.
            if r.floor >= 3 && (r.event == "ambushday" || d.chance(0.20)),
               let line = startAmbush(&r, &d, label: label) {
                spoken += " " + line
                finish(r, d, phase: .fighting, spoken: spoken)
                return
            }
            let enemy = Combat.nextEnemy(for: r, dice: &d)
            Combat.begin(&r, against: enemy).forEach { add($0) }
            let ability = Self.sentence(enemy.desc ?? "A powerful foe.")
            let line = enemy.isElite
                ? "\(label) ★ ELITE: \(enemy.icon) \(enemy.name) — \(ability) \(enemy.hp) HP."
                : "\(label) \(enemy.icon) A \(enemy.name) attacks! \(enemy.hp) HP."
            add(line)
            Sound.sfx(Soundtrack.enemyCue(dungeon: r.dungeon, boss: false))
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
        var r = run
        var d = dice
        let levelBefore = r.level
        if r.pendingEvent == "julio" && choice == 0 { achievements.record(.julioMet) }
        let out = Encounters.choose(choice, &r, dice: &d, wallet: game.wallet)
        add(out.message)
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
            Sound.sfx(Soundtrack.enemyCue(dungeon: r.dungeon, boss: false))
            Sound.track(Soundtrack.battleTrack(dungeon: r.dungeon))
            finish(r, d, phase: .fighting, spoken: out.message + " \(enemy.name), \(enemy.hp) HP." + thirdEye(r))
            return
        }
        if out.item != nil || out.gold > 0 { Sound.sfx("sfx-loot") }
        let q = questFound(&r, item: out.item, gold: out.gold)
        finishQuietRoom(r, d, spoken: out.message + q)
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
        let s = StalkerFloor(dice: &d)
        r.stalker = s
        add("🌑 Something stirs in the darkness. The Darkness Swallower is in this room with you.")
        Sound.stopMusic()
        Sound.ambient(nil)
        Sound.track("shadow-stalker")
        Sound.startLoop("monster-growl.mp3", volume: s.growlVolume, pan: s.pan)
        finish(r, d, phase: .exploring,
               spoken: "Something stirs in the darkness. The music shifts. Move carefully — the Darkness Swallower is somewhere in this room with you. It is \(s.distance) step\(s.distance != 1 ? "s" : "") away, to the \(s.direction). Reach the edge of the room \(StalkerFloor.escapesNeeded) times to escape. Use headphones: its growl tells you where it is.")
    }

    /// stalkerMove
    func stalkerMove(_ dir: String) {
        guard var s = run.stalker else { return }
        var r = run
        var d = dice
        let out = s.move(dir)
        r.stalker = s
        Sound.sfx("sfx-stairs")
        Sound.placed("monster-footstep.mp3", volume: s.stepVolume, pan: s.pan)
        Sound.moveLoop(volume: s.growlVolume, pan: s.pan)
        switch out {
        case .caught:
            Sound.stopLoop()
            Sound.placed("jump-scare-v3.mp3", volume: 1, pan: 0)
            Feedback.warning()
            let dmg = StalkerFloor.caught(&r)
            add("💀 THE DARKNESS SWALLOWER CATCHES YOU! \(dmg) shadow damage!")
            finish(r, d, phase: .exploring, spoken: "Caught! The Darkness Swallower strikes. \(dmg) damage. You barely survive.")
            playMusic()
        case .escaped:
            Sound.stopLoop()
            let item = StalkerFloor.escaped(&r, wallet: game.wallet, dice: &d)
            add("✨ You escaped the Darkness Swallower! Rare loot awarded.")
            if let item { add("📦 Found: \(item.name)!") }
            Sound.sfx("sfx-victory")
            Feedback.success()
            finish(r, d, phase: .exploring, spoken: "You escaped! The Darkness Swallower retreats into the shadows. 150 gold" + (item.map { " and \($0.name)" } ?? "") + " for your survival.")
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
        journal("Chose the \(sub.name) subclass.", in: &r)
        run = r
        persist()
        Sound.sfx("sfx-unlock")
        Feedback.announce("Subclass chosen. \(sub.name). \(sub.desc) Passive: \(sub.passive)")
    }

    func act(_ action: PlayerAction, bomb: Bool = false) {
        guard phase == .fighting else { return }
        var r = run
        var d = dice
        let options = Combat.Options(classTraits: AppSettings.classTraits)
        let result = bomb ? Combat.throwBomb(&r, dice: &d, options: options) : Combat.takeTurn(&r, action, dice: &d, options: options)
        guard result.acted else { return }
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
        }
        return said
    }

    /// The ambush: two or three enemies at once (startMultiCombat).
    private func startAmbush(_ r: inout Run, _ d: inout SystemDice, label: String) -> String? {
        let foes = Combat.ambushers(for: r, dice: &d)
        guard foes.count >= 2 else { return nil }
        let lines = Combat.beginAmbush(&r, foes)
        add(label)
        lines.forEach { add($0) }
        Sound.sfx(Soundtrack.enemyCue(dungeon: r.dungeon, boss: false))
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
        var r = run
        var d = dice
        let reward = Progression.rewardKill(&r, e, dice: &d, wallet: game.wallet)
        add(reward.message)
        var dropLine = ""
        if let drop = Inventory.equipmentDrop(&r, dice: &d) {
            add("🎁 Found: \(drop.icon) \(drop.name) Level \(drop.level ?? 1)! Check inventory.")
            dropLine = " Item found. \(drop.name) Level \(drop.level ?? 1). Open inventory to equip it."
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
        if e.mechanics["guardian"] == .bool(true) {
            r.guardianDone = true
            said += " The Elite Guardian falls. The final chamber is open."
            finish(r, d, phase: .exploring, spoken: said)
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
            finish(r, d, phase: .exploring, spoken: said)
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
        case .runOver where r.hardcore:
            run = r
            phase = .defeat
            game.deleteCharacter(at: characterIndex)
            characterGone = true
            let msg = "💀 HARDCORE — \(r.name) has fallen. This character is gone forever. There are no second chances in Hardcore Mode."
            add(msg)
            Feedback.announce(spoken + " " + msg)
        case .runOver:
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
            showingDeathCinematic = true
            Feedback.announce(spoken + " " + deathCinematicSpoken)
        }
    }

    private func victory(_ spoken: String) {
        phase = .victory
        achievements.record(.runWon(run, diedThisRun: run.diedThisRun,
                                    seconds: Date().timeIntervalSince1970 - run.startedAt))
        Sound.sfx("sfx-victory")
        Sound.ambient(nil)
        add("Victory! You have conquered \(run.dungeon).")
        var d = dice
        if let sp = Spirits.victoryReward(run, earned: earnedSpirits, dice: &d) {
            earnSpirit(sp.id)
            add("✦ Rare Spirit Unlocked: \(sp.icon) \(sp.name)! Saved forever.")
            Feedback.announce("Rare Spirit unlocked: \(sp.name)! Saved to your character forever. Requires level 5 to use.")
        }
        dice = d
        game.globalInventory.keep(from: run)
        game.checkLegends(run)
        game.recordFirstClear(run)
        game.updateCharacter(characterIndex) { $0.completed = true; $0.floor = 10 }
        game.clearRun(for: characterIndex)
        let next = game.unlockedDungeons().last ?? ""
        let unlock = next != run.dungeon && !next.isEmpty ? " \(next) is unlocked." : ""
        Feedback.announce(spoken + " Victory! You have conquered \(run.dungeon).\(unlock)"
            + (canContinueJourney ? " Continue your journey, start New Game Plus, or return." : " Start New Game Plus, or return."))
    }

    // MARK: Skills

    var skills: [Skill] { Skills.unlocked(run) }
    func skillCost(_ s: Skill) -> Int { Skills.cost(s, run) }

    func useSkill(_ effect: String) {
        guard phase == .fighting else { return }
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
        if out.used, let item {
            Sound.sfx(item.isWeapon || item.isArmor ? "sfx-confirm"
                      : ["potion", "elixir", "heal", "sp-potion", "atk-potion", "def-potion", "luck-potion", "swift-potion"].contains(item.type) ? "sfx-potion"
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
        r.floorRoomsNeeded = Rooms.roomsNeeded(floor: r.floor, difficulty: r.difficulty, dice: &d)
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
        if let line = Blacksmith.onFloor(&r) { add(line) }
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
        let floor = r.floor
        game.updateCharacter(characterIndex) { $0.floor = max($0.floor, floor) }
        shop = Inventory.shopStock(for: r, dice: &d)
        roomTitle = Rooms.floorName(floor, dungeon: r.dungeon)
        add("You descend to floor \(floor): \(roomTitle).")
        achievements.record(.floorReached(floor))
        achievements.setGlobalMax("bestFloor", Double(floor))
        journal("Descended to floor \(r.floor). Kills so far: \(r.kills). HP: \(r.hp)/\(r.maxHp).", in: &r)
        let questLine = milestone + questDone(&r, game.dailyQuests.reachedFloor(floor, usedPotion: r.usedPotion))
        Sound.sfx("sfx-stairs")
        Sound.track(Soundtrack.exploreTrack(dungeon: r.dungeon, floor: floor))
        finish(r, d, phase: .shopping,
               spoken: "Floor \(floor) of 10. You reach the stairs. A merchant waits in the passage. Shop open. The Wandering Merchant. You have \(r.gold) gold. \(shop.count) items available." + questLine)
    }

    func wander() {
        guard phase == .floorCleared, canWander else { return }
        var r = run
        r.floorRoomsNeeded += 3
        r.floorStats = FloorStats(goldStart: r.gold)
        add("🗺 You wander further. The floor opens up with more rooms to explore.")
        finish(r, dice, phase: .exploring, spoken: "Wandering floor \(r.floor). 3 more rooms added. Explore carefully.")
    }

    func price(_ entry: Inventory.ShopItem) -> Int { Spirits.shopPrice(Inventory.price(entry.item, hour: hour), run) }

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
        run = r
        dice = d
        phase = newPhase
        persist()
        setEvent(spoken, tone: newPhase == .fighting ? "danger" : newPhase == .floorCleared || newPhase == .shopping ? "good" : "")
        Feedback.announce(movePrefix + spoken)
        movePrefix = ""
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
