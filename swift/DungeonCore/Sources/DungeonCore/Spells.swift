import Foundation

/// A spell scroll (or the Spell Book) in the Arcane Shop (ARCANE_SHOP_ITEMS).
public struct SpellEntry: Sendable, Equatable {
    public let id: String
    public let name: String
    public let icon: String
    public let cost: Int
    public let rarity: String
    /// nil for the Spell Book.
    public let spellId: String?
    public let desc: String

    public var isBook: Bool { spellId == nil }
}

/// SPELLS: the Arcane Shop, the Spell Book, learning, casting, and the
/// spell subclasses (Firelord, Stormcaller, Void Born, Phase Walker, Dark
/// Arts, Night Shroud, Time Lord, Earthbound, Pure Magic, Spell Weaver).
/// Casting is a free action, like the web version: the enemy doesn't get a
/// turn, and spells cool down over your next turns.
public enum Spells {
    public static let cooldownNormal = 3
    public static let cooldownPowerful = 6
    public static let powerful: Set<String> = ["time-stop", "redeemed-souls", "final-boss", "legend-of-echoes", "shadow-blast",
                                               "lose-reality", "grave-pact", "void-collapse"]

    static func e(_ id: String, _ name: String, _ icon: String, _ cost: Int, _ rarity: String, _ spell: String?, _ desc: String) -> SpellEntry {
        SpellEntry(id: id, name: name, icon: icon, cost: cost, rarity: rarity, spellId: spell, desc: desc)
    }

    /// The shop, in the web version's order. (It listed Shadow Blast twice;
    /// Swift lists it once, with the fuller description.)
    public static let shop: [SpellEntry] = [
        e("spell-book", "Spell Book", "📖", 200, "common", nil, "Allows magic classes to learn spells permanently. Required to build a spellbook."),
        e("scroll-soulfire", "Scroll of Soulfire", "🔥", 80, "common", "soulfire", "Common. Burns the enemy soul — ignores defense. 1.6x damage."),
        e("scroll-void-bolt", "Scroll of Void Bolt", "💜", 80, "common", "void-bolt", "Common. Darkness energy — 1.5x damage, 25% stun chance."),
        e("scroll-frost-lance", "Scroll of Frost Lance", "❄️", 80, "common", "frost-lance", "Common. Freeze the enemy — they skip their next attack."),
        e("scroll-blood-shield", "Scroll of Blood Shield", "🛡️", 90, "common", "blood-shield", "Common. Absorb the next hit completely."),
        e("scroll-agony", "Scroll of Agony", "🔥", 100, "common", "agony", "Common. Curse with fire — 15 damage per turn for 3 turns. Fail: YOU burn for 25 per turn."),
        e("scroll-fireball", "Scroll of Fireball", "🔥", 90, "common", "fireball", "Common. 70% hits enemy for big damage. 30% miss — fireball returns. Defend fast."),
        e("scroll-earthshake", "Scroll of Earthshake", "🌍", 85, "common", "earthshake", "Common. Shake the earth — damage + random buff or debuff."),
        e("scroll-mirror-soul", "Scroll of Mirror Soul", "🪞", 95, "common", "mirror-soul", "Common. Reflect the last hit back at full damage."),
        e("scroll-soul-bound", "Scroll of Soul Bound", "🔗", 350, "rare", "soul-bound", "Rare. Control the enemy for 1-3 turns. Death Knight controls undead permanently."),
        e("scroll-soul-echo", "Scroll of Soul Echo", "👁️", 300, "rare", "soul-echo", "Rare. Predict enemy attack — roll % to block it fully or partially."),
        e("scroll-void-echo", "Scroll of Void Echo", "🌑", 320, "rare", "void-echo", "Rare. +50% ATK and Fury. Fail: enemy also gets +25% ATK and Fury."),
        e("scroll-extraction", "Scroll of Extraction", "⚗️", 380, "rare", "extraction", "Rare. 20% control enemy attack. Fail: Void Curse weakens all your attacks."),
        e("scroll-blood-price", "Scroll of Blood Price", "🩸", 350, "rare", "blood-price", "Rare. Spend your HP to deal massive damage. You choose the sacrifice."),
        e("scroll-grave-pact", "Scroll of Grave Pact", "⚰️", 400, "rare", "grave-pact", "Rare. Drop to 1 HP. Become unkillable and deal 2x damage for 3 turns."),
        e("scroll-time-stop", "Scroll of Time Stop", "⌛", 1200, "legendary", "time-stop", "Legendary. 50/50 — attack 3 times uninterrupted OR instant defeat."),
        e("scroll-legend-echoes", "Scroll of Legend of Echoes", "🌀", 1500, "legendary", "legend-of-echoes", "Legendary. Fight an Echo of yourself in 5 minutes. Win: -30% damage all run. Lose: everything."),
        e("scroll-redeemed-souls", "Scroll of Redeemed Souls", "☀️", 2000, "legendary", "redeemed-souls", "Legendary. 50% steal enemy HP. 30% they steal yours. 20% mutual drain. Either wins."),
        e("scroll-final-boss", "Scroll of The Final Boss", "👑", 1800, "legendary", "final-boss", "Legendary. Boss only. Success: one massive free attack. Fail: lose ALL buffs and items."),
        e("scroll-lose-reality", "Scroll of Lose Reality", "🌀", 1600, "legendary", "lose-reality", "Legendary. 5 minute timer. Kill the enemy or cease to exist. Win: massive reward + another scroll."),
        e("scroll-shadow-step", "Scroll of Shadow Step", "🌑", 80, "common", "shadow-step", "Common. Guaranteed escape from any combat."),
        e("scroll-time-echo", "Scroll of Time Echo", "⏰", 90, "common", "time-echo", "Common. Repeat your last attack instantly for free."),
        e("scroll-chain-curse", "Scroll of Chain Curse", "⛓️", 95, "common", "chain-curse", "Common. Every enemy hit reflects 50% damage back for 3 turns."),
        e("scroll-dungeon-echo", "Scroll of Dungeon Echo", "🏰", 100, "common", "dungeon-echo", "Common. Ask the dungeon one question. 50% answer. Fail: Tornado deals 60 damage to you."),
        e("scroll-the-tornado", "Scroll of The Tornado", "🌪️", 110, "common", "the-tornado", "Common. 80 damage to enemy but 40 damage to you. Pure chaos."),
        e("scroll-time-fracture", "Scroll of Time Fracture", "⏰", 340, "rare", "time-fracture", "Rare. Auto-dodge next enemy attack. 40% chance your next attack also slows."),
        e("scroll-the-hunger", "Scroll of The Hunger", "🖤", 360, "rare", "the-hunger", "Rare. Heal 15 HP per kill for 3 kills. After 3: hunger drains 15 HP per turn."),
        e("scroll-void-anchor", "Scroll of Void Anchor", "⚓", 320, "rare", "void-anchor", "Rare. Enemy cannot attack for 2 turns. You also cannot use items those turns."),
        e("scroll-phantom-step", "Scroll of Phantom Step", "👻", 300, "rare", "phantom-step", "Rare. Become intangible — next 2 hits pass through you. Cannot attack while intangible."),
        e("scroll-curse-ruin", "Scroll of Curse of Ruin", "💔", 380, "rare", "curse-of-ruin", "Rare. Enemy ATK permanently reduced 40% for fight. Costs massive SP."),
        e("scroll-the-last-word", "Scroll of The Last Word", "🗡️", 350, "rare", "the-last-word", "Rare. Only at below 20 HP. Deals damage equal to your MISSING HP."),
        e("scroll-nightmare", "Scroll of Nightmare Weave", "😱", 360, "rare", "nightmare-weave", "Rare. Enemy frozen in fear for 1 turn. Fail: fear reflects — you freeze and they get a free hit."),
        e("scroll-blood-oath", "Scroll of Blood Oath", "🩸", 400, "rare", "blood-oath", "Rare. Next 3 attacks cannot miss, deal 150% damage. After: take 20 HP damage per oath attack."),
        e("scroll-soul-fracture", "Scroll of Soul Fracture", "💥", 350, "rare", "soul-fracture", "Rare. Split enemy into 2 at 40% stats for 1 turn. Kill both: massive gold. Kill one: other reforms stronger."),
        e("scroll-dungeon-wrath", "Scroll of Dungeon's Wrath", "🏰", 280, "rare", "dungeon-wrath", "Rare. Deals 10 damage per floor you are on. Weak early. Devastating on floor 10."),
        e("scroll-soul-leash", "Scroll of Soul Leash", "🔗", 380, "rare", "soul-leash", "Rare. Tether your soul to the enemy. They die: you heal 50% of their max HP. You die: they also die."),
        e("scroll-the-reckoning", "Scroll of The Reckoning", "⚖️", 360, "rare", "the-reckoning", "Rare. Deals damage equal to total damage enemy dealt to you this fight."),
        e("scroll-curse-echoes", "Scroll of Curse of Echoes", "👁️", 340, "rare", "curse-echoes", "Rare. Every enemy attack also damages themselves at 30% for 3 turns."),
        e("scroll-the-sacrifice", "Scroll of The Sacrifice", "💔", 320, "rare", "the-sacrifice", "Rare. Instantly kill any non-boss enemy. You lose 40% current HP."),
        e("scroll-shadow-blast", "Scroll of Shadow Blast", "👤", 1000, "legendary", "shadow-blast", "Legendary. Summon a void spirit. 30-40% you control it — massive damage. 60-70% it defeats YOU instantly."),
        e("scroll-void-mirror", "Scroll of Void Mirror", "🖤", 1400, "legendary", "void-mirror", "Legendary. For 2 turns — your weaknesses become strengths and strengths become weaknesses."),
        e("scroll-abyss-stares", "Scroll of The Abyss Stares Back", "👁️", 1300, "legendary", "abyss-stares", "Legendary. 40% enemy loses 50% ATK forever. 60% YOU lose 50% ATK forever. Cannot be undone."),
        e("scroll-phantom-army", "Scroll of Phantom Army", "👻", 1100, "legendary", "phantom-army", "Legendary. 3 ghosts each deal 15 damage. 30% chance each misses. Could deal 45 or 0."),
        e("scroll-the-last-laugh", "Scroll of The Last Laugh", "😈", 1200, "legendary", "last-laugh", "Legendary. Only at enemy below 10% HP. Instant kill. Miscalculate: enemy heals to 50% HP."),
        e("scroll-shattered-reality", "Scroll of Shattered Reality", "🔮", 1500, "legendary", "shattered-reality", "Legendary. Enemy ATK becomes their DEF and DEF becomes ATK for 1 turn."),
        e("scroll-the-forgotten", "Scroll of The Forgotten", "🌫️", 1000, "legendary", "the-forgotten", "Legendary. Enemy forgets you exist for 2 turns — no attacks. Break it by attacking."),
        e("scroll-soul-drain", "Scroll of Soul Drain", "💀", 900, "legendary", "soul-drain", "Legendary. Steal HP directly from the enemy for 2 turns."),
        e("scroll-the-unwritten", "Scroll of The Unwritten", "❓", 500, "legendary", "the-unwritten", "Legendary. Random effect. Could be incredible. Could be catastrophic. Find out."),
        e("scroll-void-collapse", "Scroll of Void Collapse", "🌑", 1100, "legendary", "void-collapse", "Legendary. Massive damage. 20% hits back on you too."),
    ]

    public static var scrolls: [SpellEntry] { shop.filter { !$0.isBook } }

    public static func entry(_ spellId: String) -> SpellEntry? { shop.first { $0.spellId == spellId } }

    // Spell schools, for the subclasses that shape them.
    static let fire: Set<String> = ["soulfire", "agony", "fireball"]
    static let void: Set<String> = ["void-bolt", "void-echo", "void-anchor", "void-mirror", "void-collapse", "extraction"]
    static let shadow: Set<String> = ["shadow-step", "shadow-blast", "nightmare-weave", "phantom-step", "the-forgotten", "soul-drain"]

    // MARK: Learning

    static let magic: Set<String> = ["Wizard", "Sorcerer", "Arcanist", "Elementalist", "VoidWalker", "ShadowMage", "TimeMage",
                                     "Warlock", "Necromancer", "Druid", "Cleric", "Shaman"]

    /// isMagicClass: only these can learn spells into the book.
    public static func isMagic(_ cls: String) -> Bool { magic.contains(cls) }

    /// getSpellLearnChance
    public static func learnChance(_ cls: String) -> Double {
        if cls == "Arcanist" { return 0.95 }
        if ["Wizard", "Sorcerer", "Mage", "Arcanist", "Elementalist", "VoidWalker", "ShadowMage", "TimeMage"].contains(cls) { return 0.75 }
        if ["Warlock", "Necromancer", "Druid", "Cleric", "Shaman"].contains(cls) { return 0.45 }
        return 0.18
    }

    /// A character's learned spells and Spell Book, saved like the web version
    /// (learnedSpells, spellBook on the character).
    public static func learned(_ ch: PlayerCharacter) -> [String] {
        guard case .array(let a)? = ch.extra["learnedSpells"] else { return [] }
        return a.compactMap { if case .string(let s) = $0 { return s }; return nil }
    }

    public static func hasBook(_ ch: PlayerCharacter) -> Bool { ch.extra["spellBook"] == .bool(true) }

    public static func setLearned(_ ids: [String], on ch: inout PlayerCharacter) {
        ch.extra["learnedSpells"] = .array(ids.map { .string($0) })
    }

    public static func scrollItem(_ s: SpellEntry) -> Item {
        var it = Item(id: s.id, name: s.name, icon: s.icon, type: "spell-scroll", desc: s.desc)
        it.extra["spellId"] = .string(s.spellId ?? "")
        it.extra["rarity"] = .string(s.rarity)
        return it
    }

    public enum Purchase: Equatable, Sendable {
        case book, alreadyHaveBook, learned, failedToLearn, scroll, alreadyKnown, tooPoor
    }

    /// Buying from the Arcane Shop: the Spell Book, or a scroll that a magic
    /// class with the book tries to learn (it's used up either way), and
    /// everyone else carries as a one-use scroll.
    public static func buy(_ s: SpellEntry, character ch: inout PlayerCharacter, gold: Int, subclass: String?,
                           dice: inout some Dice) -> (Purchase, Item?) {
        if s.isBook {
            if hasBook(ch) { return (.alreadyHaveBook, nil) }
            guard gold >= s.cost else { return (.tooPoor, nil) }
            ch.extra["spellBook"] = .bool(true)
            return (.book, nil)
        }
        guard let id = s.spellId else { return (.tooPoor, nil) }
        if learned(ch).contains(id) { return (.alreadyKnown, nil) }
        guard gold >= s.cost else { return (.tooPoor, nil) }
        if hasBook(ch) && (isMagic(ch.cls) || subclass == "pure-magic") {
            // Spell Weaver: scrolls never fail to learn.
            if subclass == "spell-weaver" || dice.chance(learnChance(ch.cls)) {
                setLearned(learned(ch) + [id], on: &ch)
                return (.learned, nil)
            }
            return (.failedToLearn, nil)
        }
        return (.scroll, scrollItem(s))
    }

    // MARK: Drops

    /// checkSpellScrollDrop: 5% of kills (10% for Arcanists and Wizards) drop
    /// a scroll, common before floor 7, common or rare after.
    public static func drop(_ run: inout Run, dice: inout some Dice) -> Item? {
        let chance = run.cls == "Arcanist" || run.cls == "Wizard" ? 0.10 : 0.05
        guard dice.chance(chance) else { return nil }
        let pool = scrolls.filter { run.floor >= 7 ? $0.rarity != "legendary" : $0.rarity == "common" }
        guard !pool.isEmpty else { return nil }
        let item = scrollItem(pool[dice.roll(0...(pool.count - 1))])
        run.inventory.append(item)
        return item
    }

    /// Void Born starts each run with 3 void scrolls.
    public static func startingScrolls(_ run: inout Run, dice: inout some Dice) -> String? {
        guard run.subclass == "void-born" else { return nil }
        let pool = ["void-bolt", "void-anchor", "void-echo"].compactMap(entry)
        for _ in 0..<3 { run.inventory.append(scrollItem(pool[dice.roll(0...(pool.count - 1))])) }
        return "🌑 Void Born: 3 void scrolls are in your bag."
    }

    // MARK: Casting

    public static func cooldownFor(_ id: String, _ run: Run) -> Int {
        // Phase Walker: void spells cost no cooldown on floors 8–10.
        if run.subclass == "shadow-step" && void.contains(id) && (8...10).contains(run.floor) { return 0 }
        // Night Shroud: shadow spells cost no cooldown at night.
        if run.subclass == "night-shroud" && shadow.contains(id) && CoinShop.isNightNow() { return 0 }
        return powerful.contains(id) ? cooldownPowerful : cooldownNormal
    }

    /// Spell damage: 1.6 × your attack, shaped by your subclass.
    static func power(_ run: Run, _ id: String, against e: Enemy) -> Double {
        var m = 1.0
        if run.subclass == "pure-magic" { m *= 1.5 }
        if run.subclass == "firelord" && fire.contains(id) { m *= 1.6 }
        if run.subclass == "earthbound" && id == "earthshake" { m *= 1.8 }
        if run.subclass == "void-born" && void.contains(id) && isSpirit(e) { m *= 1.5 }
        return m
    }

    static func isSpirit(_ e: Enemy) -> Bool {
        e.flag("spiritOnly") || ["Ghost", "Spirit", "Wraith", "Specter", "Spectre", "Phantom", "Shade", "Wisp", "Banshee"].contains { e.name.contains($0) }
    }

    /// castSpell from the Spell Book: checks the cooldown, then casts.
    public static func cast(_ run: inout Run, _ id: String, dice: inout some Dice, wallet: Wallet? = nil,
                            now: Date = Date(), options: Combat.Options = Combat.Options()) -> TurnResult {
        var r = TurnResult()
        guard run.inCombat, run.enemy != nil else {
            r.acted = false
            r.announcement = "No enemy to target."
            return r
        }
        guard run.learnedSpells.contains(id) else {
            r.acted = false
            r.announcement = "You don't know that spell."
            return r
        }
        if run.spellCooldown > 0 {
            r.acted = false
            r.announcement = "Spells on cooldown. \(run.spellCooldown) turns remaining."
            return r
        }
        r = effect(&run, id, dice: &dice, wallet: wallet, now: now, options: options)
        guard r.acted else { return r }
        // Spell Weaver casts two spells before the cooldown starts.
        run.spellsThisCooldown += 1
        if run.subclass != "spell-weaver" || run.spellsThisCooldown >= 2 {
            run.spellCooldown = cooldownFor(id, run)
            run.spellsThisCooldown = 0
        }
        return r
    }

    /// Reading a scroll from the bag: one cast, no cooldown.
    public static func read(_ run: inout Run, at index: Int, dice: inout some Dice, wallet: Wallet? = nil,
                            now: Date = Date(), options: Combat.Options = Combat.Options()) -> TurnResult {
        var r = TurnResult()
        guard run.inventory.indices.contains(index), case .string(let id)? = run.inventory[index].extra["spellId"] else {
            r.acted = false
            r.announcement = "That scroll is gone."
            return r
        }
        guard run.inCombat, run.enemy != nil else {
            r.acted = false
            r.announcement = "Spell scrolls can only be read in combat."
            return r
        }
        let item = run.inventory[index]
        r = effect(&run, id, dice: &dice, wallet: wallet, now: now, options: options)
        if r.acted, let i = run.inventory.firstIndex(of: item) { run.inventory.remove(at: i) }
        return r
    }

    /// applySpellEffect. Most spells hit and move on; a few change the fight
    /// for some turns (the hooks below make those work).
    static func effect(_ run: inout Run, _ id: String, dice: inout some Dice, wallet: Wallet?, now: Date,
                       options: Combat.Options) -> TurnResult {
        var r = TurnResult()
        guard var e = run.enemy else { r.acted = false; return r }
        let name = entry(id)?.name ?? id
        let p = power(run, id, against: e)
        let base = Double(run.atk.upperBound + run.totalAtkBonus) * 1.6
        func dmg(_ m: Double) -> Int { max(1, Int((base * m * p).rounded(.down))) }
        func hit(_ d: Int) { e.hp = max(0, e.hp - d); r.playerDamage += d }
        var log: [String] = []
        var died = false
        // Dark Arts: shadow spells lay a stacking curse, -5 enemy ATK each, up to 5.
        func darkCurse() {
            guard run.subclass == "dark-arts", shadow.contains(id), run.fight.darkCurse < 5 else { return }
            run.fight.darkCurse += 1
            let lo = max(1, e.atk.lowerBound - 5), hi = max(1, e.atk.upperBound - 5)
            e.atk = lo...max(lo, hi)
            log.append("🖤 Dark Arts curse — \(e.name)'s attack falls by 5. (\(run.fight.darkCurse) of 5)")
        }

        switch id {
        case "soulfire":
            let d = dmg(1.6); hit(d)
            log.append("🔥 Soulfire! \(d) damage ignoring defense!")
        case "void-bolt":
            let d = dmg(1.5); hit(d)
            if dice.chance(0.25) {
                e.stunTurns = max(e.stunTurns, 1)
                log.append("💜 Void Bolt! \(d) damage. Enemy stunned!")
            } else {
                log.append("💜 Void Bolt! \(d) damage.")
            }
        case "frost-lance":
            let d = dmg(1.3); hit(d)
            // Stormcaller: ice freezes a turn longer.
            let turns = run.subclass == "stormcaller" ? 2 : 1
            e.stunTurns = max(e.stunTurns, turns)
            log.append("❄️ Frost Lance! \(d) damage. Enemy frozen — it skips its next \(turns == 1 ? "attack" : "2 attacks")!")
        case "blood-shield":
            run.fight.dodges += 1
            log.append("🛡️ Blood Shield! The next hit will be absorbed completely.")
        case "agony":
            if dice.chance(0.55) {
                let burn = run.subclass == "firelord" ? 24 : 15
                e.dotDamage = burn
                e.dotTurns = 3
                log.append("🔥 Agony! Enemy burns for \(burn) damage per turn for 3 turns!")
            } else {
                run.fight.playerBurn = 25
                run.fight.playerBurnTurns = 3
                log.append("🔥 Agony backfired! YOU burn for 25 damage per turn for 3 turns!")
            }
        case "fireball":
            if dice.chance(0.70) {
                let d = dmg(1.8); hit(d)
                log.append("🔥 Fireball! \(d) fire damage!")
            } else {
                run.fight.fireballReturn = dmg(1.8)
                log.append("🔥 Fireball missed! It's coming back — DEFEND on your next turn to halve it!")
            }
        case "mirror-soul":
            if let last = run.fight.recentHits.last, last > 0 {
                hit(last)
                log.append("🪞 Mirror Soul! Reflected \(last) damage back!")
            } else {
                log.append("🪞 Mirror Soul fizzled — no hit to reflect.")
            }
        case "soul-bound":
            if dice.chance(0.50) {
                let undead = Bestiary.undeadNames.contains(e.name)
                run.fight.controlled = run.cls == "DeathKnight" && undead ? 99 : dice.roll(1...2)
                log.append("🔗 Soul Bound! \(e.name) is under your control for \(run.fight.controlled == 99 ? "the rest of the fight" : "\(run.fight.controlled) turn\(run.fight.controlled == 1 ? "" : "s")") — it strikes itself.")
            } else {
                log.append("🔗 Soul Bound failed! The soul resisted.")
            }
        case "grave-pact":
            run.fight.gravePactHp = run.hp
            run.fight.gravePact = 3
            run.hp = 1
            log.append("⚰️ Grave Pact! HP dropped to 1. Unkillable for 3 turns, double damage. Your HP returns when it ends.")
        case "blood-price":
            let sacrifice = min(run.hp - 1, Int((Double(run.maxHp) * 0.3).rounded(.down)))
            guard sacrifice > 0 else {
                r.acted = false
                r.announcement = "You have no HP to spare for Blood Price."
                return r
            }
            run.hp = max(1, run.hp - sacrifice)
            let d = jsRound(Double(sacrifice * 3) * p); hit(d)
            log.append("🩸 Blood Price! Spent \(sacrifice) HP for \(d) damage!")
        case "time-stop":
            if run.subclass == "time-lord" || dice.chance(0.50) {
                e.stunTurns = max(e.stunTurns, 3)
                log.append("⌛ Time Stop! Time freezes — 3 free turns, the enemy cannot respond!")
            } else {
                run.hp = 0
                log.append("⌛ Time Stop failed. Time rejected you. Instant defeat.")
                died = true
            }
        case "redeemed-souls":
            let roll = Double(dice.roll(0...999)) / 1000
            if roll < 0.50 {
                let stolen = e.hp
                run.hp = min(run.maxHp, run.hp + stolen)
                r.playerDamage = e.hp
                e.hp = 0
                log.append("☀️ Redeemed Souls! Stole \(stolen) HP from the enemy!")
            } else if roll < 0.80 {
                e.hp = min(e.maxHp, e.hp + run.hp)
                run.hp = 1
                log.append("☀️ Redeemed Souls backfired! The enemy stole your HP!")
            } else {
                let m = Int((Double(min(run.hp, e.hp)) * 0.5).rounded(.down))
                run.hp = max(0, run.hp - m)
                hit(m)
                log.append("☀️ Redeemed Souls — mutual drain! Both lost \(m) HP!")
                died = run.hp <= 0
            }
        case "final-boss":
            guard e.isBoss else {
                r.acted = false
                r.announcement = "The Final Boss can only be cast on bosses."
                return r
            }
            let pct = Double(e.hp) / Double(max(1, e.maxHp))
            let chance = pct > 0.5 ? 0.10 : pct > 0.25 ? 0.35 : pct > 0.10 ? 0.60 : 0.85
            if dice.chance(chance) {
                let d = dmg(3.5); hit(d)
                log.append("👑 THE FINAL BOSS! \(d) unstoppable damage!")
            } else {
                // Every buff you had is stripped. (The web version also took
                // away your skills for the rest of the run.)
                let keep = (run.fight.damageTaken, run.fight.recentHits, run.fight.paradoxUsed, run.fight.firstHitDone)
                run.fight = FightEffects()
                (run.fight.damageTaken, run.fight.recentHits, run.fight.paradoxUsed, run.fight.firstHitDone) = keep
                run.tempAtk = 0; run.tempAtkTurns = 0; run.tempDef = 0; run.tempDefTurns = 0
                log.append("👑 The Final Boss laughed. All your buffs are stripped. Fight with raw power alone.")
            }
        case "void-collapse":
            let d = dmg(3.5); hit(d)
            let back = Int((Double(d) * 0.20).rounded(.down))
            run.hp = max(1, run.hp - back)
            log.append("🌑 Void Collapse! \(d) damage! You take \(back) back.")
        case "soul-drain":
            run.fight.soulDrain = 2
            log.append("💀 Soul Drain! You steal life from the enemy for 2 turns.")
        case "shadow-step":
            darkCurse()
            r.fled = true
            run.inCombat = false
            run.enemy = nil
            run.foes = []
            r.log = log + ["🌑 Shadow Step! You vanish from combat."]
            r.announcement = "Shadow Step! You vanished from combat."
            return r
        case "time-echo":
            if run.fight.lastAttack > 0 {
                let d = run.fight.lastAttack; hit(d)
                log.append("⏰ Time Echo! Your last attack repeats for \(d) damage!")
            } else {
                log.append("⏰ Time Echo fizzled — no attack to echo yet.")
            }
        case "chain-curse":
            run.fight.thorns = max(run.fight.thorns, 0.5)
            run.fight.thornsTurns = max(run.fight.thornsTurns, 3)
            log.append("⛓️ Chain Curse! Every enemy hit reflects 50% back for 3 turns.")
        case "dungeon-echo":
            if dice.chance(0.50) {
                run.fight.vulnerable = max(run.fight.vulnerable, 0.30)
                run.fight.vulnerableTurns = max(run.fight.vulnerableTurns, 3)
                log.append("🏰 Dungeon Echo! The dungeon answers — \(e.name)'s guard cracks. It takes 30% more damage for 3 turns.")
            } else {
                run.hp = max(0, run.hp - 60)
                log.append("🌪️ The dungeon went rogue! A tornado deals 60 damage to you!")
                died = run.hp <= 0
            }
        case "the-tornado":
            let d = jsRound(80 * p); hit(d)
            run.hp = max(0, run.hp - 40)
            log.append("🌪️ The Tornado! \(d) to the enemy, 40 to you!")
            died = run.hp <= 0
        case "time-fracture":
            run.fight.dodges += 1
            var line = "⏰ Time Fracture! The next enemy attack will be dodged."
            if run.subclass == "time-lord" || dice.chance(0.40) {
                run.fight.soften = min(run.fight.soften, 0.7)
                run.fight.softenHits = max(run.fight.softenHits, 2)
                line += " Time slows around \(e.name) — its next hits are weaker."
            }
            log.append(line)
        case "the-hunger":
            run.hungerKills = 3
            log.append("🖤 The Hunger! Heal 15 HP per kill for 3 kills. Then it feeds on you.")
        case "void-anchor":
            e.stunTurns = max(e.stunTurns, 2)
            run.fight.noItems = 2
            log.append("⚓ Void Anchor! \(e.name) cannot attack for 2 turns. You can't use items for 2 turns.")
        case "phantom-step":
            run.fight.phantom = 2
            log.append("👻 Phantom Step! The next 2 hits pass through you. You can't attack while intangible.")
        case "curse-of-ruin":
            let lo = max(1, jsRound(Double(e.atk.lowerBound) * 0.6)), hi = max(1, jsRound(Double(e.atk.upperBound) * 0.6))
            e.atk = lo...max(lo, hi)
            let sp = min(run.sp, 10)
            run.sp -= sp
            log.append("💔 Curse of Ruin! \(e.name)'s attack is cut 40% for the fight." + (sp > 0 ? " It drains \(sp) SP." : ""))
        case "the-last-word":
            guard run.hp <= Int((Double(run.maxHp) * 0.20).rounded(.down)) else {
                r.acted = false
                r.announcement = "The Last Word only works below 20% HP."
                return r
            }
            let d = jsRound(Double(run.maxHp - run.hp) * p); hit(d)
            log.append("🗡️ The Last Word! \(d) damage from your missing HP!")
        case "nightmare-weave":
            if dice.chance(0.50) {
                e.stunTurns = max(e.stunTurns, 1)
                log.append("😱 Nightmare Weave! \(e.name) is frozen in terror for a turn.")
            } else {
                run.frozen = true
                log.append("😱 Nightmare reflected! You are frozen — you lose your next turn.")
            }
        case "blood-oath":
            run.fight.bloodOath = 3
            log.append("🩸 Blood Oath! Your next 3 attacks can't miss and deal 150%. Each one costs 20 HP.")
        case "soul-fracture":
            let d = dmg(2.5); hit(d)
            log.append("💥 Soul Fracture! \(d) damage.")
        case "dungeon-wrath":
            let d = jsRound(Double(run.floor * 10) * p); hit(d)
            log.append("🏰 Dungeon's Wrath! Floor \(run.floor) × 10 — \(d) damage!")
        case "soul-leash":
            run.fight.soulLeash = true
            log.append("🔗 Soul Leash! Your soul is tethered to \(e.name). When it dies you heal half its max HP.")
        case "the-reckoning":
            if run.fight.damageTaken > 0 {
                let d = jsRound(Double(run.fight.damageTaken) * p); hit(d)
                log.append("⚖️ The Reckoning! \(d) damage returned!")
            } else {
                log.append("⚖️ The Reckoning fizzled — it hasn't hurt you yet.")
            }
        case "curse-echoes":
            run.fight.curseEchoes = 3
            log.append("👁️ Curse of Echoes! For 3 turns, every attack \(e.name) makes hurts it too.")
        case "the-sacrifice":
            guard !e.isBoss else {
                r.acted = false
                r.announcement = "The Sacrifice cannot kill bosses."
                return r
            }
            let cost = Int((Double(run.hp) * 0.40).rounded(.down))
            run.hp = max(1, run.hp - cost)
            r.playerDamage = e.hp
            e.hp = 0
            log.append("💔 The Sacrifice! \(e.name) is slain. You paid \(cost) HP.")
        case "shadow-blast":
            let chance = run.cls == "ShadowMage" || run.cls == "VoidWalker" ? 0.65 : run.cls == "DeathKnight" ? 0.50 : 0.35
            if dice.chance(chance) {
                let d = dmg(3.0); hit(d)
                log.append("👤 Shadow Blast! You control the spirit — \(d) massive damage!")
            } else {
                run.hp = 0
                log.append("👤 Shadow Blast failed! The spirit turns on you. Instant defeat.")
                died = true
            }
        case "void-mirror":
            run.fight.voidMirror = 2
            log.append("🖤 Void Mirror! For 2 turns, the enemy's blows heal you instead of hurting you.")
        case "abyss-stares":
            if dice.chance(0.40) {
                let lo = max(1, e.atk.lowerBound / 2), hi = max(1, e.atk.upperBound / 2)
                e.atk = lo...max(lo, hi)
                log.append("👁️ The Abyss stares back at \(e.name)! Its attack is halved forever.")
            } else {
                run.abyssCursed = true
                log.append("👁️ The Abyss stares back at YOU. Your attack is halved for the rest of this run.")
            }
        case "phantom-army":
            var total = 0
            for _ in 0..<3 where dice.chance(0.70) { total += jsRound(15 * p) }
            hit(total)
            log.append("👻 Phantom Army! \(total) total ghost damage!")
        case "last-laugh":
            if Double(e.hp) / Double(max(1, e.maxHp)) <= 0.10 {
                r.playerDamage = e.hp
                e.hp = 0
                log.append("😈 The Last Laugh! \(e.name) is instantly defeated!")
            } else {
                e.hp = max(e.hp, e.maxHp / 2)
                log.append("😈 The Last Laugh failed — \(e.name) heals to half HP!")
            }
        case "shattered-reality":
            // Enemies in Swift have no defense to swap, so its attack turns to
            // nothing and it's laid open for a turn.
            run.fight.soften = min(run.fight.soften, 0.25)
            run.fight.softenHits = max(run.fight.softenHits, 1)
            run.fight.vulnerable = max(run.fight.vulnerable, 0.5)
            run.fight.vulnerableTurns = max(run.fight.vulnerableTurns, 2)
            log.append("🔮 Shattered Reality! \(e.name)'s strength becomes weakness — its next hit is feeble and it takes 50% more damage.")
        case "the-forgotten":
            run.fight.forgotten = 2
            log.append("🌫️ The Forgotten. \(e.name) forgets you for 2 turns. Attacking breaks it.")
        case "the-unwritten":
            switch dice.roll(0...4) {
            case 0:
                run.hp = min(run.maxHp, run.hp + 40)
                log.append("❓ The Unwritten: healed 40 HP!")
            case 1:
                let d = dmg(2.5); hit(d)
                log.append("❓ The Unwritten: \(d) damage!")
            case 2:
                run.fight.atk += 8
                log.append("❓ The Unwritten: +8 ATK for this fight!")
            case 3:
                e.stunTurns = max(e.stunTurns, 2)
                log.append("❓ The Unwritten: \(e.name) is stunned for 2 turns!")
            default:
                run.gold += 100
                wallet?.addGold(100)
                log.append("❓ The Unwritten: 100 gold!")
            }
        case "lose-reality":
            run.fight.loseRealityUntil = now.addingTimeInterval(300).timeIntervalSince1970
            log.append("🌀 Lose Reality! You have 5 minutes to defeat \(e.name) or you cease to exist.")
        case "soul-echo":
            let chance = isMagic(run.cls) ? 0.55 : 0.30
            let roll = Double(dice.roll(0...999)) / 1000
            if roll < chance * 0.33 {
                run.fight.dodges += 1
                log.append("👁️ Soul Echo — a perfect prediction! The next hit is blocked.")
            } else if roll < chance {
                run.fight.reduce = max(run.fight.reduce, 0.60)
                run.fight.reduceTurns = max(run.fight.reduceTurns, 1)
                log.append("👁️ Soul Echo — partial. The next hit is reduced by 60%.")
            } else {
                log.append("👁️ Soul Echo failed. The future is unclear.")
            }
        case "void-echo":
            run.fight.atk += Int((Double(run.atk.upperBound) * 0.5).rounded(.down))
            if dice.chance(0.50) {
                log.append("🌑 Void Echo! +50% ATK for this fight!")
            } else {
                let lo = jsRound(Double(e.atk.lowerBound) * 1.25), hi = jsRound(Double(e.atk.upperBound) * 1.25)
                e.atk = lo...max(lo, hi)
                log.append("🌑 Void Echo! +50% ATK — but \(e.name) grows 25% stronger too!")
            }
        case "extraction":
            if dice.chance(0.20) {
                run.fight.controlled = max(run.fight.controlled, 1)
                log.append("⚗️ Extraction! You control \(e.name)'s next attack — it strikes itself.")
            } else {
                run.voidCurse = true
                log.append("⚗️ Extraction failed! Void Curse — your attacks are weakened until the next floor.")
            }
        case "earthshake":
            let d = dmg(1.6); hit(d)
            let roll = Double(dice.roll(0...999)) / 1000
            if run.cls == "Shaman" || run.subclass == "earthbound" || roll < 0.40 {
                e.stunTurns = max(e.stunTurns, 1)
                log.append("🌍 Earthshake! \(d) damage. The ground trembles — \(e.name) is stunned!")
            } else if roll < 0.65 {
                run.fight.def += 5
                log.append("🌍 Earthshake! \(d) damage. Stone rises to protect you — +5 DEF!")
            } else if roll < 0.80 {
                log.append("🌍 Earthshake! \(d) damage. The earth cracks beneath \(e.name).")
            } else {
                let back = Int((Double(d) * 0.3).rounded(.down))
                run.hp = max(1, run.hp - back)
                log.append("🌍 Earthshake backfired! \(d) to the enemy but \(back) to you from the shockwave!")
            }
        case "legend-of-echoes":
            if dice.chance(0.55) {
                run.legendShield = true
                log.append("🌀 Legend of Echoes! You faced your Echo and won. You take 30% less damage for the rest of this run!")
            } else {
                run.hp = 0
                log.append("🌀 Legend of Echoes! Your Echo was stronger. You have been consumed.")
                died = true
            }
        default:
            r.acted = false
            r.announcement = "\(name) has no effect."
            return r
        }
        darkCurse()
        if fire.contains(id) && e.isDead && run.subclass == "firelord" {
            run.burningGround = true
            log.append("🔥 The ground burns where \(e.name) fell.")
        }
        run.enemy = e
        // Stormcaller: damaging spells chain 40% into the rest of an ambush.
        if run.subclass == "stormcaller" && r.playerDamage > 0 && !run.foes.isEmpty {
            let chain = max(1, jsRound(Double(r.playerDamage) * 0.4))
            for i in run.foes.indices { run.foes[i].hp = max(1, run.foes[i].hp - chain) }
            log.append("⚡ The spell chains through the others for \(chain) each!")
        }
        r.log = ["✨ You cast \(name)!"] + log
        if died || run.hp <= 0 {
            r.playerDied = true
            run.inCombat = false
            r.announcement = log.joined(separator: " ")
            return r
        }
        // A free action: the enemy only acts if the fight goes on elsewhere
        // (the next enemy of an ambush steps up after a kill).
        r = Combat.finishTurn(&run, r, skipEnemy: true, dice: &dice, options: options)
        if r.announcement == nil || r.announcement == r.log.last { r.announcement = log.joined(separator: " ") }
        return r
    }

    // MARK: Hooks in the fight

    /// tickSpellCooldown, at the start of each of your turns.
    static func tick(_ run: inout Run, log: inout [String]) {
        if run.spellCooldown > 0 {
            run.spellCooldown -= 1
            if run.spellCooldown == 0 { log.append("✨ Spells ready.") }
        }
        if run.fight.noItems > 0 { run.fight.noItems -= 1 }
    }

    /// Lose Reality's clock ran out with the enemy still standing.
    static func realityLost(_ run: Run, now: Date) -> Bool {
        run.fight.loseRealityUntil > 0 && now.timeIntervalSince1970 >= run.fight.loseRealityUntil
    }

    /// Your attack this turn: Phantom Step stops it, The Forgotten breaks,
    /// Blood Oath empowers it, and the curses weaken it.
    static func shapeAttack(_ run: inout Run, _ dmg: Int, heavy: Bool, log: inout [String]) -> Int {
        var d = Double(dmg)
        if run.fight.phantom > 0 {
            log.append("👻 You're intangible — your strike passes straight through.")
            return 0
        }
        if run.fight.forgotten > 0 {
            run.fight.forgotten = 0
            log.append("🌫️ You strike — and \(run.enemy?.name ?? "the enemy") remembers you.")
        }
        if run.fight.bloodOath > 0 {
            run.fight.bloodOath -= 1
            d *= 1.5
            run.hp = max(1, run.hp - 20)
            log.append("🩸 Blood Oath strike! 150% damage — the oath takes 20 HP.")
        }
        if run.fight.gravePact > 0 { d *= 2 }
        if run.abyssCursed { d *= 0.5 }
        if run.voidCurse { d *= 0.75 }
        return jsRound(d)
    }

    /// Before the enemy attacks: Soul Drain, control, and forgetting.
    /// Returns true when it doesn't attack you.
    static func beforeEnemy(_ run: inout Run, log: inout [String]) -> Bool {
        guard var e = run.enemy else { return false }
        if run.fight.soulDrain > 0 {
            run.fight.soulDrain -= 1
            let steal = min(e.hp, max(8, jsRound(Double(e.maxHp) * 0.12)))
            e.hp -= steal
            run.hp = min(run.maxHp, run.hp + steal)
            run.enemy = e
            log.append("💀 Soul Drain steals \(steal) HP from \(e.name)!")
            if e.isDead { return true }
        }
        if run.fight.forgotten > 0 {
            run.fight.forgotten -= 1
            log.append("🌫️ \(e.name) has forgotten you. It does nothing.")
            return true
        }
        if run.fight.controlled > 0 {
            if run.fight.controlled < 99 { run.fight.controlled -= 1 }
            let selfHit = e.atk.upperBound
            e.hp = max(0, e.hp - selfHit)
            run.enemy = e
            log.append("🔗 Under your control, \(e.name) strikes itself for \(selfHit)!")
            return true
        }
        return false
    }

    /// Spells that change a hit landing on you. Returns the damage you take.
    static func incoming(_ run: inout Run, _ taken: Int, log: inout [String]) -> Int {
        var t = taken
        if run.fight.phantom > 0 && t > 0 {
            run.fight.phantom -= 1
            log.append("👻 The hit passes straight through you!")
            return 0
        }
        if run.fight.fireballReturn > 0 {
            let back = run.defending ? run.fight.fireballReturn / 2 : run.fight.fireballReturn
            log.append(run.defending ? "🛡️ You brace — the returning fireball hits for \(back)." : "🔥 Your fireball comes back and hits you for \(back)!")
            t += back
            run.fight.fireballReturn = 0
        }
        if run.legendShield { t = max(1, jsRound(Double(t) * 0.70)) }
        if run.fight.voidMirror > 0 && t > 0 {
            let heal = t / 2
            run.hp = min(run.maxHp, run.hp + heal)
            log.append("🖤 Void Mirror turns the blow — you heal \(heal) instead.")
            return 0
        }
        if run.fight.curseEchoes > 0, t > 0, var e = run.enemy {
            let back = max(1, jsRound(Double(t) * 0.3))
            e.hp = max(0, e.hp - back)
            run.enemy = e
            log.append("👁️ The Curse of Echoes rebounds — \(e.name) takes \(back)!")
        }
        return t
    }

    /// Each turn: burning, the Grave Pact running out, the Hunger's drain.
    static func tickFight(_ run: inout Run, log: inout [String]) {
        if run.fight.playerBurnTurns > 0 && run.hp > 0 {
            run.fight.playerBurnTurns -= 1
            run.hp = max(0, run.hp - run.fight.playerBurn)
            log.append("🔥 Agony burns you for \(run.fight.playerBurn) damage!")
        }
        if run.fight.gravePact > 0 {
            run.fight.gravePact -= 1
            if run.hp <= 0 { run.hp = 1; log.append("⚰️ The Grave Pact refuses your death.") }
            if run.fight.gravePact == 0 {
                run.hp = max(run.hp, run.fight.gravePactHp)
                log.append("⚰️ The Grave Pact ends. HP restored to \(run.hp).")
            }
        }
        // Intangibility fades after 2 turns even if nothing swung at you.
        if run.fight.phantom > 0 { run.fight.phantom -= 1 }
        if run.fight.voidMirror > 0 { run.fight.voidMirror -= 1 }
        if run.fight.curseEchoes > 0 { run.fight.curseEchoes -= 1 }
        if run.hungerDrain > 0 && run.hp > 0 {
            run.hungerDrain -= 1
            run.hp = max(1, run.hp - 15)
            log.append("🖤 The Hunger feeds on you — 15 HP.")
        }
    }

    /// On a kill: the Hunger, the Soul Leash, Lose Reality's reward.
    static func onKill(_ run: inout Run, _ e: Enemy, dice: inout some Dice, log: inout [String]) {
        if run.hungerKills > 0 {
            run.hungerKills -= 1
            run.hp = min(run.maxHp, run.hp + 15)
            log.append("🖤 The Hunger feeds — you heal 15 HP." + (run.hungerKills == 0 ? " It is not satisfied. It turns on you." : ""))
            if run.hungerKills == 0 { run.hungerDrain = 3 }
        }
        if run.fight.soulLeash {
            let heal = e.maxHp / 2
            run.hp = min(run.maxHp, run.hp + heal)
            log.append("🔗 The Soul Leash pulls \(heal) HP from \(e.name)'s soul into yours.")
        }
        if run.fight.loseRealityUntil > 0 {
            run.fight.loseRealityUntil = 0
            run.gold += 300
            let pool = scrolls.filter { $0.rarity != "legendary" }
            let s = pool[dice.roll(0...(pool.count - 1))]
            run.inventory.append(scrollItem(s))
            log.append("🌀 Reality holds. You won the race against your own unmaking: 300 gold and \(s.name)!")
        }
    }

    /// Firelord: the next enemy walks into the burning ground.
    static func combatStart(_ run: inout Run, log: inout [String]) {
        guard run.burningGround, var e = run.enemy else { return }
        run.burningGround = false
        e.hp = max(1, e.hp - 25)
        run.enemy = e
        log.append("🔥 \(e.name) steps onto burning ground and takes 25 damage!")
    }
}
