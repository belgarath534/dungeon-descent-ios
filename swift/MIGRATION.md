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

Run the tests: `cd swift/DungeonCore && swift test`

## Order of work

1. ✅ **Core rules:** characters, wallet, enemies, basic combat, XP, lives.
2. ✅ **App shell:** main menu, character list and creation, settings, support.
   VoiceOver labels and announcements built in from day one.
3. 🟡 **Playable Crypt run:** fights, room odds, leveling, lives, boss phases and
   victory work. Next: loot, potions, inventory, search, shop, room events.
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
| Other dungeons' enemy tables | DUNGEON ENGINE | ⬜ |
| Attack / heavy / defend / enemy counter | doFight | 🟡 base rules only |
| Skills, potions, weapon and armor effects | doFight, CLASS SKILLS | ⬜ |
| Lives, death, revive | handleDeath | 🟡 lives and 40% revive; cheat-death items and hardcore not yet |
| XP, levels, level points | gainXP, LP_STATS | ✅ |
| Kill gold | enemyDead | 🟡 base gold, Goblin, Grave Robber, luck |
| Rooms, search, floors, shop | enterRoom, searchRoom, openShop | 🟡 room odds and floors; loot, events, search, shop not yet |
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
| Music player, narrator, sound effects | MUSIC PLAYER … | ⬜ |
| 3D Mode | Three.js | ⬜ |

## Things to keep in mind

- **Web bug found:** Mercenary is supposed to start with 15 gold, but `initDungeon`
  replaces it with the wallet balance right after, so the bonus never reaches the
  player. Swift keeps that behavior for now (see `Run.swift`); decide whether to fix it.
- Android has its own HTML copy, so no Android code is needed here.
