import Foundation

/// Settings → Developer Tools (openDevToolsPrompt, checkDevPassword, the
/// dev* functions): password protected, the password in "dd_dev_pw"
/// ("67" until it's changed), and three wrong tries hide the category until
/// the app is opened again.
public enum DevTools {
    public static func password(_ store: GameStore) -> String { store.getItem("dd_dev_pw") ?? "67" }

    /// confirmChangeDevPassword. Returns the problem, or nil when saved.
    public static func changePassword(_ new: String, confirm: String, store: GameStore) -> String? {
        if new.isEmpty { return "Please enter a new password." }
        if new.count < 2 { return "Password must be at least 2 characters." }
        if new != confirm { return "Passwords do not match." }
        store.setItem("dd_dev_pw", new)
        return nil
    }

    /// devUnlockAll: every dungeon, including the ones unlocked by
    /// trophies and clears (dd_dev_mode opens those). The web version
    /// forgot The Whispering Forest.
    public static func unlockAll(_ store: GameStore) {
        let u: [String: JSONValue] = ["The Ashbound Wastes": .bool(true), "Frosthold Abyss": .bool(true),
                                      "The Sunken Archives": .bool(true), "The Hollow": .bool(true),
                                      "The Whispering Forest": .bool(true)]
        if let d = try? JSONEncoder().encode(u), let s = String(data: d, encoding: .utf8) { store.setItem(StoreKey.unlocks, s) }
        store.setItem("dd_infernal_unlocked", "1")
        store.setItem("dd_dev_mode", "1")
    }

    /// devResetUnlocks: back to the Crypt only. (The web version left
    /// dd_dev_mode on, so the dungeons it opens stayed open; Swift clears it.)
    public static func resetUnlocks(_ store: GameStore) {
        store.setItem(StoreKey.unlocks, "{}")
        store.removeItem("dd_dev_mode")
    }

    /// Every gun, and 99 of every gun part.
    public static func unlockAllGuns(_ store: GameStore) { Guns.all.forEach { Guns.addOwned($0.id, store) } }

    public static func giveAllGunParts(_ store: GameStore) {
        var p = Guns.partCounts(store)
        for part in Guns.parts { p[part.id, default: 0] += 99 }
        Guns.savePartCounts(p, store)
    }

    /// devGenerateCode: a VOID-XXXX-XXXX code that redeems for the chosen prize.
    public static func rewardCode(for prize: VoidMode.Prize, dice: inout some Dice) -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        func part() -> String { String((0..<4).map { _ in chars[dice.roll(0...(chars.count - 1))] }) }
        var code = ""
        for _ in 0..<1000 {
            code = "VOID-\(part())-\(part())"
            if VoidMode.prize(for: code) == prize { return code }
        }
        return code
    }
}
