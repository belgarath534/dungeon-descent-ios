# Dungeon Descent: Swift rewrite

The game is being rewritten from the web version (`www/index.html`, ~66,000
lines) into Swift, one system at a time. The Swift app ships to TestFlight under
the same app ID; `www/` and `ios/` stay untouched as the reference and fallback.

## How it's built

```
swift/
  DungeonCore/      Game rules only, no screens. Builds and tests on any machine.
  App/              SwiftUI app that uses DungeonCore. project.yml is turned into
                    an Xcode project by XcodeGen on Codemagic.
```

**TestFlight:** run the "Dungeon Descent Swift (TestFlight)" workflow in Codemagic.
It uses the same bundle ID (com.dungeon.descent), so it replaces the web version
on TestFlight. To go back, run the old "Dungeon Descent App Store" workflow, but
its build number has to be higher than the Swift build's first.

**Your web-version saves** live in the app's WebKit storage. The Swift app doesn't
read or delete them yet; importing them is on the list below.

- **DungeonCore** copies the web version's numbers exactly. JavaScript rounding
  and number parsing are reproduced (`jsRound`, `jsParseInt`), and the tests check
  hand-worked results from the web formulas.
- **Saves are compatible.** Storage uses the same `dd_*` keys and value formats as
  DDStore. Character fields Swift doesn't use yet are kept and written back
  unchanged, so a web save loads in Swift without losing anything.
- **Randomness goes through `Dice`,** so tests can replay a fight exactly.

- **Game data comes straight from the web code.** `node swift/tools/extract-game-data.js`
  copies every dungeon's enemies, bosses, loot, shop stock, traps, room text and
  floor names into `DungeonCore/Sources/DungeonCore/Resources/gamedata.json`. Run it
  again whenever those tables change in `www/index.html`.

Run the tests: `cd swift/DungeonCore && swift test`

**Every push to `swift-rewrite` builds the iPhone app on GitHub Actions**
(`.github/workflows/swift-build.yml`): tests, then an unsigned Release build. A red
build there means the app doesn't compile; the log says why.

## Order of work

1. ✅ **Core rules:** characters, wallet, enemies, basic combat, XP, lives.
2. ✅ **App shell:** main menu, character list and creation, settings, support.
   VoiceOver labels and announcements built in from day one.
3. ✅ **Playable runs in all 8 dungeons:** fights, flee, room odds and descriptions,
   loot rooms, searching and traps, potions, runes, scrolls, weapons and armor, the
   shop after every floor, descend or wander, leveling, lives and Phoenix Feathers,
   boss phases, victory and defeat. Runs are saved after every action and can be
   continued. Class skills: all 358, learned at level-ups.
   Next: special room events, elites, enemy abilities, weapon rarities.
   Then import web saves.
4. **Native services:** Sign in with Apple / Google through the Firebase iOS SDK,
   cloud save, StoreKit 2 purchases, Game Center, Core Haptics, audio, Live Activity,
   Magic Tap, iCloud backup.
5. **Remaining dungeons and modes,** one at a time.
6. **3D Mode** (SceneKit or RealityKit) last.

## System checklist

Status: ✅ ported · 🟡 partly ported · ⬜ not started

| System | Web section | Status |
|---|---|---|
| Storage (DDStore keys) | CHARACTER STORAGE | 🟡 key/value store and file store done; iCloud sync not yet |
| Gold and diamonds | GLOBAL GOLD SYSTEM | ✅ |
| Character list, 5 slots, save format | CHARACTER STORAGE | ✅ |
| Dungeon unlocks | getUnlockedDungeons | ✅ |
| Classes, races, professions, difficulties | CHARACTER CREATION | 🟡 Halfling, Goblin, Warden, Herbalist, Gravedigger, Pilgrim, Mercenary, Grave Robber done; other races not yet |
| Run start stats | initDungeon | 🟡 equipment, coin upgrades, milestone buffs, dream buffs, spirits not yet |
| Crypt enemies and bosses, scaling | DUNGEON ENGINE | ✅ |
| Other dungeons' enemy tables | DUNGEON ENGINE | ✅ from gamedata.json, including Nightmare enemies |
| Enemy special abilities (burn, dodge, lifesteal …) | ENEMY_SPECIALS, enemy flags | ⬜ kept in the data, not acted on yet |
| Room descriptions, floor names | ROOM_DESCS, FLOOR_NAMES | ✅ |
| Attack / heavy / defend / enemy counter | doFight | 🟡 base rules only |
| Potions, runes, scrolls, Phoenix Feather | useItem | ✅ except the shop's more exotic brews (soul trap, mirror flask, rage tonic …) |
| Weapons and armor, equipping | equipWeapon, equipArmor | 🟡 stats and equipping; rarity effects not yet |
| Class skills, SP | CLASS SKILLS, useSkill | ✅ all 358 skills of all 24 classes, skill choice at each level-up |
| Lives, death, revive | handleDeath | 🟡 lives, 40% revive, Phoenix Feather, death log; hardcore and class cheat-deaths not yet |
| XP, levels, level points | gainXP, LP_STATS | ✅ |
| Kill gold | enemyDead | 🟡 base gold, Goblin, Grave Robber, luck |
| Rooms, search, floors, shop | enterRoom, searchRoom, openShop | 🟡 all but special room events and NPC encounters |
| Saving a run in progress | midRunSave | ✅ (Swift's own format) |
| Import web saves into the Swift app | DDStore (IndexedDB) | ⬜ |
| Elites, multi-enemy combat | MULTI-ENEMY COMBAT SYSTEM | ⬜ |
| Gun crafting | GUN DEFINITIONS | ⬜ |
| Raids, Boss Rush, Daily Challenge, Tournament | RAID ENGINE, BOSS RUSH ENGINE … | ⬜ |
| Quests, bounties, inbox, achievements, stats | QUEST SYSTEM, BOUNTY BOARD … | ⬜ |
| Spirits, companion, corruption, Hunter, Void, Medusa arc | … | ⬜ |
| Seasonal events | SEASONAL EVENTS SYSTEM | ⬜ |
| Home system | HOME SYSTEM | ⬜ |
| Global chat, presence, leaderboards | GLOBAL CHAT SYSTEM … | ⬜ |
| Account login, cloud save | DD Cloud | ⬜ |
| Translations (Portuguese etc.) | translation tables | ⬜ |
| Music, ambience, sound effects | playTrack, playAmbient, sfx | ✅ same files (www/audio, bundled as-is), same track per dungeon and floor, volume settings |
| Music player, custom tracks, narrator | MUSIC PLAYER … | ⬜ |
| 3D Mode | Three.js | ⬜ |

## Things to keep in mind

- **Web bug found:** Mercenary is supposed to start with 15 gold, but `initDungeon`
  replaces it with the wallet balance right after, so the bonus never reaches the
  player. Swift keeps that behavior for now (see `Run.swift`); decide whether to fix it.
- Android has its own HTML copy, so no Android code is needed here.

## Web bugs fixed in the Swift version

Where an item's description and the web code disagree, Swift follows the description:

- **Attack and defense potions** say "+N for 3 turns" but the web version gave +4/+3
  for the whole run (and the loot table's Defense Potion used a field nothing read).
  Swift gives the described bonus for 3 turns.
- **Curse Potion** says "for 3 turns" but never wore off. It now lasts 3 turns.
- **Lucky Potion** did nothing in normal fights (only multi-enemy fights read it).
  It now doubles gold from the next 3 kills.
- **Poison Dart trap** promised 8 damage a turn for 3 turns but never ticked. It now does.
- **Scroll of Mending** was used up when read during a fight, without healing. It's
  now kept until you're out of combat.
- **Weapon attack bonus** differed between equipping mid-run (low end of the range)
  and starting a run (middle of the range). Swift always uses the middle.
- **105 of the 333 skill effects did nothing** in the web version: no handler existed,
  so they cost SP, dealt no damage and gave the enemy a free hit. This includes every
  skill of the Elementalist, Void Walker, Shadow Mage, Time Mage, Shaman and Arcanist,
  most of the Wizard's, the Ranger's Aimed Shot and the Death Knight's legendaries. In
  Swift every skill does what its description says (`SkillTable` in `Skills.swift`).
- **Starting skills:** the Sorcerer's was set to Fireball (an Elementalist skill) and the
  Sentinel's to a skill that doesn't exist, so they started with none; 12 classes had no
  starting skill at all. Every class now starts with one.
- **Skill buffs described as "this combat" or "for N turns"** (Shield Bash, Iron
  Stance, Rage, Beast Form …) were added to your stats for the rest of the run, so they
  stacked without limit. They now last for the fight or the turns described.
- **Shared skill names:** several classes share an effect name with different
  descriptions (Bone Shield, Taunt, Arcane Bolt …) and the web version ran the same code
  for all of them. Each class now gets its own version.

