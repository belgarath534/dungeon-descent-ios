import Foundation

/// 12.1: the holiday enemies' own moves (enemyAttackTurn's seasonal branches
/// on the web): the Leprechaun, O Craque, The Heartbreaker, the Gold Goblin,
/// The Clurichaun, O Papagaio and The Cupid.
enum HolidayFoes {
    /// Before the attack. A move that replaces the hit sets skipAttack.
    static func beforeAttack(_ run: inout Run, _ m: inout EnemyAbilities.Move, dice: inout some Dice, log: inout [String]) {
        guard let e = run.enemy else { return }
        if e.flag("stealsGold") {
            let n = min(run.gold, 10)
            run.gold -= n
            run.fight.stolenGold += n
            log.append("🧝 The Leprechaun steals \(n) gold! Kill it fast!")
            m.skipAttack = true
            return
        }
        if e.flag("footballKick") {
            var dmg = (e.atk.lowerBound + e.atk.upperBound) / 2 + dice.roll(0...7)
            if run.defending { dmg /= 2 }
            run.hp = max(0, run.hp - dmg)
            log.append("⚽ O Craque kicks the ball! It hits you square in the face for \(dmg) damage!")
            m.skipAttack = true
            return
        }
        if e.flag("charmsPlayer"), !run.debuffImmune, dice.chance(0.35) {
            run.frozen = true
            log.append("💘 The Heartbreaker fires a charm arrow! You are charmed — you will skip your next turn.")
        }
        if e.name == "The Clurichaun" {
            m.multiplier *= 1 + Double(e.turnsTaken) * 0.1
            if e.turnsTaken > 1 { log.append("🍺 The Clurichaun rages! +\(e.turnsTaken * 10)% damage!") }
        }
        if e.flag("mirrorAtk") {
            m.minimum = run.atk.upperBound + run.atkBonus
            log.append("\(e.name) copies your own strength back at you!")
        }
    }

    /// The Gold Goblin: 30% each turn to run off with its gold.
    static func goldFlees(_ run: Run, dice: inout some Dice, log: inout [String]) -> Bool {
        guard let e = run.enemy, e.flag("goldFlee"), dice.chance(0.30) else { return false }
        log.append("💰 The Gold Goblin flees with its gold! It escaped.")
        return true
    }

    /// The Cupid always drops a Love Potion.
    static func onKill(_ run: inout Run, _ e: Enemy, log: inout [String]) {
        guard e.flag("dropsLovePotion"), let p = SeasonalItems.all["val-love-potion"] else { return }
        run.inventory.append(p)
        log.append("💘 The Cupid drops a Love Potion!")
    }
}
