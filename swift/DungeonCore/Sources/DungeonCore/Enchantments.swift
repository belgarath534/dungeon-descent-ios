import Foundation

/// 12.4: enchantments on weapons and armor (docs/12.4-CORRUPTION.md section 5).
public enum Enchantments {
    /// The type your basic and heavy attacks deal (an elemental weapon
    /// enchantment changes it; Physical until then).
    public static func attackType(_ run: Run) -> DamageType { .physical }
}
