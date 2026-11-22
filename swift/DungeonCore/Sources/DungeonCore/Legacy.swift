import Foundation

/// Legacy Mode (runMode "legacy", dungeonTier, persistLevel): the level
/// carries between runs (up to 50 since 12.0.2; it was 25), and each dungeon you clear raises the
/// Dungeon Tier: +20% enemy HP, +10% enemy attack and +15% gold a tier. Dying
/// keeps the level and puts the tier back to 1. The web version saved the
/// level on a clear but every run started at level 1 anyway; Swift starts
/// you at it, with its level points to spend again.
public enum Legacy {
    /// The highest Legacy level, the same as Endless Descent's.
    public static let maxLevel = AFK.maxLevel
    public static func isLegacy(_ ch: PlayerCharacter) -> Bool { ch.runMode == "legacy" }

    public static func hpMult(tier: Int) -> Double { 1 + Double(max(0, tier - 1)) * 0.20 }
    public static func atkMult(tier: Int) -> Double { 1 + Double(max(0, tier - 1)) * 0.10 }
    public static func goldMult(tier: Int) -> Double { 1 + Double(max(0, tier - 1)) * 0.15 }

    /// initDungeon: the saved level, XP and skills, and the tier.
    public static func start(_ r: inout Run, _ ch: PlayerCharacter) -> [String] {
        guard isLegacy(ch) else { return [] }
        var notes: [String] = []
        let level = min(r.levelCap, max(1, ch.persistLevel ?? 1))
        if level > 1 {
            r.level = level
            if case .number(let x)? = ch.extra["persistXp"] { r.xp = max(0, Int(x)) }
            if case .array(let s)? = ch.extra["persistSkills"] {
                let ids = s.compactMap { v -> String? in if case .string(let id) = v { return id }; return nil }
                if !ids.isEmpty { r.unlockedSkills = ids }
            }
            r.levelPoints += 3 * (level - 1)
            notes.append("🌑 Legacy — you return at level \(level). \(3 * (level - 1)) level points to spend.")
        }
        let tier = max(1, ch.dungeonTier ?? 1)
        r.legacyTier = tier
        if tier > 1 {
            notes.append("🌑 Legacy — Dungeon Tier \(tier). Enemies are \(Int(((hpMult(tier: tier) - 1) * 100).rounded()))% stronger. Gold rewards \(Int(((goldMult(tier: tier) - 1) * 100).rounded()))% higher.")
        }
        return notes
    }

    /// 12.0.2: later dungeons are harder. From the third dungeon (Frosthold
    /// Abyss) enemies and bosses have +15% HP and attack, and 10% more for
    /// each dungeon after it (The Shadow World +75%). The web does the same.
    public static func depthMult(_ dungeon: String) -> Double {
        guard let i = GameData.dungeons.firstIndex(of: dungeon), i >= 2 else { return 1 }
        return 1.15 + Double(i - 2) * 0.10
    }

    /// applyTierScaling (with the dungeon's depth first, in every run mode).
    static func shape(_ e: inout Enemy, _ run: Run) {
        let d = depthMult(run.dungeon)
        if d != 1 {
            e.hp = jsRound(Double(e.hp) * d)
            e.maxHp = e.hp
            let lo = jsRound(Double(e.atk.lowerBound) * d), hi = jsRound(Double(e.atk.upperBound) * d)
            e.atk = lo...max(lo, hi)
            if e.isBoss { e.phase1Hp = jsRound(Double(e.hp) * 0.66); e.phase2Hp = jsRound(Double(e.hp) * 0.33) }
        }
        let t = run.legacyTier
        guard t > 1 else { return }
        e.hp = jsRound(Double(e.hp) * hpMult(tier: t))
        e.maxHp = e.hp
        let a = atkMult(tier: t)
        let lo = jsRound(Double(e.atk.lowerBound) * a), hi = jsRound(Double(e.atk.upperBound) * a)
        e.atk = lo...max(lo, hi)
        let g = goldMult(tier: t)
        let glo = jsRound(Double(e.gold.lowerBound) * g), ghi = jsRound(Double(e.gold.upperBound) * g)
        e.gold = glo...max(glo, ghi)
    }

    /// A Legacy character's level is kept the moment it's reached (the web
    /// version's levelUp → saveCharPersistentLevel), so dying or leaving the
    /// run doesn't take it away. It was only kept when the dungeon was
    /// cleared, so a Legacy character back from a death was level 1 again.
    /// False when there was nothing to keep.
    @discardableResult
    public static func keepLevel(_ ch: inout PlayerCharacter, run: Run) -> Bool {
        guard isLegacy(ch), run.level > (ch.persistLevel ?? 1) else { return false }
        ch.persistLevel = run.level
        ch.extra["persistXp"] = .number(Double(run.xp))
        ch.extra["persistSkills"] = .array(run.unlockedSkills.map { .string($0) })
        return true
    }

    /// The dungeon is cleared: saveCharPersistentLevel, and the tier goes up.
    /// Returns the news, if any.
    @discardableResult
    public static func cleared(_ ch: inout PlayerCharacter, run: Run) -> String? {
        ch.persistLevel = max(ch.persistLevel ?? 1, run.level)
        ch.extra["persistXp"] = .number(Double(run.xp))
        ch.extra["persistSkills"] = .array(run.unlockedSkills.map { .string($0) })
        guard isLegacy(ch) else { return nil }
        let tier = (ch.dungeonTier ?? 1) + 1
        ch.dungeonTier = tier
        return "Legacy Mode — Dungeon Tier \(tier) unlocked! Enemies will be stronger next run, but so will the rewards."
    }
}
