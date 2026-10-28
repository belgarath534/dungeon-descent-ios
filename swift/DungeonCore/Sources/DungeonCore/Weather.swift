import Foundation

/// Tonight's conditions, rolled when a run starts (DUNGEON_WEATHER,
/// ABYSSAL_WEATHER, HOLLOW_WEATHER) and kept with the run. Every effect here
/// does what its line says; several of the web version's never did.
public struct Weather: Codable, Equatable, Sendable {
    public var id, name, icon, desc, effect: String
    public var enemyAtkMult = 1.0
    public var playerAtkMult = 1.0
    public var goldMult = 1.0
    public var combatBonus = 0.0
    public var roomHpLoss = 0
    public var hpBonus = 0
    public var spBonus = 0
    public var spDiscount = 0
    public var potionBoost = 0.0
    public var damageTaken = 1.0
    public var hpPerKill = 0
    /// Ancient Curse: 1 HP more from every enemy hit, whatever your defense.
    public var cursedArmor = false
    /// The Hollow's Silent Night: the Weeping Child comes twice as often.
    public var silentNight = false
    /// The Hollow's Full Moon: enemies 20% stronger.
    public var enemyMult = 1.0

    public var quiet: Bool { effect.hasPrefix("No special effects") }

    init(_ id: String, _ name: String, _ icon: String, _ desc: String, _ effect: String, _ set: (inout Weather) -> Void = { _ in }) {
        self.id = id; self.name = name; self.icon = icon; self.desc = desc; self.effect = effect
        set(&self)
    }

    static let common: [Weather] = [
        Weather("blood-moon", "Blood Moon", "🩸", "A crimson moon hangs overhead. Violence feels closer tonight.", "Enemies deal +20% damage. You deal +20% damage.") { $0.enemyAtkMult = 1.2; $0.playerAtkMult = 1.2 },
        Weather("divine-light", "Divine Blessing", "✨", "A warm golden light fills the dungeon. Something watches over you.", "+15 max HP this run. Potions heal 25% more.") { $0.hpBonus = 15; $0.potionBoost = 0.25 },
        Weather("cursed-fog", "Cursed Fog", "🌫️", "A grey mist clings to everything. Navigation feels wrong.", "Combat encounters +20% more frequent.") { $0.combatBonus = 0.2 },
        Weather("dead-calm", "Dead Calm", "🕯️", "Total silence. Not even the rats move.", "Enemies have -15% attack. Gold drops +30%.") { $0.enemyAtkMult = 0.85; $0.goldMult = 1.3 },
        Weather("fever-run", "Fever Run", "🔥", "The walls pulse with heat. Your blood is up.", "You deal +30% damage but take +15% more.") { $0.playerAtkMult = 1.3; $0.damageTaken = 1.15 },
        Weather("still-air", "Still Air", "💨", "Nothing unusual. The dungeon breathes slowly.", "No special effects."),
    ]

    static let byDungeon: [String: [Weather]] = [
        "The Ashbound Wastes": [
            Weather("scorching-heat", "Scorching Heat", "☀️", "The air burns your lungs. Every step costs more.", "You lose 2 HP per room entered. Enemies are weakened -15% ATK.") { $0.roomHpLoss = 2; $0.enemyAtkMult = 0.85 },
            Weather("ash-storm", "Ash Storm", "🌪️", "A wall of ash blots out the sky. Breathing is difficult.", "Gold drops +50%. Combat encounters +15% more frequent.") { $0.goldMult = 1.5; $0.combatBonus = 0.15 },
            Weather("ember-rain", "Ember Rain", "🔥", "Burning cinders fall from above. The ground is hot.", "You deal +25% damage. Enemies deal +25% damage.") { $0.playerAtkMult = 1.25; $0.enemyAtkMult = 1.25 },
            Weather("cooled-ashes", "Cooled Ashes", "⚫", "The wastes are quiet today. The fire has burned itself out.", "+20 max HP this run. Potions heal 30% more.") { $0.hpBonus = 20; $0.potionBoost = 0.3 },
            Weather("burning-winds", "Burning Winds", "💨", "Hot winds from the east. They carry the scent of something dead.", "Enemies are 20% stronger but drop double gold.") { $0.enemyAtkMult = 1.2; $0.goldMult = 2 },
        ],
        "Frosthold Abyss": [
            Weather("blizzard", "Blizzard", "❄️", "A whiteout. You can barely see your hands in front of you.", "Combat chance -10%. Enemy ATK +25% — they hunt by smell.") { $0.combatBonus = -0.1; $0.enemyAtkMult = 1.25 },
            Weather("frozen-moon", "Frozen Moon", "🌕", "Ice crystal light everywhere. Beautiful and deadly.", "Enemies deal +20% damage. You deal +30% damage.") { $0.enemyAtkMult = 1.2; $0.playerAtkMult = 1.3 },
            Weather("black-ice", "Black Ice", "🖤", "The floor is treacherous. One wrong step.", "You lose 3 HP per room entered. Gold drops +40%.") { $0.roomHpLoss = 3; $0.goldMult = 1.4 },
            Weather("cold-clarity", "Cold Clarity", "🌨️", "Crisp cold air sharpens the mind.", "+10 SP max. Skills cost 2 less SP this run.") { $0.spBonus = 10; $0.spDiscount = 2 },
            Weather("dead-winter", "Dead Winter", "💀", "The abyss is completely still. Even the ice makes no sound.", "No special effects. The cold is the only enemy."),
        ],
        "The Sunken Archives": [
            Weather("rising-tides", "Rising Tides", "🌊", "Water levels are higher than usual. Entire sections are flooded.", "+15% combat encounters. Enemies deal +15% damage.") { $0.combatBonus = 0.15; $0.enemyAtkMult = 1.15 },
            Weather("ancient-curse", "Ancient Curse", "📜", "A curse written in an unknown language activates.", "You lose 1 HP per enemy attack regardless of defense.") { $0.cursedArmor = true },
            Weather("library-silence", "Library Silence", "🤫", "An unnatural silence. Even combat feels muted.", "Gold drops +35%. Potions heal 20% more.") { $0.goldMult = 1.35; $0.potionBoost = 0.2 },
            Weather("ink-flood", "Ink Flood", "🖋️", "Black ink seeps from the walls. The texts are being erased.", "Enemies are 15% stronger but drop 40% more gold.") { $0.enemyAtkMult = 1.15; $0.goldMult = 1.4 },
            Weather("dry-archives", "Dry Archives", "📚", "The water has receded. The archives breathe.", "+20 max HP. No other effects.") { $0.hpBonus = 20 },
        ],
        "Crypt of Malachar": [
            Weather("dead-restless", "The Dead Stir", "💀", "Something has disturbed the ancient dead. They rise with purpose.", "Enemies deal +20% damage. Gold drops +50%.") { $0.enemyAtkMult = 1.2; $0.goldMult = 1.5 },
            Weather("crypt-mist", "Crypt Mist", "🌫️", "A pale mist fills every corridor. The cold seeps into your bones.", "You lose 2 HP per room. Potions heal 30% more.") { $0.roomHpLoss = 2; $0.potionBoost = 0.3 },
            Weather("unholy-night", "Unholy Night", "🩸", "The walls weep blood. Something ancient awakens deep below.", "Enemies deal +30% damage. You deal +30% damage.") { $0.enemyAtkMult = 1.3; $0.playerAtkMult = 1.3 },
            Weather("hallowed-ground", "Hallowed Ground", "✝️", "Ancient prayers still echo in this crypt. Something protects you.", "+25 max HP this run. Potions heal 40% more.") { $0.hpBonus = 25; $0.potionBoost = 0.4 },
            Weather("bone-silence", "The Silence of Bones", "🕯️", "Not even a rattle. The dead sleep deeply tonight.", "No special effects. The crypt is at peace."),
        ],
        "The Whispering Forest": [
            Weather("cursed-whispers", "Cursed Whispers", "👁️", "The voices grow louder. They speak of things that should not be.", "You lose 1 HP per room. Enemy ATK +15%.") { $0.roomHpLoss = 1; $0.enemyAtkMult = 1.15 },
            Weather("wild-hunt", "The Wild Hunt", "🐺", "Something ancient runs through the forest tonight. It is hunting.", "+30% combat encounters. Enemies deal +20% damage.") { $0.combatBonus = 0.3; $0.enemyAtkMult = 1.2 },
            Weather("forest-blessing", "Forest Blessing", "🌿", "The forest chooses to protect you tonight. The whispers are kind.", "+20 max HP. Heal 2 HP per enemy killed.") { $0.hpBonus = 20; $0.hpPerKill = 2 },
            Weather("silver-fog", "Silver Fog", "🌙", "A pale moonlit fog rolls in. Gold gleams beneath your feet.", "Gold drops +60%. Combat encounters -10%.") { $0.goldMult = 1.6; $0.combatBonus = -0.1 },
            Weather("deep-dark", "The Deep Dark", "🌑", "The forest closes its canopy. No light reaches the floor.", "You deal +25% damage. Enemies deal +25% damage.") { $0.playerAtkMult = 1.25; $0.enemyAtkMult = 1.25 },
        ],
        "The Abyssal Deep": [
            Weather("crushing-depth", "Crushing Depth", "💀", "The pressure at this depth is immense. Every room costs you.", "Lose 2 HP per room. Enemies deal +10% damage.") { $0.roomHpLoss = 2; $0.enemyAtkMult = 1.1 },
            Weather("bioluminescent", "Bioluminescent Bloom", "✨", "The water glows with ancient light. Gold shimmers everywhere.", "Gold drops +60%.") { $0.goldMult = 1.6 },
            Weather("dead-calm", "Dead Calm", "🌑", "The abyss is perfectly still. Not even the creatures stir.", "No special effects. An eerie peace."),
            Weather("thermal-vent", "Thermal Vent", "🌋", "Warm currents from below carry strange energy. Healing flows easier.", "Heal 3 HP per enemy killed.") { $0.hpPerKill = 3 },
            Weather("strong-current", "The Current", "🌊", "A deep current runs through everything. Skills flow easily.", "Skills cost 2 less SP this run.") { $0.spDiscount = 2 },
            Weather("midnight-zone", "Midnight Zone", "🔵", "At this depth no light reaches. Enemies are disoriented.", "Enemy ATK -20%. You deal +15% damage.") { $0.enemyAtkMult = 0.8; $0.playerAtkMult = 1.15 },
        ],
        "The Hollow": [
            Weather("foggy-night", "Foggy Night", "🌫️", "A thick fog fills the Hollow. Visibility is nearly zero. The house feels closer.", "Combat chance +15%. Something is moving in the fog.") { $0.combatBonus = 0.15 },
            Weather("full-moon", "Full Moon", "🌕", "Moonlight pours through broken windows. The shadows are sharp. The dead are restless.", "Enemies are 20% stronger but drop 50% more gold.") { $0.enemyMult = 1.2; $0.goldMult = 1.5 },
            Weather("silent-night", "Silent Night", "🤫", "The Hollow is perfectly silent. Even your footsteps make no sound. Something is listening.", "The Weeping Child appears twice as often.") { $0.silentNight = true },
            Weather("witching-hour", "The Witching Hour", "🕛", "It is exactly midnight in the Hollow. The clocks stopped at this moment years ago.", "You deal 25% more damage.") { $0.playerAtkMult = 1.25 },
            Weather("still-and-cold", "Still and Cold", "❄️", "Nothing unusual. The Hollow is quiet and cold. The house is just waiting.", "No special effects. The house observes."),
        ],
    ]

    /// rollDungeonWeather / rollAbyssalWeather / rollHollowWeather. Dungeons
    /// without their own table share the common one.
    public static func roll(for dungeon: String, dice: inout some Dice) -> Weather {
        let pool = byDungeon[dungeon] ?? common
        return pool[dice.roll(0...(pool.count - 1))]
    }

    /// applyDungeonWeatherBonuses: max HP and SP for the run.
    public static func start(_ run: inout Run, dice: inout some Dice) {
        let w = roll(for: run.dungeon, dice: &dice)
        run.weather = w
        if w.hpBonus > 0 { run.maxHp += w.hpBonus; run.hp = min(run.maxHp, run.hp + w.hpBonus) }
        if w.spBonus > 0 { run.maxSp += w.spBonus; run.sp = min(run.maxSp, run.sp + w.spBonus) }
    }

    /// What's said when the run begins.
    public var announcement: String {
        let lead = id == "foggy-night" || id == "full-moon" || id == "silent-night" || id == "witching-hour" || id == "still-and-cold"
            ? "Tonight in the Hollow" : "Dungeon condition"
        return "\(icon) \(lead): \(name). \(desc)" + (quiet ? "" : " Effect: \(effect)")
    }
}
