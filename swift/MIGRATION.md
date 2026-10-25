# Dungeon Descent: Swift rewrite

The web version (`www/index.html`, ~66,000 lines) keeps running on TestFlight
until the Swift version can replace it. Nothing in `www/` or `ios/` changes on
the way there.

## How it's built

```
swift/
  DungeonCore/      Game rules only, no screens. Builds and tests on any machine.
  App/              (next) SwiftUI app that uses DungeonCore.
```

- **DungeonCore** copies the web version's numbers exactly. JavaScript rounding
  and number parsing are reproduced (`jsRound`, `jsParseInt`), and the tests check
  hand-worked results from the web formulas.
- **Saves are compatible.** Storage uses the same `dd_*` keys and value formats as
  DDStore. Character fields Swift doesn't use yet are kept and written back
  unchanged, so a web save loads in Swift without losing anything.
- **Randomness goes through `Dice`,** so tests can replay a fight exactly.

Run the tests: `cd swift/DungeonCore && swift test`

## Order of work

1. **Core rules** (in progress): characters, wallet, enemies, basic combat.
2. **App shell:** SwiftUI project, main menu, character list and creation, settings,
   support. VoiceOver labels and announcements built in from day one.
3. **Playable Crypt run:** rooms, search, loot, inventory, shop, leveling, lives
   and death, boss phases, victory. First TestFlight build of the Swift app.
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
| Classes, races, professions, difficulties | CHARACTER CREATION | 🟡 stats and lists only; race bonuses not applied yet |
| Run start stats | initDungeon | 🟡 equipment, coin upgrades, milestone buffs, dream buffs, spirits not yet |
| Crypt enemies and bosses, scaling | DUNGEON ENGINE | ✅ |
| Other dungeons' enemy tables | DUNGEON ENGINE | ⬜ |
| Attack / heavy / defend / enemy counter | doFight | 🟡 base rules only |
| Skills, potions, weapon and armor effects | doFight, CLASS SKILLS | ⬜ |
| Lives, death, revive | handleDeath | ⬜ |
| Rooms, search, floors, shop | enterRoom, searchRoom, openShop | ⬜ |
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
| Music player, narrator, sound effects | MUSIC PLAYER … | ⬜ |
| 3D Mode | Three.js | ⬜ |

## Things to keep in mind

- **Web bug found:** Mercenary is supposed to start with 15 gold, but `initDungeon`
  replaces it with the wallet balance right after, so the bonus never reaches the
  player. Swift keeps that behavior for now (see `Run.swift`); decide whether to fix it.
- Android has its own HTML copy, so no Android code is needed here.
