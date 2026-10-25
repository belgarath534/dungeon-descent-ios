import Foundation

/// A class skill from the web version's CLASS_SKILLS (loaded from gamedata.json).
public struct Skill: Decodable, Equatable, Sendable {
    public let name: String
    public let icon: String
    public let desc: String
    public let spCost: Int
    public let tier: String
    public let effect: String
}

/// What a skill does. Skills the web version handles use its numbers; the 105
/// it never wired up follow their descriptions (see MIGRATION.md).
public struct SkillSpec: Sendable {
    // Damage
    var dmg = 0.0               // × your attack roll
    var hits = 1
    var pctEnemyMax = 0.0       // share of the enemy's max HP
    var pctEnemyHp = 0.0        // share of its current HP
    var pctEnemyMissing = 0.0   // share of the HP it has lost
    var flat = 0
    var playerMiss = 0.0
    var lowHp = 0.0, lowHpDmg = 0.0          // stronger when your HP is low
    var execute = 0.0, executeDmg = 0.0      // stronger when the enemy's HP is low
    var killBelow = 0.0                      // instant kill under this share of HP
    var aboveHp = 0.0, aboveHpDmg = 0.0      // stronger against a healthy enemy
    var special: String? = nil

    // Costs and healing
    var selfDamage = 0
    var selfDamageShare = 0.0   // share of damage dealt taken back
    var heal = 0
    var healShare = 0.0         // share of damage dealt healed
    var healMaxShare = 0.0
    var sp = 0
    var fillsSP = false
    var drainsSP = false

    // Lasting changes
    var permAtk = 0, permDef = 0, permMaxHp = 0, permMaxSp = 0
    var fightAtk = 0, fightDef = 0
    var buffAtk = 0, buffDef = 0, buffTurns = 0

    // Control and defense
    var isFree = false            // no counter-attack this turn
    var stun = 0, stunChance = 1.0
    var shield = 0
    var dodges = 0
    var enemyMiss = 0.0
    var reduce = 0.0, reduceTurns = 0
    var cap = 0, capTurns = 0
    var soften = 1.0, softenHits = 0
    var weaken = 1.0            // enemy attack × this for the rest of the fight
    var weakenFlat = 0
    var dot = 0, dotTurns = 0, dotChance = 1.0
    var vulnerable = 0.0, vulnerableTurns = 0, vulnerableChance = 1.0
    var empower = 1.0, empowerCount = 0
    var marksCrit = false
    var unstoppable = 0
    var grantsResurrection = false
    var regen = 0, regenTurns = 0
    var thorns = 0.0, thornsTurns = 0
    var retaliate = 0
    var crusade = 0, crusadeTurns = 0
    var confuse = 0.0, confuseTurns = 0
    var decay = 0, decayTurns = 0
    var escapes = false
    var freeSkills = 0
    var reveals = false
    var grantsWarlord = false
    var skillBonus = 0.0, allBonus = 0.0
    var halfCost = false
    var grantsDebuffImmunity = false
    var oncePerRun = false
    var shrinkEnemy = 0
}

// Builder: `hit(1.5).heal(10)` reads like the skill's description.
func hit(_ m: Double, _ hits: Int = 1) -> SkillSpec { var s = SkillSpec(); s.dmg = m; s.hits = hits; return s }
func util() -> SkillSpec { var s = SkillSpec(); s.isFree = true; return s }
func act() -> SkillSpec { SkillSpec() }
func pctMax(_ p: Double) -> SkillSpec { var s = SkillSpec(); s.pctEnemyMax = p; return s }
func pctHp(_ p: Double) -> SkillSpec { var s = SkillSpec(); s.pctEnemyHp = p; return s }
func flat(_ n: Int) -> SkillSpec { var s = SkillSpec(); s.flat = n; return s }
func special(_ id: String) -> SkillSpec { var s = SkillSpec(); s.special = id; return s }

extension SkillSpec {
    private func with(_ f: (inout SkillSpec) -> Void) -> SkillSpec { var s = self; f(&s); return s }
    func free() -> SkillSpec { with { $0.isFree = true } }
    func miss(_ p: Double) -> SkillSpec { with { $0.playerMiss = p } }
    func lowHp(_ below: Double, _ m: Double) -> SkillSpec { with { $0.lowHp = below; $0.lowHpDmg = m } }
    func execute(_ below: Double, _ m: Double) -> SkillSpec { with { $0.execute = below; $0.executeDmg = m } }
    func killBelow(_ p: Double) -> SkillSpec { with { $0.killBelow = p } }
    func ambush(_ above: Double, _ m: Double) -> SkillSpec { with { $0.aboveHp = above; $0.aboveHpDmg = m } }
    func missing(_ p: Double) -> SkillSpec { with { $0.pctEnemyMissing = p } }
    func plus(_ n: Int) -> SkillSpec { with { $0.flat += n } }
    func selfDmg(_ n: Int) -> SkillSpec { with { $0.selfDamage = n } }
    func recoil(_ p: Double) -> SkillSpec { with { $0.selfDamageShare = p } }
    func heal(_ n: Int) -> SkillSpec { with { $0.heal = n } }
    func lifesteal(_ p: Double) -> SkillSpec { with { $0.healShare = p } }
    func healPct(_ p: Double) -> SkillSpec { with { $0.healMaxShare = p } }
    func healFull() -> SkillSpec { with { $0.healMaxShare = 1 } }
    func sp(_ n: Int) -> SkillSpec { with { $0.sp = n } }
    func spFull() -> SkillSpec { with { $0.fillsSP = true } }
    func drainSP() -> SkillSpec { with { $0.drainsSP = true } }
    func perm(atk: Int = 0, def: Int = 0, hp: Int = 0, sp: Int = 0) -> SkillSpec {
        with { $0.permAtk = atk; $0.permDef = def; $0.permMaxHp = hp; $0.permMaxSp = sp }
    }
    func fight(atk: Int = 0, def: Int = 0) -> SkillSpec { with { $0.fightAtk = atk; $0.fightDef = def } }
    func buff(atk: Int = 0, def: Int = 0, turns: Int) -> SkillSpec { with { $0.buffAtk = atk; $0.buffDef = def; $0.buffTurns = turns } }
    func stun(_ n: Int = 1, chance: Double = 1) -> SkillSpec { with { $0.stun = n; $0.stunChance = chance } }
    func shield(_ n: Int) -> SkillSpec { with { $0.shield = n } }
    func dodge(_ n: Int = 1) -> SkillSpec { with { $0.dodges = n } }
    func enemyMiss(_ p: Double) -> SkillSpec { with { $0.enemyMiss = p } }
    func reduce(_ p: Double, _ turns: Int) -> SkillSpec { with { $0.reduce = p; $0.reduceTurns = turns } }
    func cap(_ n: Int, _ turns: Int) -> SkillSpec { with { $0.cap = n; $0.capTurns = turns } }
    func soften(_ m: Double, _ hits: Int) -> SkillSpec { with { $0.soften = m; $0.softenHits = hits } }
    func weaken(_ m: Double) -> SkillSpec { with { $0.weaken = m } }
    func weakenBy(_ n: Int) -> SkillSpec { with { $0.weakenFlat = n } }
    func dot(_ n: Int, _ turns: Int, chance: Double = 1) -> SkillSpec { with { $0.dot = n; $0.dotTurns = turns; $0.dotChance = chance } }
    func vulnerable(_ p: Double, _ turns: Int, chance: Double = 1) -> SkillSpec {
        with { $0.vulnerable = p; $0.vulnerableTurns = turns; $0.vulnerableChance = chance }
    }
    func empower(_ m: Double, _ count: Int) -> SkillSpec { with { $0.empower = m; $0.empowerCount = count } }
    func markCrit() -> SkillSpec { with { $0.marksCrit = true } }
    func unstoppable(_ turns: Int) -> SkillSpec { with { $0.unstoppable = turns } }
    func resurrect() -> SkillSpec { with { $0.grantsResurrection = true } }
    func regen(_ n: Int, _ turns: Int) -> SkillSpec { with { $0.regen = n; $0.regenTurns = turns } }
    func thorns(_ p: Double, _ turns: Int = 99) -> SkillSpec { with { $0.thorns = p; $0.thornsTurns = turns } }
    func retaliate(_ n: Int) -> SkillSpec { with { $0.retaliate = n } }
    func crusade(_ n: Int, _ turns: Int = 99) -> SkillSpec { with { $0.crusade = n; $0.crusadeTurns = turns } }
    func confuse(_ p: Double, _ turns: Int) -> SkillSpec { with { $0.confuse = p; $0.confuseTurns = turns } }
    func decay(_ n: Int, _ turns: Int) -> SkillSpec { with { $0.decay = n; $0.decayTurns = turns } }
    func escape() -> SkillSpec { with { $0.escapes = true } }
    func freeSkills(_ n: Int) -> SkillSpec { with { $0.freeSkills = n } }
    func reveal() -> SkillSpec { with { $0.reveals = true } }
    func warlord() -> SkillSpec { with { $0.grantsWarlord = true } }
    func mastery(skills: Double = 0, all: Double = 0, halfCost: Bool = false) -> SkillSpec {
        with { $0.skillBonus = skills; $0.allBonus = all; $0.halfCost = halfCost }
    }
    func debuffImmune() -> SkillSpec { with { $0.grantsDebuffImmunity = true } }
    func once() -> SkillSpec { with { $0.oncePerRun = true } }
    func shrink(_ n: Int) -> SkillSpec { with { $0.shrinkEnemy = n } }
}

/// Every skill's behavior, keyed "Class/effect". Several classes share an effect
/// name with different descriptions, so each class has its own entry.
enum SkillTable {
    static let specs: [String: SkillSpec] = [
        // Warrior
        "Warrior/shield-bash": hit(0.9).fight(def: 3),
        "Warrior/war-cry": hit(2.0),
        "Warrior/iron-stance": act().buff(def: 4, turns: 2),
        "Warrior/taunt": act().soften(0.5, 1),
        "Warrior/weapon-throw": hit(1.2),
        "Warrior/last-stand": hit(1.0).lowHp(0.30, 3.0),
        "Warrior/battle-hardened": util().perm(hp: 3),
        "Warrior/overwhelm": hit(0.8, 2),
        "Warrior/fortify": act().reduce(0.35, 3),
        "Warrior/execute": hit(1.0).execute(0.25, 3.0),
        "Warrior/unstoppable": act().unstoppable(2),
        "Warrior/warlord": act().warlord(),
        "Warrior/titan-smash": hit(4.0).selfDmg(15),
        "Warrior/battlecry": special("battlecry"),
        "Warrior/indomitable": act().healFull().once(),

        // Monk
        "Monk/swift-strike": hit(1.0, 2),
        "Monk/inner-focus": util().heal(15).sp(10),
        "Monk/wind-step": util().dodge(1),
        "Monk/ki-pulse": hit(1.5),
        "Monk/meditate": util().sp(8).heal(10),
        "Monk/pressure-point": special("pressure-point"),
        "Monk/iron-body": act().perm(def: 5),
        "Monk/thousand-cuts": hit(0.5, 4),
        "Monk/spirit-shield": util().shield(30),
        "Monk/zen-strike": util().empower(1.5, 3),
        "Monk/transcendence": act().empower(2.0, 2),
        "Monk/soul-surge": hit(3.5),
        "Monk/one-with-all": util().spFull().heal(25),
        "Monk/iron-fist": hit(2.5),
        "Monk/enlightenment": util().perm(sp: 10),

        // Assassin
        "Assassin/backstab": hit(3.0).miss(0.35),
        "Assassin/smoke-bomb": util().escape(),
        "Assassin/poison-blade": hit(1.0).dot(8, 3),
        "Assassin/shadowstep": util().empower(1.5, 1),
        "Assassin/cheap-shot": hit(0.8).stun(1),
        "Assassin/marked-kill": util().markCrit(),
        "Assassin/shadow-clone": hit(2.0),
        "Assassin/death-mark": util().vulnerable(0.5, 3),
        "Assassin/serrated-blade": hit(1.0).dot(5, 4),
        "Assassin/ambush": hit(1.0).ambush(0.75, 2.0),
        "Assassin/assassinate": hit(1.0).killBelow(0.20),
        "Assassin/shadow-form": util().dodge(2),
        "Assassin/fan-of-knives": hit(0.6, 5),
        "Assassin/lethal-tempo": special("lethal-tempo"),
        "Assassin/death-sentence": pctMax(0.40),

        // Paladin
        "Paladin/holy-strike": hit(1.0).heal(20),
        "Paladin/divine-shield": util().dodge(1),
        "Paladin/consecrate": util().reduce(0.20, 3),
        "Paladin/lay-on-hands": util().heal(35),
        "Paladin/holy-light": util().soften(0.5, 2),
        "Paladin/smite": hit(2.5),
        "Paladin/aura-of-faith": util().regen(5, 99),
        "Paladin/sacred-blade": util().empower(2.0, 3),
        "Paladin/holy-nova": hit(1.5).lifesteal(0.5),
        "Paladin/judgment": special("judgment"),
        "Paladin/resurrection": util().resurrect(),
        "Paladin/archangel": special("archangel"),
        "Paladin/divine-wrath": hit(5.0).drainSP(),
        "Paladin/sanctuary": util().cap(10, 3),
        "Paladin/holy-crusade": util().crusade(15),

        // Naturalist
        "Naturalist/entangle": hit(0.5).stun(1),
        "Naturalist/venom": util().dot(8, 3),
        "Naturalist/pack-bond": hit(1.3),
        "Naturalist/nature-mend": util().heal(20),
        "Naturalist/camouflage": util().enemyMiss(0.40),
        "Naturalist/call-wild": hit(2.0),
        "Naturalist/thorns": util().thorns(0.30),
        "Naturalist/plague": util().dot(10, 4),
        "Naturalist/predator": hit(2.5),
        "Naturalist/swarm": hit(1.0).stun(1),
        "Naturalist/ancient-grove": hit(2.0).heal(40),
        "Naturalist/apex-predator": hit(4.0),
        "Naturalist/plague-lord": util().dot(20, 5),
        "Naturalist/nature-wrath": hit(3.0),
        "Naturalist/one-nature": util().healFull(),

        // Sorcerer
        "Sorcerer/arcane-bolt": hit(1.8),
        "Sorcerer/mana-shield": util().shield(25),
        "Sorcerer/frost-bolt": hit(1.0).soften(0.7, 1),
        "Sorcerer/arcane-surge": hit(1.6).selfDmg(5),
        "Sorcerer/mana-tap": util().sp(12),
        "Sorcerer/obliterate": special("obliterate"),
        "Sorcerer/chain-lightning": hit(1.5).stun(1),
        "Sorcerer/arcane-armor": util().shield(40),
        "Sorcerer/gravity-well": util().soften(0.85, 3),
        "Sorcerer/spell-weave": hit(1.3, 2),
        "Sorcerer/singularity": pctMax(0.50),
        "Sorcerer/time-stop": hit(1.0, 3).stun(1),
        "Sorcerer/void-blast": hit(5.0).selfDmg(20),
        "Sorcerer/arcane-nova": hit(3.0),
        "Sorcerer/unlimited-power": util().freeSkills(3),

        // Necromancer
        "Necromancer/death-touch": hit(1.4).sp(5),
        "Necromancer/raise-dead": hit(0.8),
        "Necromancer/life-drain": hit(1.2).lifesteal(0.5),
        "Necromancer/bone-shield": util().shield(20),
        "Necromancer/curse": util().vulnerable(0.15, 3),
        "Necromancer/soul-harvest": hit(1.8).sp(8),
        "Necromancer/corpse-explosion": pctMax(0.35),
        "Necromancer/undying": util().unstoppable(1),
        "Necromancer/necrotic-bolt": hit(1.6),
        "Necromancer/plague-carrier": util().dot(12, 4),
        "Necromancer/army-of-dead": hit(0.7, 4),
        "Necromancer/death-pact": hit(5.0).selfDmg(30),
        "Necromancer/soul-storm": hit(3.0),
        "Necromancer/lich-form": special("lich-form"),
        "Necromancer/death-coil": hit(2.0).heal(25),

        // Berserker
        "Berserker/reckless-strike": hit(1.6).selfDmg(5),
        "Berserker/rage": util().buff(atk: 4, turns: 3),
        "Berserker/war-stomp": hit(0.8).stun(1),
        "Berserker/blood-frenzy": special("blood-frenzy"),
        "Berserker/headbutt": hit(1.4).weaken(0.8),
        "Berserker/rampage": hit(1.5, 2),
        "Berserker/undying-rage": hit(1.0).lowHp(0.30, 3.0),
        "Berserker/savage-blow": hit(2.5),
        "Berserker/berserker-cry": util().soften(0.7, 2),
        "Berserker/relentless": hit(1.3),
        "Berserker/wrath-incarnate": special("wrath-incarnate"),
        "Berserker/death-wish": special("death-wish"),
        "Berserker/berserker-god": special("berserker-god"),
        "Berserker/endless-rage": util().empower(2.0, 3),
        "Berserker/final-blow": hit(6.0).drainSP(),

        // Bard
        "Bard/battle-hymn": hit(1.5),
        "Bard/dissonance": util().fight(def: 3).weaken(0.85),
        "Bard/soothing-melody": util().heal(18),
        "Bard/taunt-song": util().enemyMiss(0.25),
        "Bard/rhythmic-strike": hit(1.2).sp(5),
        "Bard/war-ballad": util().empower(2.0, 2),
        "Bard/lullaby": act().stun(1),
        "Bard/discord": special("discord"),
        "Bard/heroic-verse": util().perm(hp: 5),
        "Bard/anthem": util().heal(15).sp(10),
        "Bard/song-of-doom": util().empower(3.0, 2),
        "Bard/requiem": pctMax(0.45),
        "Bard/epic-tale": special("epic-tale"),
        "Bard/maestro": util().freeSkills(3),
        "Bard/grand-finale": hit(5.0),

        // Alchemist
        "Alchemist/acid-flask": hit(1.4).weaken(0.85),
        "Alchemist/healing-brew": util().heal(25),
        "Alchemist/smoke-grenade": util().enemyMiss(0.35),
        "Alchemist/transmute": special("transmute"),
        "Alchemist/sticky-bomb": special("sticky-bomb"),
        "Alchemist/explosive-flask": hit(2.0),
        "Alchemist/philosopher-stone": special("philosopher-stone"),
        "Alchemist/elixir-of-rage": hit(3.0).selfDmg(10),
        "Alchemist/corrosion": util().weaken(0.5),
        "Alchemist/chain-reaction": hit(1.2, 3),
        "Alchemist/nova-bomb": pctMax(0.60),
        "Alchemist/grand-transmute": hit(4.0),
        "Alchemist/immortality-serum": util().unstoppable(2),
        "Alchemist/plague-bomb": util().dot(15, 6),
        "Alchemist/unstable-formula": special("unstable-formula"),

        // Blood Knight
        "BloodKnight/blood-strike": hit(2.0).selfDmg(8),
        "BloodKnight/crimson-slash": hit(1.4).heal(5),
        "BloodKnight/life-tap": special("life-tap"),
        "BloodKnight/blood-bath": util().fight(atk: 3),
        "BloodKnight/hemorrhage": hit(1.0).dot(8, 3),
        "BloodKnight/sanguine-fury": hit(3.0).selfDmg(20),
        "BloodKnight/blood-armor": util().shield(35),
        "BloodKnight/crimson-nova": hit(2.0),
        "BloodKnight/vein-tap": special("vein-tap"),
        "BloodKnight/exsanguinate": hit(1.8).dot(8, 3),
        "BloodKnight/blood-god": hit(5.0).lifesteal(0.5),
        "BloodKnight/crimson-storm": hit(0.8, 5),
        "BloodKnight/exanguination": pctMax(0.35),
        "BloodKnight/blood-pact": hit(6.0).selfDmg(40),
        "BloodKnight/immortal-blood": util().regen(10, 4),

        // Druid
        "Druid/nature-bolt": hit(1.3),
        "Druid/regrowth": util().heal(20),
        "Druid/thorn-whip": hit(1.4).weaken(0.85),
        "Druid/beast-form": util().buff(atk: 4, def: 2, turns: 2),
        "Druid/rejuvenate": util().sp(8).heal(12),
        "Druid/moonfire": hit(2.0),
        "Druid/spirit-form": util().heal(30).dodge(1),
        "Druid/barkskin": util().reduce(0.40, 2),
        "Druid/sunfire": hit(1.8).dot(8, 3),
        "Druid/wild-growth": util().regen(10, 3),
        "Druid/avatar-nature": special("avatar-nature"),
        "Druid/ancient-wrath": hit(4.0),
        "Druid/balance": util().healFull().spFull(),
        "Druid/stormcall": hit(3.0).stun(1),
        "Druid/verdant-tide": hit(2.5).heal(20),

        // Warlock
        "Warlock/dark-pact": hit(1.5).selfDmg(10),
        "Warlock/soul-rend": hit(1.4).heal(8),
        "Warlock/hex": util().vulnerable(0.5, 2),
        "Warlock/void-grasp": hit(1.3).weaken(0.8),
        "Warlock/life-leech": hit(1.2).lifesteal(0.5),
        "Warlock/shadow-bolt": hit(2.0),
        "Warlock/demonic-surge": hit(1.8).fight(atk: 3),
        "Warlock/soul-cage": act().stun(1),
        "Warlock/eldritch-blast": hit(2.5),
        "Warlock/pact-of-blood": hit(3.0).selfDmg(25),
        "Warlock/void-collapse": hit(4.0),
        "Warlock/warlock-soul-storm": special("soul-storm"),
        "Warlock/elder-invocation": special("elder-invocation"),
        "Warlock/oblivion": pctMax(0.70),
        "Warlock/final-pact": special("final-pact"),

        // Death Knight
        "DeathKnight/death-strike": hit(1.5).heal(5),
        "DeathKnight/bone-shield": util().buff(def: 5, turns: 3),
        "DeathKnight/death-grip": hit(1.2).weaken(0.7),
        "DeathKnight/plague": util().dot(8, 4),
        "DeathKnight/unholy-ground": util().dot(10, 5),
        "DeathKnight/death-coil": hit(2.0).heal(25),
        "DeathKnight/army-of-dead": flat(36),
        "DeathKnight/unholy-frenzy": util().buff(atk: 6, turns: 3),
        "DeathKnight/corpse-explosion": hit(2.5),
        "DeathKnight/death-pact": util().selfDmg(20).perm(atk: 10),
        "DeathKnight/apocalypse": hit(4.0).plus(20),
        "DeathKnight/lichform": util().resurrect(),
        "DeathKnight/soul-harvest-dk": util().heal(50),
        "DeathKnight/death-and-decay": util().decay(5, 5),
        "DeathKnight/the-lich-king": util().fight(atk: 15, def: 15).debuffImmune(),

        // Ranger
        "Ranger/aimed-shot": hit(1.6),
        "Ranger/rapid-fire": hit(0.9, 2),
        "Ranger/mark-kill": util().empower(2.0, 1),
        "Ranger/shadow-step": util().escape(),
        "Ranger/venom-strike": hit(1.0).dot(5, 3),
        "Ranger/eagle-eye": util().empower(1.5, 2),
        "Ranger/wing-gust": hit(0.5).stun(1),
        "Ranger/dragon-rush": hit(0.8, 3),
        "Ranger/draconic-surge": util().empower(1.5, 2),
        "Ranger/fire-breath": hit(1.5),
        "Ranger/dragonstrike": special("killshot"),
        "Ranger/apocalyptic-fire": hit(5.0),
        "Ranger/world-ender": pctMax(0.60),
        "Ranger/true-dragon-form": util().empower(3.0, 1).markCrit(),

        // Sentinel
        "Sentinel/scale-shield": util().dodge(1),
        "Sentinel/taunt": util().reduce(0.20, 2),
        "Sentinel/fortify": util().reduce(0.40, 2),
        "Sentinel/molten-scales": util().thorns(0.30, 1),
        "Sentinel/dragon-fear": util().soften(0.5, 2),
        "Sentinel/barkskin": util().buff(def: 8, turns: 3),
        "Sentinel/retribution": special("retribution"),
        "Sentinel/dk-undying": util().unstoppable(1),
        "Sentinel/death-nova": hit(2.0),
        "Sentinel/sanctuary": util().cap(10, 3),
        "Sentinel/apocalypse": hit(1.0).lowHp(0.25, 3.0),
        "Sentinel/dark-ascension": hit(4.0),
        "Sentinel/eternal-darkness": util().dodge(3),
        "Sentinel/death-decay": special("colossus"),

        // Cleric
        "Cleric/cleric-holy-light": util().heal(25),
        "Cleric/sacred-strike": hit(1.3),
        "Cleric/bless": util().fight(atk: 2, def: 3),
        "Cleric/cleric-smite": hit(1.5),
        "Cleric/prayer": util().sp(8).heal(12),
        "Cleric/divine-barrier": util().shield(40),
        "Cleric/consecrate-ground": util().reduce(0.30, 3),
        "Cleric/holy-word": hit(2.0).stun(1),
        "Cleric/mass-heal": util().heal(45),
        "Cleric/angel-guard": util().cap(8, 3),
        "Cleric/miracle": util().healFull(),
        "Cleric/cleric-crusade": util().crusade(20, 3),
        "Cleric/divine-judgment": special("judgment"),
        "Cleric/cleric-resurrection": util().resurrect(),
        "Cleric/wrath-of-god": hit(5.0).drainSP(),

        // Wizard
        "Wizard/arcane-bolt": hit(1.4),
        "Wizard/arcane-study": util().reveal(),
        "Wizard/mana-shield": util().shield(35),
        "Wizard/spell-surge": util().freeSkills(1),
        "Wizard/frost-nova": act().stun(1),
        "Wizard/arcane-missiles": hit(0.6, 3),
        "Wizard/time-warp": hit(1.0, 2),
        "Wizard/polymorph": util().soften(0.5, 3),
        "Wizard/mana-drain": util().sp(20),
        "Wizard/arcane-explosion": hit(2.5),
        "Wizard/spellsteal": util().perm(atk: 5),
        "Wizard/arcane-singularity": pctHp(0.50),
        "Wizard/time-stop": act().stun(2),
        "Wizard/meteor": hit(4.0).killBelow(0.30),
        "Wizard/arcane-mastery": util().mastery(skills: 0.5),

        // Elementalist
        "Elementalist/fireball": hit(1.8).dot(6, 3, chance: 0.20),
        "Elementalist/ice-shard": hit(1.0).soften(0.7, 1),
        "Elementalist/lightning-bolt": hit(1.5),
        "Elementalist/flame-shield": util().retaliate(10),
        "Elementalist/frost-armor": util().buff(def: 6, turns: 3),
        "Elementalist/chain-lightning": hit(2.3),
        "Elementalist/meteor-shower": hit(0.8, 3),
        "Elementalist/blizzard": util().dodge(2),
        "Elementalist/inferno": util().dot(15, 3),
        "Elementalist/storm-call": util().empower(1.4, 2),
        "Elementalist/elemental-burst": special("elemental-burst"),
        "Elementalist/absolute-zero": act().stun(3),
        "Elementalist/solar-flare": util().dodge(3).vulnerable(1.0, 3),
        "Elementalist/thunderstrike": hit(4.0),
        "Elementalist/elemental-mastery": util().mastery(skills: 1.0),

        // Void Walker
        "VoidWalker/void-strike": hit(1.6),
        "VoidWalker/phase": util().dodge(1),
        "VoidWalker/void-pulse": hit(1.4).heal(10),
        "VoidWalker/dark-step": util().empower(2.0, 1),
        "VoidWalker/null-field": util().vulnerable(0.25, 2),
        "VoidWalker/void-drain": hit(1.2).sp(8),
        "VoidWalker/shadow-meld": util().heal(20).sp(10),
        "VoidWalker/void-rupture": hit(2.5).weakenBy(5),
        "VoidWalker/entropy": hit(0.9, 3),
        "VoidWalker/oblivion": act().stun(2),
        "VoidWalker/void-collapse": hit(4.0).recoil(0.2),
        "VoidWalker/phase-form": util().dodge(2),
        "VoidWalker/annihilation": SkillSpec().missing(1.0),
        "VoidWalker/void-mastery": util().perm(atk: 3, def: 3),
        "VoidWalker/the-void": util().mastery(all: 1.0),

        // Shadow Mage
        "ShadowMage/shadow-bolt": hit(1.5).vulnerable(0.15, 3, chance: 0.25),
        "ShadowMage/darkness": util().dodge(1),
        "ShadowMage/shadow-touch": hit(1.2).heal(5),
        "ShadowMage/nightmare": util().confuse(0.5, 2),
        "ShadowMage/shroud": util().reduce(0.30, 3),
        "ShadowMage/soul-rend": hit(2.0).shrink(10),
        "ShadowMage/shadow-clone-sm": util().empower(1.6, 1),
        "ShadowMage/dark-pact": util().perm(atk: 5, hp: -5),
        "ShadowMage/cursed-touch": util().vulnerable(0.15, 99),
        "ShadowMage/shadow-world": util().dodge(1).empower(2.0, 1),
        "ShadowMage/shadow-storm": hit(0.7, 5),
        "ShadowMage/dark-ascension": util().fight(atk: 10, def: 10),
        "ShadowMage/void-shadow": hit(3.5).vulnerable(0.15, 99),
        "ShadowMage/night-terror": util().dodge(3),
        "ShadowMage/shadow-mastery": util().mastery(skills: 2.0),

        // Time Mage
        "TimeMage/slow": util().soften(0.5, 3),
        "TimeMage/haste": hit(1.0, 2),
        "TimeMage/rewind": special("rewind"),
        "TimeMage/time-skip": act().stun(1),
        "TimeMage/temporal-sight": util().reduce(0.5, 1),
        "TimeMage/time-lock": act().stun(2).vulnerable(0.5, 2),
        "TimeMage/chronostrike": hit(1.0, 2),
        "TimeMage/paradox": util().empower(2.0, 1),
        "TimeMage/age": util().weakenBy(5),
        "TimeMage/time-surge": util().buff(atk: 4, turns: 4),
        "TimeMage/time-stop-tm": hit(1.0, 2).stun(1),
        "TimeMage/temporal-rift": hit(3.5),
        "TimeMage/chrono-mastery": util().debuffImmune(),
        "TimeMage/rewrite": special("rewrite"),
        "TimeMage/eternity": util().spFull(),

        // Shaman
        "Shaman/earthshake-sk": hit(1.6).stun(1, chance: 0.40),
        "Shaman/spirit-heal": util().heal(25),
        "Shaman/natures-wrath": hit(1.4).dot(8, 3, chance: 0.30),
        "Shaman/stone-skin": util().buff(def: 8, turns: 3),
        "Shaman/spirit-call": flat(20),
        "Shaman/totemic-strike": hit(2.0).heal(10),
        "Shaman/earthquake": hit(2.5).stun(1),
        "Shaman/ancestral-guard": util().reduce(0.5, 2),
        "Shaman/storm-totem": util().dot(12, 3),
        "Shaman/earth-barrier": util().shield(40),
        "Shaman/volcano": hit(4.0).dot(10, 3),
        "Shaman/world-shatter": hit(3.5),
        "Shaman/spirit-army": flat(75),
        "Shaman/earth-mastery": util().perm(def: 5).mastery(skills: 1.0),
        "Shaman/gaias-wrath": hit(5.0).once(),

        // Arcanist
        "Arcanist/arcane-bolt": hit(1.5),
        "Arcanist/mana-shield": util().shield(25),
        "Arcanist/arcane-pulse": hit(1.3).sp(8),
        "Arcanist/spell-echo": special("spell-echo"),
        "Arcanist/arcane-eye": util().reveal(),
        "Arcanist/arcane-storm": hit(2.0).stun(1, chance: 0.30),
        "Arcanist/spell-steal-arc": special("spell-steal"),
        "Arcanist/arcane-surge": util().freeSkills(1).empower(1.5, 1),
        "Arcanist/mana-burn": special("mana-burn"),
        "Arcanist/arcane-armor": util().buff(def: 10, turns: 3),
        "Arcanist/pure-destruction": hit(4.0),
        "Arcanist/arc-singularity": pctHp(0.50),
        "Arcanist/spell-mastery": util().mastery(skills: 0.4, halfCost: true),
        "Arcanist/arcane-overload": hit(5.0).selfDmg(30),
        "Arcanist/omnimancy": special("omnimancy"),
    ]

    static func spec(cls: String, effect: String) -> SkillSpec {
        specs["\(cls)/\(effect)"] ?? hit(1.0)
    }
}
