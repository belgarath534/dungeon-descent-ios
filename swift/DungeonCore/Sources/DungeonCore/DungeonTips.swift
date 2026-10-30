import Foundation

/// In-dungeon first-run tips (DUNGEON_TIPS, showDungeonTip): each one shows
/// once, the first time you meet what it explains, and is remembered in
/// "dd_dungeon_tips_seen". The web version never showed the combat, boss
/// and elite tips; Swift does.
public enum DungeonTips {
    public static let all: [String: (text: String, seconds: Double)] = [
        "first-room": ("💡 Use North, South, East or West to move. Press Search to look for loot in this room. Each room can hold combat, loot, or a special event.", 25),
        "first-combat": ("💡 Combat is turn-based. Attack always hits. Heavy Strike hits harder but can miss 30% of the time. Defend reduces damage. Use Potion to heal.", 25),
        "first-skill": ("💡 Skills cost SP to use. You regenerate 2 SP per room entered. Powerful skills cost more — save them for tough fights and bosses.", 22),
        "first-levelup": ("💡 You leveled up! Choose one of three skills offered. You also have 3 stat points to spend on Vitality, Strength, Endurance, Spirit or Agility.", 22),
        "first-shop": ("💡 Shop! Spend your gold on potions, weapons, armor and special items. Soul Traps let you capture enemies as permanent minions.", 22),
        "first-floor2": ("💡 Floor 2 reached. The dungeon has 10 floors total. Enemies get stronger each floor. The boss is on floor 10 and has 3 phases.", 20),
        "first-boss": ("💡 Boss fight! Three phases — each phase the boss gets stronger. Use skills and potions. You cannot flee from a boss.", 25),
        "first-home": ("💡 Home unlocked! Buy a Bed to restore HP and SP. Use the Safe to store gold. Visit the Forge tab to craft weapons from materials you find.", 22),
        "first-elite": ("💡 Elite enemy! Elites have special abilities and much higher HP. Defeat them for bonus gold and a chance at a rare spirit.", 20),
        "first-loot": ("💡 Loot found! Check your inventory to use items. Weapons and armor can be equipped from inventory or at the Blacksmith.", 18),
    ]

    public static func seen(_ store: GameStore) -> [String] {
        guard let s = store.getItem("dd_dungeon_tips_seen"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return v
    }

    /// The tip, if it hasn't been shown yet; it counts as shown from now on.
    public static func take(_ id: String, store: GameStore) -> (text: String, seconds: Double)? {
        guard let tip = all[id] else { return nil }
        var s = seen(store)
        guard !s.contains(id) else { return nil }
        s.append(id)
        if let d = try? JSONEncoder().encode(s), let str = String(data: d, encoding: .utf8) { store.setItem("dd_dungeon_tips_seen", str) }
        return tip
    }
}
