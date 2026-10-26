import Foundation

/// The seasonal Tournament: for the first 7 days of January, April, July
/// and October, one boss to hurt as much as possible. The score is the
/// damage dealt, plus speed and survival bonuses for a kill.
public struct Tournament: Sendable {
    public struct Boss: Sendable {
        public let id, name, icon: String
        public let hp: Int
        public let atk: ClosedRange<Int>
        public let desc, phaseMsg2, phaseMsg3: String
    }

    /// TOURNAMENT_BOSSES
    public static let bosses: [Boss] = [
        Boss(id: "tournament-colossus", name: "The Eternal Colossus", icon: "🏛️", hp: 500, atk: 20...35,
             desc: "An ancient construct from before the dungeons had names. It has been waiting.",
             phaseMsg2: "The Colossus awakens fully. The ground shakes.",
             phaseMsg3: "FINAL FORM — The Colossus burns with the light of a thousand defeated champions."),
        Boss(id: "tournament-void-sovereign", name: "The Void Sovereign", icon: "⬛", hp: 480, atk: 22...38,
             desc: "Whatever rules the void between dungeons. It has a name but it will not say it.",
             phaseMsg2: "The Sovereign tears reality. Your skills cost double SP.",
             phaseMsg3: "FINAL FORM — The Void Sovereign becomes everything and nothing at once."),
        Boss(id: "tournament-ancient-king", name: "The Ancient King", icon: "👑", hp: 520, atk: 18...32,
             desc: "He ruled before Malachar. Before the Crypt. Before everything. He is very tired of waiting.",
             phaseMsg2: "The Ancient King remembers who he was. He hits harder.",
             phaseMsg3: "FINAL FORM — The Ancient King dies as he lived. Loudly."),
    ]

    public struct Season: Sendable {
        public let index: Int
        public let year: Int
        public let active: Bool
        public let boss: Boss
        public let name: String
        public let hoursLeft: Int
        public let daysUntil: Int
        /// "season_3_2026": the save and leaderboard key.
        public var key: String { "season_\(index)_\(year)" }
    }

    /// getTournamentSeason. The web version counted down to January 1 of the
    /// same year from October on, so it showed a negative number of days;
    /// here it's next year's.
    public static func season(_ now: Date = Date(), calendar: Calendar = .current) -> Season {
        let year = calendar.component(.year, from: now)
        let starts = [1, 4, 7, 10].map { calendar.date(from: DateComponents(year: year, month: $0, day: 1))! }
        let index = starts.lastIndex { now >= $0 } ?? 0
        let start = starts[index]
        let end = start.addingTimeInterval(7 * 86400)
        let active = now >= start && now < end
        let next = index < 3 ? starts[index + 1] : calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
        return Season(index: index, year: year, active: active, boss: bosses[index % bosses.count],
                      name: ["Winter", "Spring", "Summer", "Autumn"][index] + " \(year)",
                      hoursLeft: active ? max(0, Int((end.timeIntervalSince(now) / 3600).rounded(.up))) : 0,
                      daysUntil: active ? 0 : Int((next.timeIntervalSince(now) / 86400).rounded(.up)))
    }

    // MARK: The fight

    public let boss: Boss
    public var bossHp: Int
    public var hp: Int
    public let maxHp: Int
    public let atkBonus: Int
    public let defBonus: Int
    public var phase = 1
    public var damageDealt = 0
    public var turnsUsed = 0
    public var done = false
    public var won = false

    /// startTournament: the class's HP plus 30, attack 12–22 plus the character's bonus.
    public init(character ch: PlayerCharacter, boss: Boss) {
        self.boss = boss
        bossHp = boss.hp
        maxHp = GameData.classInfo(ch.cls).maxHp + 30
        hp = maxHp
        func num(_ k: String) -> Int { if case .number(let n)? = ch.extra[k] { return Int(n) }; return 0 }
        atkBonus = num("atkBonus")
        defBonus = num("defBonus")
    }

    public enum Action { case attack, heavy, defend }

    public struct Turn: Sendable {
        public var log: [(text: String, good: Bool)] = []
        public var spoken: [String] = []
    }

    /// tnAttack
    public mutating func act(_ action: Action, dice: inout some Dice) -> Turn {
        var t = Turn()
        guard !done else { return t }
        var base = dice.roll(12...22) + atkBonus
        var missed = false
        switch action {
        case .heavy:
            if dice.chance(0.30) {
                base = 0
                missed = true
                t.log.append(("Heavy strike misses!", false))
                t.spoken.append("Heavy strike missed.")
            } else {
                base = jsRound(Double(base) * 1.7)
            }
        case .defend: base = jsRound(Double(base) * 0.4)
        case .attack: break
        }
        bossHp = max(0, bossHp - base)
        damageDealt += base
        turnsUsed += 1
        if !missed {
            let msg = action == .heavy ? "Heavy strike — \(base) damage!" : action == .defend ? "Defend and counter — \(base) damage." : "Attack — \(base) damage!"
            t.log.append((msg, true))
            t.spoken.append("\(msg) Boss HP: \(bossHp). Total damage: \(damageDealt).")
        }
        if bossHp <= jsRound(Double(boss.hp) * 0.66) && phase == 1 {
            phase = 2
            t.log.append(("⚡ " + boss.phaseMsg2, false))
            t.spoken.append("Phase 2. " + boss.phaseMsg2)
        }
        if bossHp <= jsRound(Double(boss.hp) * 0.33) && phase == 2 {
            phase = 3
            t.log.append(("⚡ " + boss.phaseMsg3, false))
            t.spoken.append("Final phase. " + boss.phaseMsg3)
        }
        if bossHp <= 0 {
            done = true
            won = true
            return t
        }
        var bAtk = dice.roll(boss.atk)
        if phase == 2 { bAtk = jsRound(Double(bAtk) * 1.25) }
        if phase == 3 { bAtk = jsRound(Double(bAtk) * 1.5) }
        if action == .defend { bAtk = max(1, jsRound(Double(bAtk) * 0.4)) }
        let taken = max(1, bAtk - defBonus)
        hp = max(0, hp - taken)
        t.log.append(("\(boss.name) strikes for \(taken).", false))
        t.spoken.append("\(boss.name) attacks for \(taken). Your HP: \(hp).")
        if hp <= 0 { done = true }
        return t
    }

    /// tnVictory / tnDeath: a kill adds up to 500 for speed and 300 for HP left.
    public var speedBonus: Int { won ? max(0, 500 - turnsUsed * 10) : 0 }
    public var survivalBonus: Int { won ? jsRound(Double(hp) / Double(maxHp) * 300) : 0 }
    public var score: Int { damageDealt + speedBonus + survivalBonus }

    // MARK: Best scores ("dd_tournament")

    public static func best(_ season: Season, store: GameStore) -> Int {
        guard let s = store.getItem("dd_tournament"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d),
              case .number(let n)? = v[season.key] else { return 0 }
        return Int(n)
    }

    /// saveTournamentScore. True when it's a new best (and so worth uploading).
    @discardableResult
    public static func record(_ score: Int, season: Season, store: GameStore) -> Bool {
        var v: [String: JSONValue] = [:]
        if let s = store.getItem("dd_tournament"), let d = s.data(using: .utf8),
           let x = try? JSONDecoder().decode([String: JSONValue].self, from: d) { v = x }
        guard score > best(season, store: store) else { return false }
        v[season.key] = .number(Double(score))
        if let d = try? JSONEncoder().encode(v), let s = String(data: d, encoding: .utf8) { store.setItem("dd_tournament", s) }
        return true
    }
}
