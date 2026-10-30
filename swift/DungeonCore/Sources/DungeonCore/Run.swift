import Foundation

/// The state of one dungeon run (the web version's `DS` object).
/// Only the fields the ported systems use are here so far; more get added as
/// each system moves over.
public struct Run: Codable, Sendable {
    public var name: String
    public var cls: String
    public var race: String
    public var prof: String
    public var dungeon: String
    public var difficulty: GameData.Difficulty

    public var floor: Int
    public var roomsOnFloor = 0
    public var totalRooms = 0
    public var floorRoomsNeeded = 6

    public var maxHp: Int
    public var hp: Int
    public var maxLives: Int
    public var lives: Int
    public var atk: ClosedRange<Int>
    public var def: Int
    public var atkBonus = 0
    public var defBonus = 0
    public var critBonus = 0.0

    public var gold = 0
    public var xp = 0
    public var level = 1
    public var levelCap: Int
    public var levelPoints = 0
    public var sp = 20
    public var maxSp = 20
    public var kills = 0
    public var luckBonus = 0.0
    public var fleeBonus = 0.0
    /// The Golden Dream: gold from kills × 1.30 this run.
    public var dreamGoldMult = 1.0
    /// The captured enemy fighting beside you (Home → Minions).
    public var minion: Minion? = nil
    /// One-off lines for the log when the run begins (dream buffs).
    public var startNotes: [String] = []
    /// Home skill upgrades ("Warrior_Shield_Bash": 3).
    public var skillLevels: [String: Int] = [:]
    // Subclass (chosen at level 5) and its passives' state
    public var subclass: String? = nil
    public var warlordAtk = 0
    public var battleHymnTurns = 0
    public var smiterCount = 0
    public var bombReady = false
    public var undyingUsed = false
    public var beast = 0
    /// The spirit companion's id.
    public var spirit: String? = nil
    /// Shadow Corruption stacks (The Shadow World).
    public var shadowCorruption = 0
    /// The rest of an ambush: enemies fighting alongside `enemy`, your target.
    public var foes: [Enemy] = []
    /// Shadow World enemies killed this run, for echo ambushes (newest last).
    public var shadowKilled: [Enemy] = []
    /// The Stalker Floor in progress, if the Darkness Swallower found you.
    public var stalker: StalkerFloor? = nil
    /// The Void Reaper wasn't stopped: enemies are 50% stronger (set while the curse lasts).
    public var worldCurse = false
    /// Spells known by the character (copied in at run start) and their cooldown.
    public var learnedSpells: [String] = []
    public var spellCooldown = 0
    public var spellsThisCooldown = 0
    /// Run-long spell results: Extraction's Void Curse (until the next floor),
    /// Legend of Echoes' shield, The Abyss Stares Back on you, The Hunger.
    public var voidCurse = false
    public var legendShield = false
    public var abyssCursed = false
    public var hungerKills = 0
    public var hungerDrain = 0
    /// Firelord: the next enemy walks into burning ground.
    public var burningGround = false
    /// Challenges: the Daily Dungeon's modifiers, its save key and start
    /// time, and the Gauntlet stage (0-based).
    public var dailyMods: [String] = []
    public var dailyKey: String? = nil
    public var dailyStart = 0.0
    public var gauntletStage: Int? = nil
    /// Hunter Mode: the hunter on your trail (nil when it's off or dead).
    public var hunter: Hunter.State? = nil
    /// Corruption Mode: the character's corruption (nil when it's off).
    public var corruption: Int? = nil
    /// Your guide's personality while the guide is on (nil when it's silenced).
    public var guide: String? = nil
    /// 3D Mode: the floor's rooms, walls and doors (nil when 3D Mode is off).
    public var roomGraph: RoomGraph? = nil
    /// The seasonal or weekly event running (getActiveEvent), set when the
    /// run starts and on each new floor.
    public var event: String? = nil
    /// Seasonal shop boosts for this run.
    public var xpBoostMult = 1.0
    public var xpBoostFloors = 0
    public var spiritBoost = false
    public var sparkler = false

    public var potionMult: Double
    public var undeadRes: Bool
    public var pilgrimProf: Bool
    public var graveRobberLoot = false
    public var hardcore = false
    public var ngPlus = false
    public var ngPlusCount: Int? = nil

    public var inCombat = false
    public var defending = false
    public var markedKill = false
    public var enemy: Enemy? = nil
    public var bossPhase = 1

    // Items and gear
    public var inventory: [Item] = []
    public var equippedWeapon: Item? = nil
    public var equippedArmor: Item? = nil

    // Effects from potions, runes, scrolls and traps
    public var tempAtk = 0
    public var tempAtkTurns = 0
    public var tempDef = 0
    public var tempDefTurns = 0
    public var swiftTurns = 0
    public var runeSpeed = false
    public var runeFortune = false
    public var luckKills = 0
    /// The Handwriting (Shadow World): your next attack is a critical hit.
    public var shadowNotes = false
    /// The Whispering Forest's corruption meter, 0–100.
    public var forestCorruption = 0
    /// The Medusa arc this run.
    public var medusa = Medusa.Arc()
    /// The Weeping Child was soothed this run (the Weeping Mother remembers).
    public var weepingChildSoothed = false
    /// The Time Descender appears once a run at most.
    public var timeDescenderMet = false
    /// One wandering NPC a run.
    public var npcMet = false
    /// The floor where Friday the 13th's Black Box last appeared.
    public var blackBoxFloor = 0
    /// Tonight's conditions in this dungeon.
    public var weather: Weather? = nil
    /// This run's Run Modifier, if one rolled.
    public var modifier: String? = nil
    /// Alchemy potion effects (Bloodfire, Shadow Cloak, Rage Tonic …).
    public var brews = Alchemy.Brews()
    /// The race's ability is on (Races.start, with Class Traits on).
    public var raceTraits = false
    /// The class trait is on (ClassTraits.start, with Class Traits on).
    public var classTraits = false
    /// DeathKnight's Undying Resolve, still unused this run.
    public var undyingResolve = false
    /// Necromancer: a killed enemy that fights for you in the next fight.
    public var raised: Enemy? = nil
    /// Developer Tools: the next fight is an ambush / Medusa.
    public var devAmbush = false
    /// The Curse Shop's Cursed Modifier: this run gets a run modifier whatever the setting.
    public var cursedModifier = false
    /// The Freedom Potion's debuff immunity, turns left.
    public var freedomTurns = 0
    /// Warding Bells attuned: each avoids one trap when you search.
    public var wardingBell = 0
    /// The pre-boss gauntlet's waves, and how many are done.
    public var preBossWaves = 0
    public var preBossDone = 0
    /// The Shapeshifter's Mask was used this run.
    public var maskUsed = false
    /// Legacy Mode's Dungeon Tier for this run (1 = none).
    public var legacyTier = 1
    public var devMedusa = false
    /// Today's Daily Challenge effect ("ironDay" …), if you registered for it.
    public var dailyChallenge: String? = nil
    public var poisonTurns = 0
    public var poisonDamage = 0
    public var frozen = false

    // Skills
    public var unlockedSkills: [String] = []
    public var skillPool: [String] = []
    /// Skills offered at the last level-up, waiting for the player to pick one.
    public var skillChoices: [String] = []
    public var lastSkill: String? = nil
    /// Next skills cost no SP (Unlimited Power, Maestro, Spell Surge).
    public var freeSkills = 0
    /// Extra damage on skills / on everything for the rest of the run (masteries).
    public var skillDamageBonus = 0.0
    public var allDamageBonus = 0.0
    public var halfCostSkills = false
    public var resurrection = false
    public var debuffImmune = false
    public var usedOncePerRun: [String] = []
    /// Undying weapons and Sanctuary armor work once per floor.
    public var gearSavedThisFloor = false

    /// Effects that only last for the current fight.
    public var fight = FightEffects()

    // Room state
    public var searched = false
    public var firstSearchDone = false
    /// Rooms already rolled by a Scroll of Reveal, used before rolling new ones.
    public var upcomingRooms: [Rooms.Outcome] = []
    /// This floor's special rooms ("normal", "treasure", "rest" …), planned when the floor starts.
    public var roomPlan: [String] = []
    /// An event waiting for the player's choice.
    public var pendingEvent: String? = nil

    // For achievements
    public var startedAt = Date().timeIntervalSince1970
    public var diedThisRun = false
    public var usedPotion = false
    /// This floor's numbers for the Floor Complete panel, and the run's.
    public var floorStats = FloorStats()
    public var bestHit = 0
    public var potionsUsed = 0
    /// Floor 10's Elite Guardian has been beaten; the boss is next.
    public var guardianDone = false
    /// The character's origin, and its XP and per-level SP bonuses.
    public var backstory: String?
    public var backstoryXPBonus = 0.0
    public var backstorySPBonus = 0
    public var skillsUsed: [String] = []
    public var hpAtFloorStart = 0

    // Mystery Coin Shop upgrades (applyCoinUpgrades)
    public var coinUpgrades: Set<String> = []
    public var secondWind = false
    public var deathsBargain = false
    public var gamblerUsed = false
    public var luckyDescentUsed = false
    /// Damage Death's Bargain dealt on the last death (0 when it didn't fire).
    public var bargainStrike = 0

    /// This run's journal (DS.journalLog), saved to the character as "journal".
    public var journalLog: [JournalEntry] = []

    public func has(_ upgrade: String) -> Bool { coinUpgrades.contains(upgrade) }

    public var isDead: Bool { hp <= 0 }

    /// Attack from the equipped weapon: the middle of its range, as initDungeon() adds it.
    public var weaponBonus: Int {
        guard let w = equippedWeapon else { return 0 }
        let r = w.weaponAttack
        return (r.lowerBound + r.upperBound) / 2
    }

    /// Defense from the equipped armor.
    public var armorDef: Int { equippedArmor?.armorDefense ?? 0 }

    /// Everything added on top of the class's attack roll.
    public var totalAtkBonus: Int {
        atkBonus + weaponBonus + tempAtk + fight.atk + (fight.buffTurns > 0 ? fight.buffAtk : 0)
            - (equippedArmor?.armorType == "heavy" ? 1 : 0)
    }

    /// Total defense, before the +4 for defending.
    public var totalDef: Int { def + defBonus + armorDef + tempDef + fight.def + (fight.buffTurns > 0 ? fight.buffDef : 0) + ShadowWorld.armorDefense(self) }

    public var hasFleeRing: Bool { inventory.contains { $0.effect == "flee" } }

    /// Starts a run for a character, like initDungeon().
    public init(character ch: PlayerCharacter, gold: Int = 0) {
        let info = GameData.classInfo(ch.cls)
        name = ch.name
        cls = ch.cls
        race = ch.race
        prof = ch.prof
        dungeon = ch.dungeon
        difficulty = ch.difficultyLevel
        floor = max(ch.floor, 1)
        maxHp = info.maxHp
        hp = info.maxHp
        maxLives = difficulty.lives
        lives = difficulty.lives
        atk = info.atk
        def = info.def
        levelCap = ch.levelCap
        potionMult = ch.prof == "Herbalist" ? 2 : 1
        // The character's spirit, or the first starter (pickSpirit fallback).
        spirit = ch.lastSpirit.flatMap { Spirits.spirit($0)?.id } ?? "ember-fox"
        undeadRes = ch.prof == "Gravedigger"
        pilgrimProf = ch.prof == "Pilgrim"
        // Mercenary's starting blade. (The web version also sets 15 starting
        // gold, but then overwrites it with the wallet balance a few lines
        // later, so it never actually reaches the player.)
        if ch.prof == "Mercenary" { atkBonus += 3 }
        if ch.prof == "Warden" { defBonus += 3 }
        if ch.race == "Halfling" {
            luckBonus += 0.15
            atk = max(1, atk.lowerBound - 2)...max(2, atk.upperBound - 2)
        }
        self.gold = max(0, gold)
        hardcore = ch.hardcoreMode
        if ch.hunterMode { hunter = Hunter.State() }
        if ch.corruptionMode { corruption = min(100, max(0, ch.corruption)) }
        if ch.guideEnabled { guide = ch.guidePersonality }
        ngPlus = ch.ngPlusActive
        if case .number(let n)? = ch.extra["ngPlusCount"] { ngPlusCount = Int(n) }
        // Continue Journey carries level and XP into the next dungeon.
        if case .number(let l)? = ch.extra["carryLevel"] { level = max(1, Int(l)) }
        if case .number(let x)? = ch.extra["carryXp"] { xp = max(0, Int(x)) }
        if case .string(let b)? = ch.extra["backstory"] { backstory = b }
    }

    /// applyMilestoneBuffs: permanent rewards from bestiary milestones and
    /// Hall of Records awards ("dd_milestone_effects"). Like the web version,
    /// only these effects do anything at run start.
    public mutating func applyMilestoneBuffs(_ effects: [String: Int]) {
        func has(_ k: String) -> Bool { (effects[k] ?? 0) > 0 }
        if has("hpUp") { maxHp += 5; hp = min(maxHp, hp + 5) }
        if has("hpUpBig") { maxHp += 10; hp = min(maxHp, hp + 10) }
        if has("hpUpBig2") { maxHp += 15; hp = min(maxHp, hp + 15) }
        if has("hpUpNM") { maxHp += 20; hp = min(maxHp, hp + 20) }
        if has("defUp") { defBonus += 3 }
        if has("spUp") { maxSp += 5; sp = min(maxSp, sp + 5) }
    }

    /// Run-start effects that touch the shared wallet. Call once when a run
    /// begins. Grave Robber gets 50 gold every run and +20% gold from kills.
    public mutating func applyStartBonuses(wallet: Wallet) {
        if prof == "Grave Robber" {
            gold += 50
            wallet.addGold(50)
            graveRobberLoot = true
        }
        // The origin chosen at creation (BACKSTORIES). The web version applied
        // these to the previous run's state, so they never reached the player.
        switch backstory {
        case "exiled-noble", "debt-collector":
            let g = backstory == "exiled-noble" ? 15 : 25
            gold += g
            wallet.addGold(g)
        case "cursed-wanderer": maxHp += 10; hp = min(maxHp, hp + 10)
        case "former-soldier": defBonus += 2
        case "lost-scholar": backstoryXPBonus = 0.2
        case "true-believer": lives += 1; maxLives += 1
        case "last-hope": backstorySPBonus = 5; maxSp += 5; sp = min(maxSp, sp + 5)
        default: break
        }
    }
}

/// One line of a character's journal: "10/26 Floor 3" and what happened.
public struct JournalEntry: Codable, Sendable, Equatable {
    public var time: String
    public var text: String
    public init(time: String, text: String) { self.time = time; self.text = text }
}

/// What happened on the current floor (showFloorCompleteScreen).
public struct FloorStats: Codable, Sendable, Equatable {
    public var kills = 0
    public var damageDealt = 0
    public var damageTaken = 0
    public var bestHit = 0
    public var hpHealed = 0
    public var goldStart = 0
    public init(goldStart: Int = 0) { self.goldStart = goldStart }
}

/// Skill effects that last only for the current fight (reset when a new one starts).
public struct FightEffects: Codable, Sendable {
    /// The boss already asked its riddle this fight.
    public var riddleAsked = false
    /// Ranger's Opening Shot and Assassin's First Blood, still to come this fight.
    public var openingShot = false
    public var firstBlood = false
    /// The Necromancer's risen enemy, striking beside you.
    public var ally: Enemy? = nil
    /// Medusa's first gaze: defense down for this many turns.
    public var gazeTurns = 0
    /// Gold the Unlucky One took this fight (taken from your wallet too).
    public var stolenGold = 0
    /// Phantom Run: this fight's first strike still to come.
    public var phantomCrit = false
    /// Damage absorbed before HP (Mana Shield, Bone Shield …).
    public var shield = 0
    /// Enemy attacks dodged completely.
    public var dodges = 0
    /// Chance the enemy's next attack misses (Camouflage).
    public var enemyMiss = 0.0
    /// Incoming damage reduced by this share for some turns (Fortify, Barkskin …).
    public var reduce = 0.0
    public var reduceTurns = 0
    /// No hit can do more than this for some turns (Sanctuary).
    public var cap = 0
    public var capTurns = 0
    /// The enemy's next hits are multiplied by this (Holy Light, Taunt, Slow …).
    public var soften = 1.0
    public var softenHits = 0
    /// The enemy takes this much more damage for some turns (Death Mark, Hex …).
    public var vulnerable = 0.0
    public var vulnerableTurns = 0
    /// Your next attacks are multiplied by this (Sacred Blade, War Ballad …).
    public var empower = 1.0
    public var empowerCount = 0
    public var unstoppableTurns = 0
    public var regen = 0
    public var regenTurns = 0
    /// Share of damage taken reflected back (Thorns).
    public var thorns = 0.0
    public var thornsTurns = 0
    /// Flat damage dealt back to the enemy each time it hits you (Flame Shield).
    public var retaliate = 0
    /// HP healed on each of your hits (Holy Crusade).
    public var crusadeHeal = 0
    public var crusadeTurns = 0
    /// Chance the enemy hits itself instead (Nightmare).
    public var confuse = 0.0
    public var confuseTurns = 0
    /// Bonuses until the fight ends, and timed ones.
    public var atk = 0
    public var def = 0
    public var buffAtk = 0
    public var buffDef = 0
    public var buffTurns = 0
    /// Bomb that goes off on the enemy's next turn.
    public var stickyBomb = 0
    public var lethalTempo = 0.0
    public var firstHitDone = false
    public var warlord = false
    /// The enemy's attack drops by this each turn (Death and Decay).
    public var decay = 0
    public var decayTurns = 0
    public var damageTaken = 0
    public var recentHits: [Int] = []
    public var huntersMarkReady = false
    /// Wind Walker / Shadow first-strike crit and Trapper's first-hit stun are spent.
    public var subFirstStrike = false
    public var paradoxUsed = false
    /// Medusa's Serpent Guard is still up this fight.
    public var medusaGuard = false
    /// The Sorrow Hound's fear: your attacks do 20% less for this many turns.
    public var fearTurns = 0
    public var nullShieldUsed = false
    /// The Shapeshifter's Mask: the ability copied this fight, and its state.
    public var mask = ""
    public var maskGrow = 0
    public var maskToggle = false
    public var maskFear = 0
    public var maskCorrupt = 0
    // Spells (applySpellEffect)
    public var darkCurse = 0
    public var playerBurn = 0
    public var playerBurnTurns = 0
    /// A missed Fireball comes back on the enemy's next turn.
    public var fireballReturn = 0
    /// Turns the enemy strikes itself (Soul Bound, Extraction); 99 for the fight.
    public var controlled = 0
    public var gravePact = 0
    public var gravePactHp = 0
    public var soulDrain = 0
    /// Your last attack's damage, for Time Echo.
    public var lastAttack = 0
    /// Void Anchor: no items for this many turns.
    public var noItems = 0
    public var phantom = 0
    public var bloodOath = 0
    public var soulLeash = false
    public var curseEchoes = 0
    public var voidMirror = 0
    public var forgotten = 0
    /// Lose Reality's deadline (seconds since 1970), 0 when not running.
    public var loseRealityUntil = 0.0

    public init() {}
}

extension Run {
    /// Reads a saved run, filling any field it doesn't have (because it was
    /// saved by an older build) with that field's default, so adding fields
    /// never throws away a run in progress.
    public static func decodeSaved(_ data: Data) -> Run? {
        if let r = try? JSONDecoder().decode(Run.self, from: data) { return r }
        let blank = PlayerCharacter(name: "", cls: "Warrior", race: "Human", prof: "Blacksmith",
                                    dungeon: GameData.dungeons[0], difficulty: .wanderer)
        guard let defaults = try? JSONEncoder().encode(Run(character: blank)),
              let base = try? JSONSerialization.jsonObject(with: defaults) as? [String: Any],
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func merge(_ a: [String: Any], _ b: [String: Any]) -> [String: Any] {
            var out = a
            for (k, v) in b {
                if let av = a[k] as? [String: Any], let bv = v as? [String: Any] { out[k] = merge(av, bv) } else { out[k] = v }
            }
            return out
        }
        guard let merged = try? JSONSerialization.data(withJSONObject: merge(base, saved)) else { return nil }
        return try? JSONDecoder().decode(Run.self, from: merged)
    }
}

