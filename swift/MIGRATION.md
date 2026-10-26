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

**Your web-version saves** live in the app's WebKit storage. On first launch the Swift
app looks for them (a hidden web view opens the same IndexedDB at capacitor://localhost)
and offers to import them; Settings can do it again later. The web data is only read,
never changed, so going back to the web version keeps working.

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
   continued. Class skills: all 358, learned at level-ups. Elites, enemy abilities,
   special rooms and dungeon events. Weapon and armor rarities. Achievements,
   trophies and Game Center. Hardcore, Continue Journey and New Game+. Daily quests.
   Next: bounties, daily challenge, boss rush, raids.
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
| Run start stats | initDungeon | 🟡 equipment, coin upgrades and milestone buffs done; dream buffs and spirits not yet |
| High Score | HIGH SCORE SYSTEM, renderHighScore, uploadToLeaderboard, renderLeaderboardTab, loadInbox | ✅ score (dd_score), ranks and the category breakdown, earned for kills, elites, bosses, achievements, Boss Rush and Endless milestones. Upload to the shared global leaderboard (top 20, the web version's "leaderboard" collection), the weekly champion's 3 Mystery Coins, and the developer inbox with coin claims. Web bug fixed: the inbox's message list had been deleted, so a non-empty inbox stayed on "Loading inbox..." forever |
| Endless milestones | advanceFloor | ✅ every 25 floors a full heal and +5 max HP, every 10 floors a 30% heal |
| Obituary | loadObituary, postDeathToObituary | ✅ the 15 newest deaths worldwide from the shared "deaths" list, with this device's Graveyard when offline. Dungeon, Daily Raid and Boss Rush deaths are posted like the web version |
| Account and cloud save | ACCOUNT SYSTEM — BETA, syncToCloud, loadFromCloud, _fbDeleteAccount | ✅ Settings → Account: email sign in and sign up, Google, Apple, forgot password, sync, load, sign out and delete account. Same Firebase project, same "dungeon-descent" Firestore database and the same saves/{uid} document as the web version, so one account and one save work in both. The quiet sync runs when the app goes to the background, at most every 2 minutes. Change from the web version: when both this device and the cloud have a save, it asks which to keep instead of replacing this device's save. Username can be set in Account (reserved in "usernames" like the web version); the title picker isn't ported yet |
| Endless Descent (AFK) | ENDLESS DESCENT — AFK MODE, AFK_SHOP_ITEMS, AFK_DAILY_CHALLENGES | ✅ setup, the automatic fight every 15 seconds, class passives, Endless-only enemies, boss floors, loot, levels to 10, the skill pick, summary, Descent Shop and daily challenge. New in Swift: the run keeps going after you leave the app. With music on, the app keeps fighting in the background; otherwise the fights it missed are fought when you come back. The run is saved after every fight, and a Live Activity (same DDLiveActivity extension and bundle ID as the web version) shows the floor, HP, points, level, potions and a countdown on the Lock Screen and in the Dynamic Island, alerting on bosses, level-ups and the end. Web bugs fixed: killing The Endless Knight ended your run (it now rises once and the fight goes on), and the Warlock and Wizard damage surges never added any damage |
| The Chronicles | chr-lore, STORIES, VOID_CHRONICLES, renderJournal, renderMusicPlayer | ✅ Lore, Library (stories, Void Chronicles by fragments found, hidden Spire and Julio stories, narration streamed from the web version's audio host), the character journal and the Music Player. Custom "My Tracks" aren't ported. The web version never wrote dd_stories_read, so the Codex's DDDI entry could never unlock; it now also unlocks after reading 3 stories |
| Character journal | addJournalEntry, logDeath | ✅ run start, every 5 kills, boss kills, each new floor and every lost life, saved to the character like the web version |
| The Codex | CODEX_WORLD, CODEX_ENEMY, CODEX_ARTIFACTS | ✅ all 14 entries with the web version's unlock rules (Mine, Spire, Chronicles and Void entries unlock once those modes are ported) |
| Mystery Coin Shop | COIN_UPGRADES, applyCoinUpgrades | ✅ all 26 upgrades. The Android-only Watch Ad box and the in-app coin purchases are left out. Ancient Knowledge (+15% XP) now works; the web version sold it and never applied it. Treasure Sense's gem is turned into gold right away, the way Swift handles every gem. When Death's Bargain kills the enemy, the kill counts for the bestiary and achievements; the web version left you alive at 0 HP. Bloodhound's Nose and Trapper's Kit do nothing until equipment drops and the Soul Trap are ported |
| Crypt enemies and bosses, scaling | DUNGEON ENGINE | ✅ |
| Other dungeons' enemy tables | DUNGEON ENGINE | ✅ from gamedata.json, including Nightmare enemies |
| Enemy special abilities (burn, dodge, lifesteal …) | ENEMY_SPECIALS, enemy flags | ✅ all 176 named special moves and the common ability flags; the one-off Hollow and Shadow World mechanics not yet |
| Room descriptions, floor names | ROOM_DESCS, FLOOR_NAMES | ✅ |
| Attack / heavy / defend / enemy counter | doFight | 🟡 base rules only |
| Potions, runes, scrolls, Phoenix Feather | useItem | ✅ except the shop's more exotic brews (soul trap, mirror flask, rage tonic …) |
| Weapons and armor, equipping | equipWeapon, equipArmor | ✅ |
| Weapon and armor rarities | WEAPON_RARITIES, RARITY_EFFECTS | ✅ six tiers, all 24 effects |
| Class skills, SP | CLASS SKILLS, useSkill | ✅ all 358 skills of all 24 classes, skill choice at each level-up |
| Lives, death, revive | handleDeath | ✅ lives, 40% revive, Phoenix Feather, resurrection skills, gear saves, hardcore, death log |
| XP, levels, level points | gainXP, LP_STATS | ✅ |
| Kill gold | enemyDead | 🟡 base gold, Goblin, Grave Robber, luck |
| Rooms, search, floors, shop | enterRoom, searchRoom, openShop | 🟡 all but special room events and NPC encounters |
| Saving a run in progress | midRunSave | ✅ (Swift's own format) |
| Import web saves into the Swift app | DDStore (IndexedDB) | ✅ offered on first launch and in Settings (WebSaveImporter) |
| Elites | ELITE_ENEMIES | ✅ 15% from floor 4, every dungeon and Nightmare |
| Special rooms (treasure, sanctuary, cursed, hidden, merchant) | SPECIAL_ROOMS | ✅ |
| Dungeon events (shrine, chest, Julio, wounded adventurer, Abyssal events …) | DUNGEON_EVENTS | ✅ 9 of 16 (the Shadow World ones and The Witness not yet) |
| Multi-enemy combat | MULTI-ENEMY COMBAT SYSTEM | ⬜ |
| Gun crafting | GUN DEFINITIONS | ⬜ |
| Boss Rush | BOSS RUSH ENGINE | ✅ with the personal leaderboard |
| Daily Raid | RAID ENGINE | ✅ Normal and Hard, raid tiers, once a day. Skills without a raid rule now hit for normal damage (the web version charged SP and did nothing) |
| Daily Challenge, Tournament | DAILY_CHALLENGES, tournament | ⬜ |
| Achievements, trophies, Game Center | ACHIEVEMENTS, awardAchievement | ✅ all 115, same save keys and Game Center IDs |
| Lifetime stats, Hall of Records | GLOBAL STATS TRACKING, GLOBAL_AWARDS, Hall of Legends | ✅ all the web's tracked stats, milestone awards (Mystery Coins and permanent effects), records and first clears |
| Bestiary | BESTIARY_DATA, recordKill, BESTIARY_MILESTONES | ✅ 434 entries with filters, search and kill milestones; Spirits and Community tabs not yet |
| Hardcore, Continue Journey, New Game+ | handleHardcoreDeath, continueJourney, startNGPlus | ✅ |
| Legacy run mode | Legacy Mode | ⬜ |
| Floor 10 Elite Guardian before the boss, 35% heal on each descent | startEliteGauntlet, advanceFloor | ✅ |
| Dungeon screen in the web version's look | screen-dungeon, ov-shop, ov-levelup, skill-choice-overlay, stats-overlay, death-cinematic, screen-runsummary | ✅ top bar, daily quest, XP/SP, room tracker, room and event box, compass, combat, inventory tabs and favorites, shop, level up then skill choice, floor complete, flee, pause, run log, death cinematic, run summary. Not yet: Voice, Echo-locate, Blacksmith, Arcane Shop, Spell Book, Home, chat, selling |
| Death: graveyard entry, gear kept, Classic level reset | showDefeat | ✅ |
| Settings in the web version's look | settings-screen, settings-panel-* | ✅ categories; Audio, Accessibility (verbose rooms, combat announcements, repair unlocks), Gameplay (class traits), General (version, web save import), Account. Language, Chat, Notifications, Beta, Developer Tools not yet |
| The Graveyard, Help, Credits, What's New | screen-graveyard, screen-help, screen-credits, screen-whatsnew | ✅ text from index.html through tools/extract-static-screens.py |
| Quests & Achievements screen | screen-quests | ✅ main and daily quest, achievements with Load More; Daily Challenge not yet |
| Web look: main menu, Your Champions, Death Log, Forge Your Legend | screen-menu, screen-charlist, screen-deathlog, screen-creation | ✅ same order, text, VoiceOver labels and sliders; creation cards come from index.html through tools/extract-creation.py |
| The Shadow World dungeon | SHADOW_ENEMIES | ⬜ |
| Spirits, corruption, hunter, guide in play | STARTER_SPIRITS, corruption, hunterTurn, companion | ⬜ chosen at creation and saved, no effect in runs yet |
| Daily quests | DAILY_QUESTS, updateDailyQuestProgress | ✅ 15 of 17 (the rare spirit and lore fragment days move to the next quest until those systems are ported); shown on the main menu and at run start |
| Quests, bounties, inbox | QUEST SYSTEM, BOUNTY BOARD … | ⬜ |
| Spirits, companion, corruption, Hunter, Void, Medusa arc | … | ⬜ |
| Seasonal events | SEASONAL EVENTS SYSTEM | ⬜ |
| Home system | HOME SYSTEM | ⬜ |
| Global chat, presence, leaderboards | GLOBAL CHAT SYSTEM … | ⬜ |
| Account login, cloud save | DD Cloud | ✅ see "Account and cloud save" |
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
- **Cursed Chamber** looked up its enemy in the wrong kind of table, so it never
  spawned the cursed enemy (outside the Shadow World) and just rolled an ordinary room.
  It now spawns a stronger enemy with triple gold, as described.
- **Ashbound enemy abilities** (Cinder Hound and Ember Knight burning you, Smoke Wraith
  phasing out every third turn) were in the data and descriptions but nothing applied
  them. They now work.
- **Kill counts** went up by 2 per kill (incrementAchievementStat ran twice in enemyDead),
  so kill achievements unlocked at half the kills they promise. Swift counts 1.
- **Origins (backstories) never applied their bonus.** `applyBackstory()` ran at
  creation and changed the *previous* run's state, so +15 gold, +10 HP, +2 defense,
  +1 life and so on never reached the new character. "Last Hope" also promised
  +5 SP per level up that no code ever gave. The Swift version applies them when
  each run starts.
- **Most permanent milestone rewards never applied.** Bestiary milestones and Hall of
  Records awards store effects, but `applyMilestoneBuffs()` only handles the extra HP,
  defense and SP ones; "+2 Attack forever", "Second Wind free", "+1 defense vs undead",
  "potions heal 10% more" and the rest do nothing, and "+10 Max HP forever" gives +5.
  The Swift version currently matches the web version here; fix later.

