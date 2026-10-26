import Foundation

/// Weapon and armor rarities (WEAPON_RARITIES, RARITY_EFFECTS, ARMOR_RARITY_EFFECTS).
/// A rare drop gets stronger stats and one special effect from its tier.
public enum Rarity {
    public struct Tier: Sendable {
        public let id: String
        public let label: String
        public let symbol: String
        public let multiplier: Double
        let dropChance: Double
        let effectTier: String?
    }

    public struct Effect: Sendable {
        public let id: String
        public let name: String
        public let desc: String
    }

    public static let tiers: [Tier] = [
        Tier(id: "common", label: "Common", symbol: "⚪", multiplier: 1.0, dropChance: 0.60, effectTier: nil),
        Tier(id: "uncommon", label: "Uncommon", symbol: "🟢", multiplier: 1.15, dropChance: 0.25, effectTier: "minor"),
        Tier(id: "rare", label: "Rare", symbol: "🔵", multiplier: 1.30, dropChance: 0.10, effectTier: "moderate"),
        Tier(id: "epic", label: "Epic", symbol: "🟣", multiplier: 1.50, dropChance: 0.04, effectTier: "strong"),
        Tier(id: "legendary", label: "Legendary", symbol: "🟡", multiplier: 1.75, dropChance: 0.009, effectTier: "legendary"),
        Tier(id: "mythic", label: "Mythic", symbol: "🔴", multiplier: 2.20, dropChance: 0.001, effectTier: "mythic"),
    ]

    static let weaponEffects: [String: [Effect]] = [
        "minor": [Effect(id: "keen", name: "Keen", desc: "+5% critical hit chance."),
                  Effect(id: "swift", name: "Swift", desc: "First attack each combat deals +20% damage.")],
        "moderate": [Effect(id: "vampiric", name: "Vampiric", desc: "Heals 3 HP on every hit."),
                     Effect(id: "serrated", name: "Serrated", desc: "15% chance to hit twice per attack."),
                     Effect(id: "weighted", name: "Weighted", desc: "Heavy strikes never miss."),
                     Effect(id: "fortune", name: "Fortune", desc: "+25% gold from every kill.")],
        "strong": [Effect(id: "soulbound", name: "Soulbound", desc: "Restores 5 SP on every kill."),
                   Effect(id: "thundering", name: "Thundering", desc: "25% chance to stun enemy on hit."),
                   Effect(id: "cursed", name: "Cursed", desc: "+40% damage but you take 3 HP per turn in combat."),
                   Effect(id: "executioner", name: "Executioner", desc: "+50% damage against enemies below 25% HP.")],
        "legendary": [Effect(id: "godslayer", name: "Godslayer", desc: "Deals double damage to bosses."),
                      Effect(id: "phantom", name: "Phantom", desc: "Attacks ignore all enemy defense."),
                      Effect(id: "lifesteal", name: "Lifesteal", desc: "Heals 15% of all damage dealt.")],
        "mythic": [Effect(id: "apocalypse", name: "Apocalypse", desc: "Skills cost 0 SP. All attacks deal +60% damage."),
                   Effect(id: "undying", name: "Undying", desc: "Once per floor survive a killing blow at 1 HP.")],
    ]

    static let armorEffects: [String: [Effect]] = [
        "minor": [Effect(id: "sturdy", name: "Sturdy", desc: "5% chance to fully block an attack."),
                  Effect(id: "light-step", name: "Light Step", desc: "+10% flee chance.")],
        "moderate": [Effect(id: "regenerating", name: "Regenerating", desc: "Heals 3 HP at the start of every enemy turn."),
                     Effect(id: "thorned", name: "Thorned", desc: "Reflects 15% of damage taken back at the attacker.")],
        "strong": [Effect(id: "fortified", name: "Fortified", desc: "-15% all incoming damage."),
                   Effect(id: "vengeful", name: "Vengeful", desc: "20% chance to counter for your own attack damage when hit.")],
        "legendary": [Effect(id: "juggernaut", name: "Juggernaut", desc: "Immune to being frozen."),
                      Effect(id: "unbreakable", name: "Unbreakable", desc: "No single hit can deal more than 25% of your max HP.")],
        "mythic": [Effect(id: "sanctuary", name: "Sanctuary", desc: "Once per floor, survive a killing blow at 1 HP."),
                   Effect(id: "aegis", name: "Aegis", desc: "-40% damage taken, but -20% damage dealt.")],
    ]

    /// The effects a tier can roll, for the Rarity Effects guide.
    public static func effects(for tier: Tier, weapon: Bool) -> [Effect] {
        tier.effectTier.flatMap { (weapon ? weaponEffects : armorEffects)[$0] } ?? []
    }

    /// Rolls a drop's rarity, rarest first like rollWeaponRarity().
    public static func roll(dice: inout some Dice) -> Tier {
        var remaining = 1.0
        for t in tiers.reversed() where t.id != "common" {
            if dice.chance(t.dropChance / max(0.0001, remaining)) { return t }
            remaining -= t.dropChance
        }
        return tiers[0]
    }

    /// Gives a weapon or armor its rarity: stronger stats, a name prefix and an effect.
    public static func apply(_ tier: Tier, to item: Item, dice: inout some Dice) -> Item {
        guard tier.id != "common", item.isWeapon || item.isArmor else { return item }
        var i = item
        if let base = i.atkBase { i.atkBase = base.map { jsRound(Double($0) * tier.multiplier) } }
        if let d = i.defBase { i.defBase = jsRound(Double(d) * tier.multiplier) }
        i.extra["rarity"] = .string(tier.id)
        i.extra["rarityLabel"] = .string(tier.label)
        i.extra["raritySymbol"] = .string(tier.symbol)
        if let key = tier.effectTier, let list = (i.isWeapon ? weaponEffects : armorEffects)[key], !list.isEmpty {
            let e = list[dice.roll(0...(list.count - 1))]
            i.extra["rarityEffect"] = .string(e.id)
            i.extra["rarityEffectName"] = .string(e.name)
            i.extra["rarityEffectDesc"] = .string(e.desc)
            i.desc = "[\(tier.label)] \(e.name) — \(e.desc) \(i.desc)"
            i.name = "\(tier.label) \(i.name)"
        }
        return i
    }
}

extension Item {
    /// The rarity effect id ("keen", "aegis" …), if this item has one.
    public var rarityEffect: String? {
        if case .string(let s)? = extra["rarityEffect"] { return s }
        return nil
    }
}

extension Run {
    var weaponEffect: String? { equippedWeapon?.rarityEffect }
    var armorEffect: String? { equippedArmor?.rarityEffect }
}
