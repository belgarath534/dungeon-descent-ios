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

    private let game: GameModel
    private let characterIndex: Int
    private var dice = SystemDice()

    init(game: GameModel, characterIndex: Int, resume: Bool) {
        self.game = game
        self.characterIndex = characterIndex
        if resume, let saved = game.savedRun(for: characterIndex) {
            run = saved
            phase = saved.inCombat ? .fighting
                : saved.roomsOnFloor >= saved.floorRoomsNeeded && saved.roomsOnFloor > 0 ? .floorCleared : .exploring
            roomTitle = Rooms.floorName(saved.floor, dungeon: saved.dungeon)
            add("Run resumed on floor \(saved.floor). HP \(saved.hp) of \(saved.maxHp).")
            return
        }
        var r = Run(character: game.characters[characterIndex], gold: game.wallet.gold)
        r.applyStartBonuses(wallet: game.wallet)
        game.globalInventory.load(into: &r)
        var d = SystemDice()
        Skills.start(&r, dice: &d)
        if r.floor >= 10 && r.difficulty != .endless { r.floorRoomsNeeded = 1 }
        run = r
        roomTitle = Rooms.floorName(r.floor, dungeon: r.dungeon)
        add("Descended into \(r.dungeon) on \(r.difficulty.rawValue) difficulty.")
        add("Floor \(r.floor): \(roomTitle). \(r.lives) \(r.lives == 1 ? "life" : "lives").")
        if let s = Skills.unlocked(r).first { add("✨ Starting skill: \(s.name). \(s.desc)") }
        persist()
    }

    var isBossFloor: Bool { run.floor >= 10 && run.difficulty != .endless }
    var bossRoomNext: Bool { isBossFloor && run.roomsOnFloor == run.floorRoomsNeeded - 1 }
    var canWander: Bool { run.floor < 9 }
    var hour: Int { Calendar.current.component(.hour, from: Date()) }

    // MARK: Exploring

    func enterRoom() {
        guard phase == .exploring else { return }
        var r = run
        var d = dice
        r.roomsOnFloor += 1
        r.totalRooms += 1
        r.searched = false
        r.sp = min(r.maxSp, r.sp + 2)
        roomTitle = Rooms.floorName(r.floor, dungeon: r.dungeon)
        roomText = Rooms.description(for: r, dice: &d)
        let label = "Room \(r.roomsOnFloor) of \(r.floorRoomsNeeded)."
        var spoken = "\(label) \(roomText)"

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

        if isBossFloor && r.roomsOnFloor >= r.floorRoomsNeeded {
            let boss = Combat.nextBoss(for: r, dice: &d)
            Combat.begin(&r, against: boss)
            add("\(boss.icon) \(boss.name) rises before you. \(boss.hp) HP.")
            spoken += " \(boss.name) rises before you. \(boss.hp) HP."
            finish(r, d, phase: .fighting, spoken: spoken)
            return
        }

        switch Rooms.next(&r, dice: &d) {
        case .fight:
            let enemy = Combat.nextEnemy(for: r, dice: &d)
            Combat.begin(&r, against: enemy)
            let line = "\(label) \(enemy.icon) A \(enemy.name) attacks! \(enemy.hp) HP."
            add(line)
            spoken += " A \(enemy.name) attacks! \(enemy.hp) HP."
            finish(r, d, phase: .fighting, spoken: spoken)
        case .loot:
            let find = Inventory.lootRoom(&r, dice: &d, wallet: game.wallet)
            add("\(label) \(find.message)")
            spoken += " " + find.message
            if find.item != nil || find.gold > 0 { Feedback.success() }
            finishQuietRoom(r, d, spoken: spoken)
        case .event:
            add("\(label) \(roomText)")
            finishQuietRoom(r, d, spoken: spoken)
        }
    }

    private func finishQuietRoom(_ r: Run, _ d: SystemDice, spoken: String) {
        if r.roomsOnFloor >= r.floorRoomsNeeded {
            finish(r, d, phase: .floorCleared, spoken: spoken + " Floor \(r.floor) complete. Descend or wander.")
            add("Floor \(r.floor) complete.")
        } else {
            finish(r, d, phase: .exploring, spoken: spoken)
        }
    }

    func search() {
        guard phase == .exploring || phase == .floorCleared else { return }
        var r = run
        var d = dice
        let find = Inventory.search(&r, dice: &d, wallet: game.wallet)
        add(find.message)
        if find.trap != nil && find.trap != "avoided" { Feedback.warning() }
        else if find.item != nil || find.gold > 0 { Feedback.success() }
        run = r
        dice = d
        if find.playerDied {
            playerDied(killedBy: find.trap ?? "a trap", spoken: find.message)
            return
        }
        persist()
        Feedback.announce(find.message)
    }

    // MARK: Fighting

    func act(_ action: PlayerAction) {
        guard phase == .fighting else { return }
        var r = run
        var d = dice
        let result = Combat.takeTurn(&r, action, dice: &d, options: .init(classTraits: AppSettings.classTraits))
        result.log.forEach { add($0) }
        if result.crit { Feedback.hit(heavy: true) } else if result.playerDamage > 0 { Feedback.hit() }

        var spoken = result.log.first ?? ""
        if result.bossPhaseMessage != nil {
            spoken = result.log.joined(separator: " ")
            Feedback.hit(heavy: true)
        }

        if result.fled {
            finish(r, d, phase: r.roomsOnFloor >= r.floorRoomsNeeded ? .floorCleared : .exploring,
                   spoken: result.announcement ?? "You fled.")
            return
        }
        if result.enemyDied, let e = r.enemy {
            run = r; dice = d
            enemyDefeated(e, spoken: spoken)
            return
        }
        if result.playerDied {
            run = r; dice = d
            playerDied(killedBy: r.enemy?.name ?? "the dungeon", spoken: spoken)
            return
        }
        if let a = result.announcement, result.bossPhaseMessage == nil { spoken += " " + a }
        finish(r, d, phase: .fighting, spoken: spoken)
    }

    private func enemyDefeated(_ e: Enemy, spoken: String) {
        var r = run
        var d = dice
        let reward = Progression.rewardKill(&r, e, dice: &d, wallet: game.wallet)
        add(reward.message)
        var said = spoken + " " + reward.message
        if reward.levelsGained > 0 {
            let msg = "Level up! You are now level \(r.level). You have \(r.levelPoints) level points to spend."
            add(msg)
            said += " " + msg
            if r.skillChoices.isEmpty {
                Skills.offer(&r, dice: &d)
                if !r.skillChoices.isEmpty {
                    let names = r.skillChoices.compactMap { Skills.skill($0, cls: r.cls)?.name }
                    said += " New skill available! Choose one of: " + names.joined(separator: ", ") + "."
                }
            }
        }
        Feedback.success()
        r.enemy = nil
        r.inCombat = false
        if e.isBoss {
            run = r
            dice = d
            victory(said)
        } else if r.roomsOnFloor >= r.floorRoomsNeeded {
            add("Floor \(r.floor) complete.")
            finish(r, d, phase: .floorCleared, spoken: said + " Floor \(r.floor) complete. Descend or wander.")
        } else {
            finish(r, d, phase: .exploring, spoken: said)
        }
    }

    private func playerDied(killedBy: String, spoken: String) {
        var r = run
        Feedback.warning()
        switch Progression.handleDeath(&r) {
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
        case .revived(let left):
            let msg = "You died. \(left) \(left == 1 ? "life" : "lives") remaining. Restored to 40 percent health."
            add(msg)
            finish(r, dice, phase: r.roomsOnFloor >= r.floorRoomsNeeded ? .floorCleared : .exploring,
                   spoken: spoken + " " + msg)
        case .runOver:
            run = r
            phase = .defeat
            add("Defeated. All lives lost. \(r.name) fell on floor \(r.floor).")
            let floor = r.floor
            game.updateCharacter(characterIndex) {
                $0.logDeath(floor: floor, killedBy: killedBy)
                $0.floor = 1
            }
            game.clearRun(for: characterIndex)
            Feedback.announce(spoken + " Defeated. All lives lost. \(r.name) fell on floor \(floor) to \(killedBy).")
        }
    }

    private func victory(_ spoken: String) {
        phase = .victory
        add("Victory! You have conquered \(run.dungeon).")
        game.globalInventory.keep(from: run)
        game.updateCharacter(characterIndex) { $0.completed = true; $0.floor = 10 }
        game.clearRun(for: characterIndex)
        let next = game.unlockedDungeons().last ?? ""
        let unlock = next != run.dungeon && !next.isEmpty ? " \(next) is unlocked." : ""
        Feedback.announce(spoken + " Victory! You have conquered \(run.dungeon).\(unlock)")
    }

    // MARK: Skills

    var skills: [Skill] { Skills.unlocked(run) }
    func skillCost(_ s: Skill) -> Int { Skills.cost(s, run) }

    func useSkill(_ effect: String) {
        guard phase == .fighting else { return }
        var r = run
        var d = dice
        let result = Skills.use(&r, effect, dice: &d, options: .init(classTraits: AppSettings.classTraits))
        guard result.acted else {
            Feedback.announce(result.announcement ?? "You can't use that now.")
            return
        }
        result.log.forEach { add($0) }
        if result.playerDamage > 0 { Feedback.hit(heavy: result.playerDamage >= 30) }
        var spoken = result.log.joined(separator: " ")
        if result.fled {
            finish(r, d, phase: r.roomsOnFloor >= r.floorRoomsNeeded ? .floorCleared : .exploring, spoken: spoken)
            return
        }
        if result.enemyDied, let e = r.enemy {
            run = r; dice = d
            enemyDefeated(e, spoken: spoken)
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
        run = r
        persist()
        add("✨ You unlocked \(s.name). \(s.desc)")
        Feedback.announce("You unlocked \(s.name). \(s.desc)")
    }

    // MARK: Items

    func useItem(at index: Int) {
        guard phase != .victory && phase != .defeat else { return }
        var r = run
        var d = dice
        let isReveal = r.inventory.indices.contains(index) && r.inventory[index].id == "scroll-reveal"
        let out = Inventory.use(&r, at: index)
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
        let floor = r.floor
        game.updateCharacter(characterIndex) { $0.floor = max($0.floor, floor) }
        shop = Inventory.shopStock(for: r, dice: &d)
        roomTitle = Rooms.floorName(floor, dungeon: r.dungeon)
        add("You descend to floor \(floor): \(roomTitle).")
        finish(r, d, phase: .shopping,
               spoken: "Floor \(floor) of 10. \(roomTitle). A merchant waits in the passage. Shop open. You have \(r.gold) gold.")
    }

    func wander() {
        guard phase == .floorCleared, canWander else { return }
        var r = run
        r.floorRoomsNeeded += 3
        add("🗺 You wander further. The floor opens up with more rooms to explore.")
        finish(r, dice, phase: .exploring, spoken: "Wandering floor \(r.floor). 3 more rooms added. Explore carefully.")
    }

    func price(_ entry: Inventory.ShopItem) -> Int { Inventory.price(entry.item, hour: hour) }

    func buy(_ id: Int) {
        guard phase == .shopping, let i = shop.firstIndex(where: { $0.id == id }) else { return }
        var r = run
        var entry = shop[i]
        let out = Inventory.buy(&r, &entry, wallet: game.wallet, hour: hour)
        shop[i] = entry
        run = r
        add(out.message)
        if out.used { Feedback.success() }
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

    func leaveShop() {
        guard phase == .shopping else { return }
        phase = .exploring
        persist()
        Feedback.announce("You leave the merchant behind. Floor \(run.floor), \(run.floorRoomsNeeded) rooms ahead.")
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
        Feedback.announce(spoken)
    }

    private func persist() {
        guard phase != .victory && phase != .defeat else { return }
        game.saveRun(run, for: characterIndex)
    }

    private func add(_ text: String, speak: Bool = false) {
        log.insert(LogLine(text: text), at: 0)
        if log.count > 200 { log.removeLast() }
        if speak { Feedback.announce(text) }
    }
}
