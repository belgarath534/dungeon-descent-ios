import Foundation

/// The Shadow Realm (SR, getShadowEnemies, startShadowRealm, shadowAttack,
/// shadowEnemyAttack, shadowDie): the secret mode behind the code SHADOW in
/// Redeem Code. Endless waves, one shadow at a time, stronger every 5 waves
/// and a Shadow Sovereign every 10. Three potions, a little HP back after each
/// wave, and the ten best runs kept in "dd_shadow_leaderboard".
public enum ShadowRealm {
    public static let code = "SHADOW"

    public struct State: Sendable {
        public var name: String
        public var cls: String
        public var wave = 1
        public var kills = 0
        public var hp: Int
        public var maxHp: Int
        public var atk: Int
        public var def: Int
        public var potions = 3
        public var defending = false
        public var enemy: Enemy?
    }

    /// startShadowRealm: class HP plus 15 a level, 10 attack plus 2 a level,
    /// and your saved weapon and armor.
    public static func start(_ ch: PlayerCharacter, weapon: Item?, armor: Item?) -> State {
        let lvl = max(1, ch.persistLevel ?? 1)
        let maxHp = GameData.classInfo(ch.cls).maxHp + (lvl - 1) * 15
        var atk = 10 + (lvl - 1) * 2
        if let w = weapon { atk += (w.weaponAttack.lowerBound + w.weaponAttack.upperBound) / 2 }
        return State(name: ch.name, cls: ch.cls.isEmpty ? "Adventurer" : ch.cls, hp: maxHp, maxHp: maxHp,
                     atk: atk, def: armor?.armorDefense ?? 0)
    }

    /// getShadowEnemies: the next wave's shadow.
    public static func spawn(_ s: inout State, dice: inout some Dice) -> String {
        let w = s.wave
        var e: Enemy
        if w % 10 == 0 {
            let hp = 200 + w * 8
            e = Enemy(name: "Shadow Sovereign", icon: "👑", hp: hp, maxHp: hp, atk: (12 + w)...(20 + w), gold: 0...0)
            e.isBoss = true
            e.desc = "The ruler of this place. It knows you are here."
        } else {
            let t = (w - 1) / 5
            let base: [(String, String, Int, ClosedRange<Int>, String)] = [
                ("Shadow Wisp", "🌑", 30 + t * 12, (4 + t * 2)...(8 + t * 3), "A flicker of dark energy."),
                ("Void Stalker", "👤", 45 + t * 15, (5 + t * 2)...(10 + t * 3), "It moves without sound."),
                ("Shade Wraith", "👻", 60 + t * 18, (6 + t * 3)...(12 + t * 4), "Passes through walls. Not through you."),
                ("Dark Sentinel", "🗿", 80 + t * 20, (7 + t * 3)...(14 + t * 4), "Ancient. Patient. Violent."),
                ("Nightmare Hound", "🐺", 55 + t * 16, (8 + t * 3)...(15 + t * 4), "Runs on shadow and hunger."),
                ("Corruption Core", "💜", 100 + t * 25, (9 + t * 4)...(17 + t * 5), "A collapsed star of pure shadow."),
            ]
            let b = base[dice.roll(0...(base.count - 1))]
            e = Enemy(name: b.0, icon: b.1, hp: b.2, maxHp: b.2, atk: b.3, gold: 0...0)
            e.desc = b.4
        }
        s.enemy = e
        s.defending = false
        return (e.isBoss ? "👑 BOSS — " : "") + "\(e.name) emerges from the shadow. Wave \(w)."
    }

    public enum Action: Sendable { case attack, heavy, defend }

    public struct Turn: Sendable {
        public var lines: [String] = []
        public var killed = false
        public var died = false
    }

    /// shadowAttack, then shadowEnemyAttack if it still stands.
    public static func act(_ s: inout State, _ action: Action, dice: inout some Dice) -> Turn {
        var t = Turn()
        guard var e = s.enemy, !e.isDead, s.hp > 0 else { return t }
        s.defending = false
        switch action {
        case .attack:
            let d = s.atk + dice.roll(0...5)
            e.hp = max(0, e.hp - d)
            t.lines.append("⚔ You hit \(e.name) for \(d) damage.")
        case .heavy:
            let d = jsRound(Double(s.atk + dice.roll(0...7)) * 1.6)
            if dice.chance(0.25) {
                t.lines.append("💨 Heavy strike misses — the shadow steps aside.")
            } else {
                e.hp = max(0, e.hp - d)
                t.lines.append("💥 Heavy strike! \(d) damage to \(e.name).")
            }
        case .defend:
            s.defending = true
            let d = (s.atk + dice.roll(0...3)) / 2
            e.hp = max(0, e.hp - d)
            t.lines.append("🛡 You brace yourself, striking back for \(d) damage.")
        }
        s.enemy = e
        if e.isDead {
            s.kills += 1
            let heal = max(5, s.maxHp / 20)
            s.hp = min(s.maxHp, s.hp + heal)
            t.killed = true
            t.lines.append("💀 \(e.name) is consumed by its own shadow. Wave \(s.wave) cleared!")
            t.lines.append("✨ The silence heals you slightly. +\(heal) HP.")
            return t
        }
        let raw = dice.roll(e.atk)
        let dmg = max(1, raw - s.def - (s.defending ? s.atk * 3 / 10 : 0))
        s.hp = max(0, s.hp - dmg)
        t.lines.append("\(e.icon) \(e.name) hits you for \(dmg) damage." + (s.defending ? " (Blocked some!)" : ""))
        t.died = s.hp <= 0
        return t
    }

    /// shadowUsePotion: 40% of your HP. It doesn't cost a turn, as in the web version.
    public static func drink(_ s: inout State) -> String? {
        guard s.potions > 0 else { return nil }
        s.potions -= 1
        let heal = s.maxHp * 40 / 100
        s.hp = min(s.maxHp, s.hp + heal)
        return "🧪 You drink a potion. +\(heal) HP. \(s.potions) remaining."
    }

    public struct Record: Codable, Equatable, Sendable {
        public var name: String
        public var cls: String
        public var wave: Int
        public var kills: Int
        public var date: String
    }

    public static func board(_ store: GameStore) -> [Record] {
        guard let s = store.getItem("dd_shadow_leaderboard"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([Record].self, from: d) else { return [] }
        return v
    }

    /// shadowDie: onto the board, best wave first, ten kept.
    @discardableResult
    public static func record(_ s: State, store: GameStore, now: Date = Date()) -> [Record] {
        let f = DateFormatter()
        f.dateStyle = .short
        var b = board(store) + [Record(name: s.name, cls: s.cls, wave: s.wave, kills: s.kills, date: f.string(from: now))]
        b.sort { $0.wave != $1.wave ? $0.wave > $1.wave : $0.kills > $1.kills }
        b = Array(b.prefix(10))
        if let d = try? JSONEncoder().encode(b), let str = String(data: d, encoding: .utf8) { store.setItem("dd_shadow_leaderboard", str) }
        return b
    }
}
