import SwiftUI
import DungeonCore

/// One dungeon run in progress. For now every room is a fight; room events,
/// search, loot and the shop come next (see swift/MIGRATION.md).
@MainActor
final class RunModel: ObservableObject {
    enum Phase: Equatable {
        case exploring
        case fighting
        case floorCleared
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

    private let game: GameModel
    private let characterIndex: Int
    private var dice = SystemDice()
    private var bossPhase = 1

    init(game: GameModel, characterIndex: Int) {
        self.game = game
        self.characterIndex = characterIndex
        var r = Run(character: game.characters[characterIndex], gold: game.wallet.gold)
        r.applyStartBonuses(wallet: game.wallet)
        run = r
        add("Descended into \(r.dungeon) on \(r.difficulty.rawValue) difficulty.")
        add("Floor \(r.floor). \(r.lives) \(r.lives == 1 ? "life" : "lives").")
    }

    var isBossFloor: Bool { run.floor >= 10 && run.difficulty != .endless }
    var bossRoomNext: Bool { isBossFloor && run.roomsOnFloor == run.floorRoomsNeeded - 1 }

    func enterRoom() {
        guard phase == .exploring else { return }
        var r = run
        var d = dice
        r.roomsOnFloor += 1
        r.totalRooms += 1
        let roomLabel = "Room \(r.roomsOnFloor) of \(r.floorRoomsNeeded)."
        let enemy: Enemy
        if isBossFloor && r.roomsOnFloor >= r.floorRoomsNeeded {
            enemy = Combat.nextBoss(for: r, dice: &d)
            bossPhase = 1
            add("\(enemy.icon) \(enemy.name) rises before you. \(enemy.hp) HP.", speak: true)
        } else {
            switch Rooms.roll(r.difficulty, dice: &d) {
            case .fight:
                enemy = Combat.nextEnemy(for: r, dice: &d)
                add("\(roomLabel) \(enemy.icon) A \(enemy.name) attacks! \(enemy.hp) HP.", speak: true)
            case .loot:
                add("\(roomLabel) Something glints in the dust, but loot isn't in the Swift version yet.", speak: true)
                finishQuietRoom(r, d)
                return
            case .event:
                add("\(roomLabel) The room is quiet. Room events come in a later Swift build.", speak: true)
                finishQuietRoom(r, d)
                return
            }
        }
        Combat.begin(&r, against: enemy)
        run = r
        dice = d
        phase = .fighting
    }

    private func finishQuietRoom(_ r: Run, _ d: SystemDice) {
        run = r
        dice = d
        if r.roomsOnFloor >= r.floorRoomsNeeded {
            phase = .floorCleared
            add("Floor \(r.floor) cleared.", speak: true)
        }
    }

    func act(_ action: PlayerAction) {
        guard phase == .fighting else { return }
        var r = run
        var d = dice
        let result = Combat.takeTurn(&r, action, dice: &d, options: .init(classTraits: AppSettings.classTraits))
        result.log.forEach { add($0) }
        if result.crit { Feedback.hit(heavy: true) } else if result.playerDamage > 0 { Feedback.hit() }

        var spoken = result.log.first ?? ""
        if let e = r.enemy, e.isBoss, !e.isDead {
            if bossPhase == 1 && e.hp <= e.phase1Hp, let m = e.phaseMsg2 {
                bossPhase = 2
                add(m)
                spoken += " " + m
            } else if bossPhase == 2 && e.hp <= e.phase2Hp, let m = e.phaseMsg3 {
                bossPhase = 3
                add(m)
                spoken += " " + m
            }
        }

        if result.enemyDied, let e = r.enemy {
            let reward = Progression.rewardKill(&r, e, dice: &d, wallet: game.wallet)
            add(reward.message)
            spoken += " " + reward.message
            if reward.levelsGained > 0 {
                let msg = "Level up! You are now level \(r.level). You have \(r.levelPoints) level points to spend."
                add(msg)
                spoken += " " + msg
            }
            Feedback.success()
            r.enemy = nil
            if e.isBoss {
                phase = .victory
                game.updateCharacter(characterIndex) { $0.completed = true; $0.floor = 10 }
                spoken += " Victory! You have conquered \(r.dungeon)."
            } else if r.roomsOnFloor >= r.floorRoomsNeeded {
                phase = .floorCleared
                spoken += " Floor \(r.floor) cleared."
            } else {
                phase = .exploring
            }
        } else if result.playerDied {
            Feedback.warning()
            switch Progression.handleDeath(&r) {
            case .revived(let left):
                let msg = "You died. \(left) \(left == 1 ? "life" : "lives") remaining. Restored to 40 percent health."
                add(msg)
                spoken += " " + msg
                r.enemy = nil
                phase = .exploring
            case .runOver:
                add("Defeated. All lives lost.")
                spoken += " Defeated. All lives lost."
                r.enemy = nil
                phase = .defeat
            }
        } else if let a = result.announcement {
            spoken += " " + a
        }

        run = r
        dice = d
        Feedback.announce(spoken)
    }

    func descend() {
        guard phase == .floorCleared else { return }
        run.floor += 1
        run.roomsOnFloor = 0
        let floor = run.floor
        game.updateCharacter(characterIndex) { $0.floor = max($0.floor, floor) }
        phase = .exploring
        add("You descend to floor \(floor).", speak: true)
    }

    func spend(_ stat: Progression.Stat) {
        var r = run
        guard Progression.spend(&r, on: stat) else { return }
        run = r
        add("\(stat.label) increased. \(r.levelPoints) level points left.", speak: true)
    }

    private func add(_ text: String, speak: Bool = false) {
        log.insert(LogLine(text: text), at: 0)
        if log.count > 200 { log.removeLast() }
        if speak { Feedback.announce(text) }
    }
}
