import Foundation

/// 12.2: losing a normal dungeon run costs half the gold you carry. Gold in
/// your Home safe is never touched, which is what the safe is for. Challenges
/// (the Gauntlet, the Daily Dungeon, the Weekly Ladder, community dungeons)
/// and co-op don't count.
public enum DeathPenalty {
    public static let share = 0.5

    /// Takes half the carried gold; returns how much was lost.
    @discardableResult
    public static func apply(_ run: inout Run, wallet: Wallet) -> Int {
        let lost = Int(Double(wallet.gold) * share)
        guard lost > 0, wallet.spendGold(lost) else { return 0 }
        run.gold = max(0, run.gold - lost)
        return lost
    }

    public static func line(_ lost: Int, safe: Int) -> String {
        "💰 You drop half the gold you carried: \(lost) gold is lost in the dungeon."
            + (safe > 0 ? " The \(safe) gold in your Home safe is safe." : " Gold kept in your Home safe is never lost.")
    }
}
