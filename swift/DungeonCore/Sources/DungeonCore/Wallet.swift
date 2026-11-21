import Foundation

/// The shared gold and diamond wallet used across every game mode.
/// Port of getGlobalGold / addGlobalGold / spendGlobalGold / getDiamonds etc.
public final class Wallet {
    private let store: GameStore
    /// Called with an achievement id ("ach-gold-hoarder") when one is earned.
    public var onAchievement: (String) -> Void
    /// Called whenever gold or diamonds change, so screens can refresh.
    public var onChange: () -> Void = {}

    public init(store: GameStore, onAchievement: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.onAchievement = onAchievement
    }

    // MARK: Gold

    public var gold: Int {
        max(0, jsParseInt(store.getItem(StoreKey.globalGold) ?? "0") ?? 0)
    }

    public func setGold(_ amount: Int) {
        store.setItem(StoreKey.globalGold, String(max(0, amount)))
        onChange()
    }

    public func addGold(_ amount: Int) {
        setGold(gold + amount)
        let total = (jsParseInt(store.getItem(StoreKey.totalGoldEver) ?? "0") ?? 0) + amount
        store.setItem(StoreKey.totalGoldEver, String(total))
        if gold >= 300 { onAchievement("ach-gold-hoarder") }
        if gold >= 1000 { onAchievement("ach-gold-rich") }
    }

    /// Returns false (and spends nothing) if there isn't enough gold.
    @discardableResult
    public func spendGold(_ amount: Int) -> Bool {
        guard gold >= amount else { return false }
        setGold(gold - amount)
        let spent = (jsParseInt(store.getItem(StoreKey.totalGoldSpent) ?? "0") ?? 0) + amount
        store.setItem(StoreKey.totalGoldSpent, String(spent))
        if spent >= 600 { onAchievement("ach-big-spender") }
        if spent >= 7000 { onAchievement("ach-whale") }
        return true
    }

    // MARK: Diamonds

    public var diamonds: Int {
        max(0, jsParseInt(store.getItem(StoreKey.diamonds) ?? "0") ?? 0)
    }

    public func setDiamonds(_ amount: Int) {
        store.setItem(StoreKey.diamonds, String(max(0, amount)))
        onChange()
    }

    public func addDiamonds(_ amount: Int) {
        guard amount > 0 else { return }
        setDiamonds(diamonds + amount)
    }

    @discardableResult
    public func spendDiamonds(_ amount: Int) -> Bool {
        guard diamonds >= amount else { return false }
        setDiamonds(diamonds - amount)
        return true
    }
}
