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
   trophies and Game Center. Hardcore, Continue Journey and New Game+. Daily quests,
   bounties, Daily Challenge, Daily Descent, Boss Rush and raids.
4. **Native services:** Sign in with Apple / Google through the Firebase iOS SDK,
   cloud save, StoreKit 2 purchases, Game Center, Core Haptics, audio, Live Activity,
   Magic Tap, iCloud backup.
5. **Remaining dungeons and modes,** one at a time.
6. **3D Mode** (SceneKit or RealityKit) last.

## System checklist

Status: ✅ ported · 🟡 partly ported · ⬜ not started

| System | Web section | Status |
|---|---|---|
| Storage (DDStore keys) | CHARACTER STORAGE | ✅ key/value store and file store |
| iCloud Backup | iCloudSyncPlugin, syncToiCloud, loadFromiCloud | ✅ Settings → Account: the on/off switch (dd_icloud_backup_enabled), automatic backup when the app goes to the background (at most every 2 minutes), Back Up Now and Restore. Same CloudKit container and record as the old app, so its backups restore here |
| Gold and diamonds | GLOBAL GOLD SYSTEM | ✅ |
| Character list, 5 slots, save format | CHARACTER STORAGE | ✅ |
| Dungeon unlocks | getUnlockedDungeons | ✅ |
| Classes, races, professions, difficulties | CHARACTER CREATION, initDungeon's race bonuses, getShopDiscount | 🟡 all 15 races (`Races.swift`): every race card's stat line and ability. All 11 professions: Blacksmith, Herbalist, Scholar, Mercenary, Gravedigger, Thief, Pilgrim, Grave Robber, Street Rat (Smoke Bomb for any class, +20% flee), Warden (+3 defense, the first debuff each floor slides off) and Tinkerer (2 Health Potions, skills cost 2 less SP) |
| Run start stats | initDungeon | ✅ equipment, coin upgrades, milestone buffs, dream buffs, spirits, Legacy levels and profession bonuses |
| High Score | HIGH SCORE SYSTEM, renderHighScore, uploadToLeaderboard, renderLeaderboardTab, loadInbox | ✅ score (dd_score), ranks and the category breakdown, earned for kills, elites, bosses, achievements, Boss Rush and Endless milestones. Upload to the shared global leaderboard (top 20, the web version's "leaderboard" collection), the weekly champion's 3 Mystery Coins, and the developer inbox with coin claims. Web bug fixed: the inbox's message list had been deleted, so a non-empty inbox stayed on "Loading inbox..." forever |
| Endless milestones | advanceFloor | ✅ every 25 floors a full heal and +5 max HP, every 10 floors a 30% heal |
| Global Chat | GLOBAL CHAT SYSTEM, ugcReport, ugcBlock | ✅ the shared "global_chat" room, live, with the chat username, 200-character limit, word filter, the one-time Terms agreement, Report (sent to the developer and hidden) and Block on every message, and Settings → Chat to change the username or unblock everyone. New messages from others are read out by VoiceOver. Web bug fixed: the word filter matched inside words, so messages with "class", "pass" or "assassin" were refused. Settings → Chat → Show Chat in Dungeon adds the 💬 button in the dungeon |
| Obituary | loadObituary, postDeathToObituary | ✅ the 15 newest deaths worldwide from the shared "deaths" list, with this device's Graveyard when offline. Dungeon, Daily Raid and Boss Rush deaths are posted like the web version |
| Account and cloud save | ACCOUNT SYSTEM — BETA, syncToCloud, loadFromCloud, _fbDeleteAccount | ✅ Settings → Account: email sign in and sign up, Google, Apple, forgot password, sync, load, sign out and delete account. Same Firebase project, same "dungeon-descent" Firestore database and the same saves/{uid} document as the web version, so one account and one save work in both. The quiet sync runs when the app goes to the background, at most every 2 minutes. Change from the web version: when both this device and the cloud have a save, it asks which to keep instead of replacing this device's save. Username can be set in Account (reserved in "usernames" like the web version), and the title in Change Title |
| Endless Descent (AFK) | ENDLESS DESCENT — AFK MODE, AFK_SHOP_ITEMS, AFK_DAILY_CHALLENGES | ✅ setup, the automatic fight every 15 seconds, class passives, Endless-only enemies, boss floors, loot, levels to 10, the skill pick, summary, Descent Shop and daily challenge. New in Swift: the run keeps going after you leave the app. With music on, the app keeps fighting in the background; otherwise the fights it missed are fought when you come back. The run is saved after every fight, and a Live Activity (same DDLiveActivity extension and bundle ID as the web version) shows the floor, HP, points, level, potions and a countdown on the Lock Screen and in the Dynamic Island, alerting on bosses, level-ups and the end. Web bugs fixed: killing The Endless Knight ended your run (it now rises once and the fight goes on), and the Warlock and Wizard damage surges never added any damage |
| The Chronicles | chr-lore, STORIES, VOID_CHRONICLES, renderJournal, renderMusicPlayer | ✅ Lore, Library (stories, Void Chronicles by fragments found, hidden Spire and Julio stories, narration streamed from the web version's audio host), the character journal and the Music Player. Custom "My Tracks" aren't ported. The web version never wrote dd_stories_read, so the Codex's DDDI entry could never unlock; it now also unlocks after reading 3 stories |
| Character journal | addJournalEntry, logDeath | ✅ run start, every 5 kills, boss kills, each new floor and every lost life, saved to the character like the web version |
| The Codex | CODEX_WORLD, CODEX_ENEMY, CODEX_ARTIFACTS | ✅ all 14 entries with the web version's unlock rules (Mine, Spire, Chronicles and Void entries unlock once those modes are ported) |
| Equipment drops | checkEquipmentDrop, rollEquipmentDrop | ✅ 15% of kills (20% with Bloodhound's Nose) drop a sword, mace, axe, dagger, staff, bow or light/medium/heavy armor, a level higher every 3 floors, with a rolled rarity |
| Selling items | renderShopSell, getSellPrice | ✅ the Wandering Merchant's Sell Your Items section, counting toward the selling achievements |
| Mystery Coin Shop | COIN_UPGRADES, applyCoinUpgrades | ✅ all 26 upgrades. The Android-only Watch Ad box and the in-app coin purchases are left out. Ancient Knowledge (+15% XP) now works; the web version sold it and never applied it. Treasure Sense's gem is turned into gold right away, the way Swift handles every gem. When Death's Bargain kills the enemy, the kill counts for the bestiary and achievements; the web version left you alive at 0 HP. |
| Crypt enemies and bosses, scaling | DUNGEON ENGINE | ✅ |
| Other dungeons' enemy tables | DUNGEON ENGINE | ✅ from gamedata.json, including Nightmare enemies |
| Enemy special abilities (burn, dodge, lifesteal …) | ENEMY_SPECIALS, enemy flags | ✅ all 176 named special moves and the common ability flags; the one-off Hollow and Shadow World mechanics not yet |
| Room descriptions, floor names | ROOM_DESCS, FLOOR_NAMES | ✅ |
| Attack / heavy / defend / enemy counter | doFight | 🟡 base rules only |
| Class traits | CLASS_TRAITS, applyClassTraits, applyTraitPerFloor, applyTraitOnKill, and the class checks in initDungeon, doFight, enemyTurn, enemyDead and handleDeath | ✅ all 24 classes (`ClassTraits.swift`), announced when the run starts and following Settings → Gameplay → Class Traits. Both of the web version's layers apply: the announced trait and the older class bonuses in the fight code (Assassin's instant kill, Warlock's Dark Pact, Wizard's Arcane Surge, Bard's charm, Monk's dodge, the mage classes' smaller HP …). The trait descriptions now list everything a class does |
| Potions, runes, scrolls, Phoenix Feather | useItem | ✅ except the shop's more exotic brews (soul trap, mirror flask, rage tonic …) |
| Weapons and armor, equipping | equipWeapon, equipArmor | ✅ |
| Weapon and armor rarities | WEAPON_RARITIES, RARITY_EFFECTS | ✅ six tiers, all 24 effects |
| Class skills, SP | CLASS SKILLS, useSkill | ✅ all 358 skills of all 24 classes, skill choice at each level-up |
| Lives, death, revive | handleDeath | ✅ lives, 40% revive, Phoenix Feather, resurrection skills, gear saves, hardcore, death log |
| XP, levels, level points | gainXP, LP_STATS | ✅ |
| Kill gold | enemyDead | 🟡 base gold, Goblin, Grave Robber, luck |
| Rooms, search, floors, shop | enterRoom, searchRoom, openShop | ✅ |
| Saving a run in progress | midRunSave | ✅ (Swift's own format) |
| Import web saves into the Swift app | DDStore (IndexedDB) | ✅ offered on first launch and in Settings (WebSaveImporter) |
| Elites | ELITE_ENEMIES | ✅ 15% from floor 4, every dungeon and Nightmare |
| Special rooms (treasure, sanctuary, cursed, hidden, merchant) | SPECIAL_ROOMS | ✅ |
| Dungeon events (shrine, chest, Julio, wounded adventurer, Abyssal events …) | DUNGEON_EVENTS | ✅ all 16, including the six Shadow World ones and The Witness |
| Multi-enemy combat | MULTI-ENEMY COMBAT SYSTEM, startMultiCombat, spawnAmbush, spawnShadowAmbush | ✅ ambushes: 20% of fights from floor 3 (every fight on Ambush Day), two enemies or three from floor 7, each with a Target button; every enemy still standing strikes after your action, and each kill pays out as it falls. In The Shadow World, once you've killed two enemies, ambushes raise their echoes (75% HP, each hit adds corruption) |
| Guns | GUN_DEFS, GUN_PARTS_DEFS, gunAction, craftGunFromParts, buyGunWithDiamonds, renderHomeGunWorkshop, spireGunAction | ✅ all 13 guns. Home → Guns crafts them from parts; the Blacksmith's Guns tab sells them for diamonds; equip one and a 🔫 button appears in dungeon fights, the Mine and the Spire: Charge (free), shoot until the gun is empty, then it reloads for its seconds and says when it's ready. Gun parts drop from 8% of dungeon kills and come up in the Mine. Saved in dd_gun_parts, dd_owned_guns and dd_equipped_gun like the web version. The charge and shot sounds were embedded in index.html; they're now www/audio/sfx-gun-charge.mp3 and sfx-gun-shot.mp3. Raid and Siege guns wait for those modes' turn |
| Boss Rush | BOSS RUSH ENGINE | ✅ with the personal leaderboard |
| Daily Raid | RAID ENGINE | ✅ Normal and Hard, raid tiers, once a day. Skills without a raid rule now hit for normal damage (the web version charged SP and did nothing) |
| Hide and Seek | hsStart, hsMove, hsHide, the spatial growl, hs_rooms | ✅ single player and multiplayer (up to 5, the web version's hs_rooms layout and transactions, so Swift and web players share a house: shared hiding spots, rescuing caught teammates, the monster chasing whoever is nearest, joins, leaves, catches and escapes read out). The 7×7 house, the chase rules, the listening beat with its footstep, the explore and chase music, and the Darkness Swallower's growl panned left or right and louder as it closes in. The 3D view (for sighted watchers) isn't ported |
| PVP Arena (Multiplayer) | goToMultiplayer, mpCreateRoom, mpJoinRoom, mpAction, mpRematch | ✅ create or join a 4-character room, Ready, turn-based Attack/Heavy/Skill/Defend/Taunt, emotes, rematch and leaving, using the web version's pvp_rooms layout exactly so Swift and web players can fight each other. The opponent's moves are read out as they happen. Web bugs fixed: when your opponent left mid-battle you were told you lost (now you win); an opponent joining was announced as "wants a rematch"; skills could be used with 0 SP |
| Tournament | TOURNAMENT_BOSSES, getTournamentSeason, tnAttack | ✅ the first 7 days of January, April, July and October: the season's boss, Attack/Heavy/Defend with phases, damage plus speed and survival bonuses, 5 Mystery Coins for a kill, the season best (dd_tournament) and the shared season leaderboard. Web bugs fixed: the leaderboard stored and showed players' real email addresses (Swift stores the leaderboard name and hides old emails), and from October the countdown to the next tournament was negative |
| Daily Challenge | DAILY_CHALLENGES, registerForDC, applyDailyChallenge, checkDailyChallengeCompletion, renderDCPanel (dd_dc_reg, dd_dc, dd_dc_history) | ✅ Quests → ⚡ Challenge: today's challenge by the web version's formula, Register and Cancel, the warning, the reward and Recent Challenges. Registered runs get the modifier (all seven work: Iron Day, Glass Cannon, Cursed Day, Blessed Day, Nightmare Day, Speed Run, Horde Day), and clearing a dungeon pays 1 Mystery Coin once a day. The run log says today's challenge when you aren't registered |
| Achievements, trophies, Game Center | ACHIEVEMENTS, awardAchievement | ✅ all 115, same save keys and Game Center IDs |
| Lifetime stats, Hall of Records | GLOBAL STATS TRACKING, GLOBAL_AWARDS, Hall of Legends | ✅ all the web's tracked stats, milestone awards (Mystery Coins and permanent effects), records and first clears |
| Bestiary | BESTIARY_DATA, recordKill, BESTIARY_MILESTONES | ✅ 434 entries with filters, search and kill milestones; the Spirits tab (renderSpiritBestiary) by rarity with how to unlock each; the Community tab (renderCommunityBestiary) with every visible community enemy, its creator, stats and kills, and Report and Block on each |
| Community Enemy Creator | ecInit, ecRollStats, ecSubmit, getCommunityEnemy, communityEnemyToFightData, incrementCommunityKill (community_enemies in the "dungeon-descent" Firestore database) | ✅ name, description, type, dungeon, theme music and creator name, stats rolled by type with Reroll, the content check and the one-time Terms agreement, the World Builder achievement; the pool is shared with the web version, 12% of ordinary rooms bring one out ("A creature stirs — X, unleashed by Y.") with its theme music, kills are counted, and blocked creators and reported enemies never appear |
| Hardcore, Continue Journey, New Game+ | handleHardcoreDeath, continueJourney, startNGPlus | ✅ |
| Legacy run mode | Legacy Mode, applyTierScaling, saveCharPersistentLevel | ✅ the level (up to 25), XP and skills carry into the next run, with 3 level points a level to spend again; each clear raises the Dungeon Tier (+20% enemy HP, +10% attack, +15% gold a tier, bosses and the Elite Guardian too); death keeps the level and puts the tier back to 1 |
| Independence Tournament | JULY4_TOURNAMENT, startJuly4Tournament, checkJuly4TournamentEnd (dd_july4_tourney) | ✅ during the Fourth of July event: a personal target, 25 points a kill, first place pays 500 gold and 5 trophies, once a year |
| Fireworks Corner | openFireworksCorner | ✅ at Home on July 4th: 50 to 99 XP every 8 seconds, to your run |
| Floor 10 Elite Guardian before the boss, 35% heal on each descent | startEliteGauntlet, advanceFloor | ✅ |
| Command Center | openCommandCenter, executeCommand, ccHandleInput, startVoiceCommand, toggleCommandCenter (dd_command_center) | ✅ type or speak (iOS speech recognition) every web command: go to nine screens, start or schedule Endless Descent ("start afk at 11:30pm", while the app is open), cancel it, claim the Daily Descent, gold, stats, time, redeem codes (SHADOW too), play and stop music, help, and the six-step terminal character creator; quick-command buttons; Settings → Accessibility shows or hides it on the menu |
| Skill Orbs | homeCreateSkillOrbs, useSkillOrb (dd_skill_orbs) | ✅ when a character's run ends in death, every Home skill upgrade above level 1 becomes a class-locked orb and the upgrades start over; Home → Skill Upgrade lists the orbs, and a character of the same class uses one to take that skill to the orb's level |
| Shapeshifter's Mask | shadowItem shapeshifterMask | ✅ once a run, in a fight: copies the enemy's ability (12 of them) for the rest of the fight, or heals 30 HP |
| First-run tips | DUNGEON_TIPS, showDungeonTip (dd_dungeon_tips_seen) | ✅ the ten tips, each once, as a banner that drains away and read out after the move's own news |
| Pre-boss gauntlet | startPreBossGauntlet, spawnPreBossWave | ✅ after the Elite Guardian, 1 or 2 waves of the dungeon's toughest enemies (stronger on harder difficulties and NG+) before the boss chamber opens |
| Boss death cinematic | showBossDeathCinematic | ✅ the boss's last lines on black before victory |
| Drowned King's resurrection | enemy.resurrect | ✅ rises once at 1 HP |
| Item drops | ENCHANTER drop, spirit orb drop, July 4th firework | ✅ Enchanter 2.5% of searches and kills, Spirit Orb 5% of searches (a spirit you haven't earned), Mega Firework 15% of kills during the July 4th event |
| Dungeon screen in the web version's look | screen-dungeon, ov-shop, ov-levelup, skill-choice-overlay, stats-overlay, death-cinematic, screen-runsummary | ✅ top bar, daily quest, XP/SP, room tracker, room and event box, compass, combat, inventory tabs and favorites, shop, level up then skill choice, floor complete, flee, pause, run log, death cinematic, run summary. Echo-Location (3D Mode). Arcane Shop, Spell Book and Spells. Not yet: Voice, chat |
| Death: graveyard entry, gear kept, Classic level reset | showDefeat | ✅ |
| Settings in the web version's look | settings-screen, settings-panel-* | ✅ categories; Audio, Accessibility (verbose rooms, combat announcements, repair unlocks), Gameplay (class traits), General (version, web save import), Account. Beta Features (3D Mode) and 3D Settings. Language |
| The Graveyard, Help, Credits, What's New | screen-graveyard, screen-help, screen-credits, screen-whatsnew | ✅ text from index.html through tools/extract-static-screens.py |
| Quests & Achievements screen | screen-quests | ✅ main and daily quest, achievements with Load More, the Daily Challenge tab |
| Web look: main menu, Your Champions, Death Log, Forge Your Legend | screen-menu, screen-charlist, screen-deathlog, screen-creation | ✅ same order, text, VoiceOver labels and sliders; creation cards come from index.html through tools/extract-creation.py |
| The Shadow World dungeon | SHADOW_ENEMIES, addShadowCorruption, applyShadowEnemyMechanics, THE SHAPESHIFTER | ✅ dungeon 9, unlocked by finishing The Abyssal Deep: its 14 enemies and 3 elites with their moves (Mimic, Drifter, Null Fragment, Smear, Null Knight, Reflection, Sorrow Hound, Lurker, Void Weaver, Twice Dead, Shadow Archon, The Unborn, The Remnant; Hollow Echo, Null Sovereign, The Shapeless), Shadow Corruption and the Purge button, The Echo then the four-phase Shapeshifter, its floors, rooms, music and loot (Shadow Blade, Null Shield, Void Cloth, Shadow Cloak, Null Potion, Mirror Fragment, Echo Bone). The Stalker Floor: 10% of rooms from floor 3, a dark 5×5 room where the Darkness Swallower's growl pans to where it is and its footsteps follow you; reach an edge 3 times (150 gold and Shadow gear), get caught (35% of your HP), or turn and fight it when it's one step away. The Shadow events: The Mirror, The Voice, The Handwriting, The Offering, The Security Room (the growl plays in 3D from the Darkness Swallower's camera; the 15-second clock starts after its announcement) and The Two Doors, with the Offering Cloth and Door Key working. The Echo Staff repeats every damaging spell for half its damage |
| The Abyssal Deep's four-phase bosses and the rhythm sequence | checkBossPhase fourPhase, triggerRhythmGame, playRhythmBeats, rhythmTap, evaluateRhythm, rhythmResult | ✅ The Leviathan, the Leviathan Eye and the Abyssal Sovereign: phase 2 at 66% (+25% attack), phase 3 at 33% (+30%), phase 4 at 15% (+50%), each with its own music and line, shown as Phase N of 4. At phase 4 the abyss beats three times (a deep tone, 0.8 seconds apart) and you tap three times to match, within 0.42 seconds a gap, before 5 seconds run out: +40% attack and +30% defense for 2 turns, or the boss grows 30% stronger. Into The Abyss and In Perfect Time achievements |
| Spirits in play | STARTER_SPIRITS, RARE_SPIRITS, ELITE_SPIRITS, openPauseSpirits, awardRareSpirit | ✅ all 24 spirits fight, guard and loot beside you; rare ones wake at level 5. The spirit row under the top bar, switching in Pause → Spirits (with the Market Sprite's 50 gold fee), elite spirits from 30% of elite kills and each dungeon's rare spirit on victory. Not yet: custom spirits from the Spirit Forge, trap detection (traps aren't in yet), the Spirit Bestiary |
| Hunter Mode | HUNTER MODE (hunterTurn, hunterAnnounce, showHunterChoice, hunterFight, hunterRun, hunterCatch, hunterSlain, hunterPhaseUp), HUNTER AUDIO | ✅ chosen at character creation: it starts 10 rooms behind and comes a room closer every move and every won fight, with the web version's lines, a pulse, the heartbeat from 5 rooms and the hunter music from 3. At two rooms: Fight (The Hunter, a boss scaled to your level) or Run (a room's head start). Caught: a life lost and it circles back to 8 rooms, or the run ends. Each new floor puts it 3 rooms further back; from floor 2 it moves faster. Killing it ends Hunter Mode for the run with the Hunter's Trophy, gold and XP. New in Swift: its sounds are 3D, behind you (in 3D Mode, from the door you came through). Not yet: switching it on or off from the pause menu |
| Corruption Mode | CORRUPTION SYSTEM (addCharCorruption, checkCorruptionThresholds, CORRUPTION_WHISPERS, onPlayerDeathCorruption, showCorruptionRunModal) | ✅ chosen at character creation and saved on the character: every life lost adds 5% (7% from floor 4, 10% from floor 7). 25%: the dungeon whispers in some rooms. 50%: one fight in ten from floor 2 is the Corrupted Hunter (a stronger elite with Soul Pierce). 75%: skills backfire 15% of the time (10% of your HP, never the last point). 100%: every run is a Corruption Run, with double gold and a legendary weapon or armor from the boss. A Corruption bar shows in the dungeon. The Whispering Forest's own meter is its own row |
| Whispering Forest corruption, The Shade | CORRUPTION SYSTEM (startCorruptionSystem, addCorruption, triggerCorruptionDeath), the Music Box item, spawnTheShade, applyShadeSpecialHit | ✅ in the Whispering Forest a meter creeps up 1% every 8 seconds you spend exploring (it waits during fights, events, the shop and choices), with warnings at 50, 75 and 90; at 100 the forest takes a life. A Music Box waits on floors 3, 6 and 9 and clears it; healing potions push it back 10%. The Shade (8% of fights from floor 9, any dungeon): 289 HP, strikes three times 30% of the time, and in the forest adds 12% corruption a hit (20% for a triple). The meter is saved with the run |
| The Medusa arc | MEDUSA ARC SYSTEM (rollMedusaSpawn, triggerMedusa, applyMedusaGaze, showMedusaChoice, medusaRaiseShield, medusaLowerShield, triggerMedusaFather, triggerLordPhorcys) | ✅ The Hollow from floor 4: Medusa (10%, once a run) with her gaze (35% of her turns: defense down, then a lost turn, then stone). Beaten: Raise the Shield (a normal kill) or Lower the Shield (she walks with you, blocking one attack a fight, and her spirit is yours for good). Her father may then be in any room (60%, 3% less per past reunion, reset monthly), with 50 gold. Runs that never meet her can meet Lord Phorcys from floor 6 (8%). The Lower the Shield, Found and She Still Looks achievements. |
| The Weeping Child, the Weeping Mother, The Music Box | triggerWeepingChild, sootheChild, triggerWeepingMother, motherOption, startMusicBoxCombat, musicBoxMelody | ✅ The Hollow: the Weeping Child (floor 3+, 10% of fights): pick it up (50%), hum a lullaby (55%), or play the Music Box (75%), or it fights you. A Paladin with class traits soothes it on sight. The Weeping Mother (floor 5+, 7%): lead her to the child you soothed (gold and +5 max HP), do a chore (HP), or fight her. The Music Box enemy plays a three-note melody instead of attacking and leaves the Music Box item when beaten. The achievements count |
| The Time Descender, The Clock | rollTimeDescender, triggerTimeDescender, timeDescenderPhaseTwo, timeDescenderClockHit, timeDescenderVictory | ✅ floor 6+, 15% of fights, once a run, any dungeon. Beat it and The Clock begins: it strikes three times, 5 seconds apart, while your actions wait; then you get one strike (a heavy strike can miss) or brace. 80–140 gold, 120 XP, and the first win ever leaves Chrono Armor, which stops the clock for good |
| The Chimera | CHIMERA SYSTEM (CHIMERA_VARIANTS, spawnChimera, chimeraAttack, chimeraEnemyTurn, chimeraVictory) | ✅ 17% of fights from floor 5 (and always on your first visit to the Whispering Forest's floor 9): three parts that each attack and that you target one at a time. The Chimera: Lion Head, Goat Body (regrows 8 HP a turn), Serpent Tail (8 poison a turn). The Corrupted Chimera: the Maw (+15% forest corruption a turn), the Thornbound (reflects a quarter of your damage), the Hollow Shell. The whole beast pays gold and 120 XP when its last part falls. The web version's Hollow Shell was meant to summon help if ignored but never did; in Swift it's simply a third part |
| Wandering NPCs, The Witness, the Easter Bunny, the Black Box | NPC_ENCOUNTERS, tryNPCEncounter, resolveNPCChoice, abyssal-witness, triggerTheWitness, checkWitnessAfterKill, triggerEasterBunny, easterBunnyChoice, Friday the 13th's Black Box | ✅ once a run on floors 2–9, a Wounded Warrior, Lost Merchant, Mysterious Stranger or the Lost Child (who gives a Void Fragment for the Void Chronicles). The Abyssal Deep's Witness: beat the shark and it joins you as a permanent minion (and its achievement). Easter: the Easter Bunny in 15% of fights (fight it, adopt it as your spirit, or let it go). Friday the 13th: a Black Box in 20% of rooms from floor 2, once a floor; open it and The Unlucky One fights you with your crits at zero and steals gold |
| Dungeon conditions (weather) | DUNGEON_WEATHER, ABYSSAL_WEATHER, HOLLOW_WEATHER, rollDungeonWeather, applyDungeonWeatherBonuses | ✅ each run rolls tonight's conditions for its dungeon (the Crypt, Ashbound Wastes, Frosthold, Sunken Archives, Whispering Forest, Abyssal Deep and The Hollow have their own; the rest share one list). They're announced when the run starts, shown in the dungeon, saved with the run, and every effect works: damage both ways, gold, how often fights happen, HP lost per room, max HP and SP, cheaper skills, stronger potions, HP per kill, the Ancient Curse and the Hollow's Full Moon and Silent Night |
| Run Modifiers | RUN_MODIFIERS, rollRunModifier, applyRunModifier, toggleRunModifiers (dd_run_modifiers) | ✅ each run rolls one of eight (Settings → Gameplay turns them off): Burning Dungeon, Frozen Floors, The Watching, Death March, Gold Curse, Phantom Run, Berserk Mode, Blessed Run. Announced when the run starts and saved with it; every one does what it says |
| Settings: Notifications | settings-panel-notifications, scheduleAllNotifications (dd_notif_prefs) | ✅ the 13 switches and Save & Apply, as iPhone notifications: daily reset, streak, night mode, morning, the Void Reaper's last two hours, comeback, the seasonal events, Ambush Days, the next Friday the 13th and the weekly events. Kept current every time the app opens |
| Settings: Developer Tools | openDevToolsPrompt, checkDevPassword, the dev* functions, devSendCoins, devGenerateCode (dd_dev_pw, dd_dev_mode) | ✅ the password (dd_dev_pw, "67" until changed, three wrong tries hide it until the app restarts) and Change Password; 1M diamonds, all guns, all gun parts, unlock all dungeons and reset unlocks; Void Reaper force awaken and reset (for everyone, on the shared record); Medusa force spawn, jump to floor 10, God Mode and force ambush (from Settings in the pause menu); Send Mystery Coins to a player's inbox by email; the VOID reward code generator. The three true ending tools and Reset SR Prompt wait for those systems. Web bug fixed: Unlock All Dungeons left The Whispering Forest locked, and Reset All Unlocks left the Infernal, Abyssal and Shadow World open |
| Settings: Redeem Code, Support, Send Feedback | settings-panel-redeem, settings-panel-feedback, sendFeedback | ✅ Redeem Code has its own panel; Support opens the support page; Send Feedback goes straight to the developer through the same form as the web version |
| Settings: Hide Menu Items, Achievement Sound | renderMenuToggles (dd_menu_prefs), setAchSound (dd_ach_sound) | ✅ show or hide 17 main menu buttons; pick the sound for ordinary achievements with previews |
| Settings: Save codes | exportSaveCode, importSaveCode | ✅ export copies a DD-v96 code (the web version's format) with the whole save; import takes DD-v96 and DD2 codes from either version |
| Weapon Forge | FORGE_MATERIALS, FORGE_SPECIAL_EFFECTS, FORGE_RECIPES, tryDropMaterial, forgeCraft, forgeReroll, forgeKeep (dd_forge_stash, dd_forge_count) | ✅ Home → Forge: materials drop from 15% of kills (commons only before floor 5, rares from floor 8), the 8 recipes, a random special effect, rerolling it for 2 Iron Scrap, and keeping the weapon (into this run's pack and the stash, counted for The Forger achievements). Every effect works in combat |
| Alchemy | ALCHEMY_INGREDIENTS, ALCHEMY_RECIPES, craftAlchemyPotion, applyPotionEffect, alchemyDropOnKill (dd_alchemy_ingredients, dd_alchemy_stored) | ✅ Home → Alchemy: the ingredient shop, ingredients from 10% of kills (matched to the enemy), the 22 recipes with the Alchemist's stronger brews and two Alchemist-only ones, the non-Alchemist's 20% unstable brew, and every potion effect. Potions brewed by the web version outside a run are picked up when the next run starts |
| Tactical potions | mirror-flask, phantom-potion, gravity-tonic, leech-brew, rage-tonic, fog-flask, time-potion, corruption-flask | ✅ all eight work in combat, from the shops or the Alchemy table, and sort under Potions |
| Elixir Vendor | VENDOR_ELIXIRS, renderElixirVendor, sellVendorElixir, buyVendorDailyElixir (dd_elixir_vendor_last_buy) | ✅ Home → Vendor: one of ten elixirs a day for 55 gold, and spare elixirs sold for 25 |
| Your guide | GUIDE PERSONALITY SYSTEM (GUIDE_DIALOGUE), COMPANION SYSTEM (companionSay, companionOn…), toggleGuideFromPause | ✅ the companion you named (Mira by default) speaks in your chosen personality (encouraging, sarcastic, mysterious, calm) when a run starts, at level ups, when you drop to a quarter of your health, when a boss rises, when the hunter is 3 rooms away, when you lose a life and when you win. Each line is said right after what happened and kept in the run log. The pause menu switches the guide and Hunter Mode on or off for the character. Not yet: the achievement lines and the speech-bubble picture |
| Shake to Attack | initShakeToAttack, toggleShakeAttack (dd_shake) | ✅ Settings → Audio → Shake to Attack. In a fight, a shake attacks and a hard shake uses your first skill you can afford, 0.8 seconds apart, at the web version's thresholds. Uses the iPhone's motion sensor directly, so there's no permission prompt |
| Daily Descent (daily login reward) | DAILY_REWARDS, initDailyDescentBadge, checkDailyDescent, claimDailyDescent (dd_daily_descent) | ✅ the main menu badge and Today's Offering: the 30-day cycle of gold, potions, elixirs, Mystery Coins and Soul Fragments, +50 gold a day for every finished cycle, the week dots and the day-30 crown. Same save key and shape, so a web streak carries over. Soul Fragments are saved in dd_soul_fragments for the Spirit Forge. Web bug fixed: the streak check parsed dates like "2026-10-5", which Safari (and so the iPhone app) can't read when the month or day is one digit, so after claiming on those days, missing a day never reset the streak; Swift counts calendar days |
| The familiar | FAMILIAR_SPECIES, getFamiliar, gainFamiliarBond, familiarSpeak, openFamiliarOverlay, familiarRecognizeJulio, familiarRecognizeVoidReaper (dd_familiar) | ✅ the menu badge opens Your Familiar: bond level and bar, titles and the evolution badge, naming it, and choosing among the four species (each unlocked by its milestone). Bond from fights won (+2), searches (+1) and dungeon clears (+15), with the level-up line and the three Bond achievements; now and then a line of its own in a new room; it recognizes Julio and the Void Reaper. The low-sanity comfort waits for Insane mode's sanity |
| Character export and import | exportCharacter, importCharacter, confirmImport | ✅ Your Champions → Export (or a card's Export) shows the code with Copy; Import takes a code from either version |
| Boss riddles | BOSS_RIDDLES, rollBossRiddle, showBossRiddle, answerBossRiddle | ✅ once a boss fight, 22% of your attacks: the boss asks one of 12 riddles, 30 seconds, right heals 59 HP, wrong or too slow makes its attack 25% stronger, with both riddle achievements. Web bug fixed: the right answer was always the first; Swift shuffles them |
| New dungeon announcements | DUNGEON_UNLOCK_INFO, checkDungeonUnlockPopups (dd_dungeon_popup_seen) | ✅ Your Champions announces each newly unlocked dungeon once. The web version had no entry for The Shadow World; Swift uses its dungeon card's text |
| Reset Game | openResetGame, confirmResetGame | ✅ Settings → General → Reset Everything, with the warning; every dd_ key and setting cleared. Not offered from inside a run |
| Trophies screen | openTrophyOverlay | ✅ the menu's 🏆 opens your trophies and every achievement unlocked. The spinning 3D trophy isn't ported |
| Music Player item | useMusicPlayerItem, the shop's Music Player (dd_mp_owned) | ✅ the floor shop sells it for 50 gold until you've owned one; from the bag it opens the music player over the dungeon. The player is shared with the Chronicles |
| Birthday | initBirthdayEvent, openBirthdayScreen, claimBirthdayReward | ✅ on March 23 the menu badge opens the birthday screen: 500 gold once a year and that year's DDBD code. The web version only knew 2026; Swift counts the years, and Redeem Code takes later years' codes |
| Titles | TITLE_TAGS, TITLE_COSTS, openTitlePicker, selectTitle, buyTitle (dd_title, dd_owned_titles) | ✅ Settings → Account → Change Title: ten free, twenty for Mystery Coins, and the three seasonal titles once bought. Web bugs fixed: buying a title threw an error halfway, and the seasonal titles went to the selected character, which from the menu was none |
| Boss timer | startBossTimer, checkBossTimerThreshold, bossTimerEnrage | ✅ when a dungeon boss appears: 5 minutes (3 in The Hollow, one less in Insane) to bring it below half its HP, shown on the boss bar with the one-minute, 30 and 10 second warnings. Beat it for Beat The Clock; miss it and the boss's attack grows 25% and a minion joins. Web bug fixed: the minion was announced but never added; in Swift it fights, and falls with its boss |
| The Shadow Realm | SR, getShadowEnemies, startShadowRealm, shadowAttack, shadowDie (dd_shadow_leaderboard) | ✅ Redeem Code → SHADOW: the intro, choosing a champion, endless waves (stronger every 5, the Shadow Sovereign every 10), Attack, Heavy, Defend, three potions, a little HP after each wave, Retreat, and the ten best runs. The Void Reaper music plays throughout. Its Inventory button isn't ported (in the web version it opened the dungeon's bag, which does nothing here) |
| Daily quests | DAILY_QUESTS, updateDailyQuestProgress | ✅ 15 of 17 (the rare spirit and lore fragment days move to the next quest until those systems are ported); shown on the main menu and at run start |
| Quests, inbox | QUEST SYSTEM … | ⬜ |
| Bounty Board | BOUNTY BOARD SYSTEM (BOUNTY_TEMPLATES, renderBountyBoard, registerBounty, refreshBounties, updateBountyProgress, completeBounty, the dungeon banner) | ✅ all 35 bounties, three a day with 5 refreshes, one active at a time, progress from kills, elites, bosses and floors, gold and trophies when done, the banner in the dungeon. Saved in dd_bounty_data in the web version's shape. |
| The Hunting Grounds, Bounty Rank | THE HUNTING GROUNDS (BOUNTY_RANKS, addBountyXP, startHunt, huntTick, stopHunt, brianSay) | ✅ from the Bounty Board: pick a hunter and send them into the forest. Every 25–45 seconds a fight (more enemies as your rank rises), a find (rares from rank 5) or a rest, with the forest's ambience. Gold, saved items, Bounty Rank XP in dd_bounty_rank (10 ranks), and kills count toward "any dungeon" bounties. Brian narrates through the game's narration service when you're signed in; otherwise VoiceOver reads his lines. The hunt keeps going while you look around the app |
| Spirits, companion, corruption, Hunter, Medusa arc | … | ✅ see their own rows |
| Seasonal events | getActiveEvent, getEventBonuses, renderEventsScreen, openSeasonalShop | ✅ all 16 seasonal and weekly events on their dates, their XP, gold and enemy strength, Blood Moon's harder hits both ways, 20% of enemies replaced by the event's own (56 of them, in events.json), seasonal currency from 30% of kills, the menu banner and currency, the Events screen and the six seasonal shops. Not yet: the event enemies' special moves (the Leprechaun stealing gold, the Cupid's Love Potion …), the Easter Bunny room, Friday the 13th's Black Box, the July 4th Fireworks Corner, the Cinco de Mayo weapon, Ambush Day ambushes, birthday music, and shop items that need systems not ported yet (titles, run modifiers, combat items) |
| Subclasses | SUBCLASSES, showSubclassChoice, chooseSubclass | ✅ the level 5 choice for every class that has one (Berserker and Druid don't, in the web version either), its stat points, its passive and the name in the top bar. The spell passives work with spells (see Spells). Ancient Blood's fire immunity has nothing to block yet |
| Blacksmith | openBlacksmith, openMenuBlacksmith, upgradeEquipped, reforgeWeapon, degradeWeapon | ✅ from the dungeon (run gold) and the main menu (global gold): upgrade weapon and armor to level 10 (Enchanters pay first, Blacksmiths get 10% off, seasonal discounts apply), buy the 11 weapons and 7 armors (the Worn Blade free once), sell, equip and unequip, reforge and raise rarity, the Rarity Effects guide, weapon durability and repairs. Soul Drinker, Thunderfist, The Last Blade, Thornmail, Ghost Shroud and the staff's +10 SP work in combat. The Guns tab says coming soon |
| The Spire | THE SPIRE, startSpire, spireDoPlayerTurn, spireRestFloor, spireVictory | ✅ the setup screen with your best floor and champion, Auto Mode (Level 5, every 4 seconds), the climb from your best floor with Attack, Heavy, Defend, potions and the auto-potion, the 9 bosses, rest floors, milestones, diamond and Mystery Coin drops, the Blacksmith mid-climb, death to The Graveyard and the Obituary, and The Time Eater's rewards. Your equipped gun fires from the 🔫 button; gun parts from Spire floors aren't in yet; the Spire Bestiary tab isn't in yet |
| Home system | HOME SYSTEM, MINION SYSTEM, HOME_DREAMS | ✅ buy the home (500g), bed (75g) and sleep every 5 rooms with a dream, the gold safe, skill upgrades to level 5, the Minions tab, and the Soul Trap combat button. Minions strike after you every round. The Forge, Alchemy and Vendor tabs have their own rows below; the Spirits tab says coming soon; Skill Orbs (upgrades passed on when a character dies) and the July 4th Fireworks Corner are not in yet |
| Global chat, presence, leaderboards | GLOBAL CHAT SYSTEM, initPresence, cleanStalePresence | ✅ Global Chat (see its row), the menu's "⚔ N players online" from the shared presence list, and the High Score, Tournament, Boss Rush and Shadow Realm leaderboards |
| Account login, cloud save | DD Cloud | ✅ see "Account and cloud save" |
| Translations (Portuguese) | T['pt-BR'], the early PT table, setLanguage (dd_lang) | 🟡 `node swift/tools/extract-translations.js` copies the web version's 7,642 English → Portuguese lines into `App/DungeonDescent/Localizable.xcstrings` (keeping entries added by hand for Swift-only text). Settings → Language: device language, English or Português, switching at once; the iPhone's own per-app language setting works too. Screen text written straight into the views, text, buttons and VoiceOver labels built in code, and every spoken line are looked up. 340 Swift-only lines (Home, Hide and Seek, chat, iCloud, 3D Mode, Command Center, Enemy Creator, the rhythm sequence …) have their own Portuguese. Not yet: text built from pieces ("Floor 3", names, numbers), which stays in English. The web version's live MyMemory machine translation isn't ported |
| Spells | ARCANE_SHOP_ITEMS, openArcaneShop, openSpellBook, castSpell, applySpellEffect, checkSpellScrollDrop, spell SUBCLASSES | ✅ the Arcane Shop and Spell Book from the main menu (pick a character, saved gold) and from the dungeon (run gold), the Spell Book item, learning by class (Arcanist 95%, magic classes 75%, half-magic 45%), all 48 scrolls, the ✨ Spells button in combat (a free action with a 3- or 6-turn cooldown), one-use scrolls from the bag, scroll drops from 5% of kills (10% for Arcanists and Wizards), and the spell subclasses: Firelord, Stormcaller, Void Born, Phase Walker, Dark Arts, Night Shroud, Time Lord, Earthbound, Pure Magic and Spell Weaver |
| The Mine | THE MINE SYSTEM, mineDig, mineDescend, mineCombatAction, mineUseSkill, mineSurface | ✅ choose a character, dig (1.5-second swing), the 15-item hands, going deeper (10 HP back each depth), the chest from depth 3, the 19 mine enemies with Attack, Heavy, Defend, Potion, Skill and Flee, the milestone bosses at depths 10, 20, 30, 50 and 100 with their lore, the depth stat and Deep Miner achievement, and surfacing with gold, diamonds, Mystery Coins, potions (to your saved items), gun parts (dd_gun_parts) and alchemy herbs (dd_alchemy_ingredients). The Gun button fires your equipped gun |
| Void Mode | VOID MODE, VOID_HEROES, startVoidMode, voidAction, voidEnemyTurn, generateVoidCode, enterRewardCode | ✅ the Void Commander's 500 HP and four abilities (Void Blast, Shadow Shield, Soul Drain, Dark Strike) with cooldowns, the five waves of heroes with their heals, enrage, crits and Void Bane, 50 HP between waves, and the victory: every character +3 levels (up to 50), the Void Conqueror achievement and a shareable VOID-XXXX-XXXX code. Settings → General → Enter Reward Code redeems Void codes and the birthday codes (DDBD26 …: 1000 gold, the Golden Sword, 15% Blacksmith discount) |
| The Void Reaper | VOID REAPER (initVoidReaper, vrCheckServerTransitions, vrAttack, vrVictory, updateVRMenuBanner) | ✅ the shared world boss on the web version's "void_reaper" record, so Swift and web players fight the same one: the menu banner (stirring %, days until it wakes, awake with hours left and the global HP, or the Void Curse), Face The Void Reaper while it's awake, your own fight (class HP + 20, 3 potions, Attack / Heavy / Defend, three phases from the global HP), 500 damage a strike (600 heavy), the system messages in Global Chat, and the cycle: 1–3 weeks asleep, 24 hours awake, then either defeat and a new cycle or the Void Curse (every dungeon's enemies 50% stronger for 24 hours) |
| The Siege | THE SIEGE (loadSiegeHub, buySiegeUpgrade, startSiege, siegeAttack, siegeEnemyAttack, showSiegeResult) | ✅ the fortress hub (level, durability, Wave Points, stationed minions, dd_siege_data), the four upgrades, Easy / Normal / Nightmare, ten waves with Attack, Heavy Strike, potions, Minion Attack and your gun, the enemy turning on your base below 50 HP, Wave Points for damage, and the result with gold and 3 trophies for a win |
| Challenges | CHALLENGES (GAUNTLET_DUNGEONS, DAILY_MODIFIERS_POOL, startGauntlet, startDailyDungeon, _getDailySetup, the victory handler's Gauntlet and Daily parts) | ✅ The Gauntlet: all six dungeons back to back on one life, HP carried over, the Gauntlet Champion achievement at the end. The Daily Dungeon: the same dungeon and two modifiers as the web version each day (same formula), all eight modifiers working, the first clear's time saved in dd_daily_<date> and the Daily Dungeon achievement. A Challenge in progress is saved like any run and can be resumed |
| Music, ambience, sound effects | playTrack, playAmbient, sfx, getMenuTrack, goTo's music per screen | ✅ the holiday menu music (Halloween and Friday the 13th, Christmas, the birthday), each screen's own track (Bestiary, Help, Codex, Chronicles, Spire, Graveyard, Chat), same files (www/audio, bundled as-is), same track per dungeon and floor, volume settings. Checked against every playTrack call in the web version: the Abyssal Deep boss changes music with each phase, the Hunter fights to the plain battle music, the run summary cuts the music for 1.2 seconds then plays the victory music or the menu's, the death log is silent, and the Siege result keeps its music |
| Music player, custom tracks, narrator | MUSIC PLAYER … | ⬜ |
| 3D Mode | generate3DRoomGraph, moveRoom3D, play3DExitCues, echoLocate, init3DView, ROOM3D_THEMES, get3DSettings | ✅ Settings → Beta Features → 3D Mode (dd_beta_features, same key as the web version) and 3D Settings (Shadows, Torch Flicker, FPS Counter, Minimap; dd_3d_settings). Each floor is a connected grid of rooms with real walls and doors: walls stop you, a new room is the normal room, a cleared room is just a room, Wander grows the map. Sound is real 3D audio (AVAudioEngine with HRTF, best with headphones) instead of left/right panning: you face north like the compass, each open door blips from where it is, a wall thuds from that wall, your footsteps go the way you walk, the enemy's cry comes from the room you walked into, each dungeon has its own room echo, and a falling tone plays as you descend. Echo-Location (button, or VoiceOver's two-finger double tap) answers from every direction, longer down long corridors, and hints at what the next new room holds. The view is RealityKit: every room built in its dungeon's colors and torchlight, the camera gliding room to room, drag to look around, and a minimap for sighted play. In The Shadow World with 3D Mode on, the Stalker Floor is a 7×7 room: the Darkness Swallower starts in a far corner, you hear exactly where it is in 3D, and it keeps coming every 8 seconds even if you stand still; after each escape it starts again from the far side. Free walking with on-screen sticks and Hide and Seek's 3D view aren't ported |

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
- **Dream buffs never applied.** `homeSleep()` ran the dream's buff on the run you
  were in, and the dream's text says "for your next run", so it was gone by the
  time it mattered. The Swift version saves the dream on the character and applies
  it once when the next run starts (+3 attack, +3 defense, +15 max SP, potions heal
  25% more, +10% flee chance or +30% gold from kills).
- **Home skill upgrades did nothing.** The level was saved, but no code read it.
  In the Swift version each level above 1 adds 10% to that skill's damage.
- **Elite minions never happened.** The Soul Trap never told `captureMinion()` the
  enemy was elite, so every minion was common. Elite enemies now give elite minions
  (85% of their attack and a 10% chance of a double hit).
- **No limit on minions.** The Help screen says you can keep up to 8, but the web
  version never checked. Swift stops at 8 and says to release one first.
- **Most subclass passives did nothing.** The web version saved a flag for each path,
  but no code read the flags for Wind Walker, Shadow, Poisoner, Crusader, Beast Caller,
  Archmage, Hawkeye, Trapper, Death Knight, Elementalist, Hex Blade, Dragon Ascendant,
  Brewmaster, Plague Bearer, Phase Walker, Night Shroud, Paradox or Spirit Caller. In
  the Swift version they do what their description says. Night Shroud's "Night Mode"
  doesn't exist, so it uses the same night hours as Night Blessing (8pm to 6am).
- **Battle Hymn never sang.** It added +5 attack while a turn counter was above 0,
  but nothing ever set the counter. Now each skill gives +5 attack for your next 3 attacks.
- **The Bomb Thrower had no bomb.** The bomb recharged every floor, but there was no
  button to throw it. Swift adds a 💣 Bomb button in combat: 60 damage, once per floor.
- **The Warlord's streak never reset.** The passive says +2 attack per kill "resets each
  floor", but it lasted the whole run. Swift resets it on each new floor.
- **Vampire Lord healed from gold, not damage.** It healed 20% of the gold an enemy
  dropped. It now heals 20% of the damage your attacks deal, as described.
- **"Spirit" and "vitality" stat bonuses gave nothing**, because those aren't level
  point stats. They now count as Intelligence and Stamina.
- **Spirit effects that never happened.** Thunder Moth's stun and Glacial Wolf's freeze
  were logged but never applied; the Void Moth's 15% chance to negate a hit had no code;
  the Void Herald's "requires level 7" was never checked. All work in Swift.
- **Glacial Wolf and Frost Crown stacked defense forever.** Their +4 and +5 defense
  "at combat start" were added permanently every fight, so defense kept climbing all
  run. Swift gives the bonus for that fight only.
- **Event gold bonuses were never paid.** Void Week (double gold), the Fourth of July,
  St. Patrick's Day, Brazil, Valentine's Day, Cinco de Mayo, Ambush Day and Friday the
  13th's gold change were shown on the menu and Events screen, but no code applied them.
  Blood Moon's "+25% damage taken" was never applied either. Swift applies all of them.
- **Most seasonal shop rewards vanished.** Demon Revival's bonus life, the XP boosts
  (Potion of Darkness, Cookie of Knowledge, Independence Scroll, Feast of Knowledge),
  the Elf Blessing and the Sparkler buff were saved for "your next run" but nothing ever
  read them; potions bought from the menu went into a run that wasn't there. Swift
  applies them when the next run starts, and potions go into that run's bag.
- **Reforging stacked rarities.** Reforging or raising a weapon's rarity applied the new
  tier on top of the old one, so names became "Rare Uncommon Iron Sword" and the attack
  multiplied twice; a reforge that rolled Common changed nothing. Swift rebuilds the
  weapon from its base each time.
- **Armor upgrades had no cap.** Weapons stop at level 10, but armor kept going at ever
  higher prices. Swift caps both at 10.
- **The menu Blacksmith used your last run's profession.** From the main menu it said
  there was no Blacksmith discount but still charged the last run's discounted price.
  Swift gives no profession discount on the menu, matching what it says.
- **Only The Time Eater ever appeared in The Spire.** Every tenth floor was a rest
  floor, and every boss floor (10, 50, 100 … 1000) is a multiple of ten, so the rest
  floor always won. The same rule meant milestone gold and the every-ten-floors diamond
  and Mystery Coin drops never happened. Swift puts bosses on their floors, makes the
  other tenth floors rest floors, and pays each tenth floor's rewards once.
- **Spire kills paid twice.** Each kill's gold was added to your global gold two times.
- **The Time Eater's 25 Mystery Coins went nowhere.** They were put on the character,
  where the Coin Shop never looks. The victory screen also said +500 gold while the game
  paid 1000. Swift pays 1000 gold and 25 Mystery Coins and says so.
- **Gear changed at the Blacksmith mid-climb didn't count** until the next climb. Swift
  updates your attack and defense when you leave the Blacksmith.
- **Shadow World floor names were one floor off.** Its list has no empty first entry like
  the other dungeons', so floor 1 showed floor 2's name and "The Place That Wasn't" never
  appeared. Swift lines them up.
- **Three Shadow World enemies' moves never happened in a fight.** The Shadow Archon's
  command (+15% damage), The Unborn's "weapons deal half damage" and the Shadow Pup's
  pair were only used by the Shapeshifter's Mask. Swift applies them (the second Shadow
  Pup takes the first one's place, since fights are one-on-one).
- **The Lurker hid and struck on the same turn.** Its description says it hides on the
  first turn and lands a guaranteed critical on the second; Swift does that.
- **Continue Journey** from The Abyssal Deep now leads into The Shadow World.
- **Ambushes ran a separate, thinner fight.** The web version's ambush code had its own
  attack and enemy-turn rules: no armor rarity effects, no enemy abilities or statuses,
  enemies ignoring your armor's level, a 12% crit and a 25% heavy miss instead of the
  normal ones. Swift runs ambushes through the normal fight, so every ability, subclass,
  spirit, armor effect and enemy move works in them too.
- **Walking into the Darkness Swallower didn't catch you.** It moved after you did, so
  stepping onto its square let it step off you again. Swift counts it as caught.
- **The Stalker Floor's 150 gold** went to the run but not to your global gold.
- **3D Mode could strand you on a floor.** If every room on the map had been visited
  while the floor was still short of its room count (a room that didn't count, like the
  one where the Darkness Swallower found you), there was nowhere new to walk. Swift grows
  the map whenever it has fewer new rooms than the floor still needs, and a room the
  Stalker Floor took over stays new.
- **3D Mode's door blips were only panned left and right.** North and south were told
  apart by pitch alone. Swift places every sound in real 3D, keeping the pitch difference.
- **Leaving the merchant in 3D Mode** jumped you into the next room without walking.
  Swift leaves you standing where you are, with the room's doors read out.

- **Most spells did nothing after their message.** Frost Lance's freeze, Blood Shield,
  Phantom Step, Void Anchor, Chain Curse, Soul Drain, Time Stop's free turns, The
  Forgotten, Blood Oath, Soul Bound's control, Nightmare Weave, Curse of Echoes, Void
  Mirror, Time Fracture, The Hunger, Soul Leash, Soul Echo, Extraction and Lose Reality's
  reward only set a flag nothing read. Swift makes each one do what it says. (Void Mirror
  makes the enemy's blows heal you for 2 turns; Shattered Reality weakens its next hit and
  lays it open, since Swift enemies have no defense to swap; Dungeon Echo's answer makes
  the enemy take 30% more for 3 turns.)
- **None of the spell subclass passives worked.** Firelord, Stormcaller, Void Born, Dark
  Arts, Time Lord, Pure Magic, Spell Weaver (and Phase Walker's and Night Shroud's spell
  parts, and Earthbound's Earthshake) only set flags. Swift applies them.
- **A scroll bought without a Spell Book could never be used.** It went into the bag as a
  "spell-scroll" item that nothing knew how to read. In Swift you read it in combat for one
  cast, or, as a magic class with a Spell Book, outside combat to try to learn it.
- **Buying the Spell Book from the main menu broke.** The book was only ever set on the
  current run, so from the menu the purchase failed, and in a run it was forgotten when the
  run ended. Swift keeps the Spell Book on the character, the same field the web version saves.
- **The Final Boss's failure took your skills away for the whole run.** Swift strips your
  buffs, as the scroll says.
- **Shadow Blast was listed twice in the Arcane Shop.**
- **Mine enemies' special moves never happened.** The Dust Shade's and Shaft Lurker's
  dodges, the Tunnel Snake's poison, the Stone and Diamond Golems' first-hit immunity (and
  the Diamond Golem's 20% resistance), the Iron Sprite's drain, the Crystal Wolf's and
  Forgotten Foreman's growth, the Vein Horror's lifesteal and the Ore Demon's burn were
  written down but never copied onto the enemy. Swift makes them work, and tells you each
  enemy's move when it appears. (The Iron Sprite blocks your skills for a turn, since the
  Mine has no SP.)
- **Mine Mystery Coins went missing.** They were written straight into one coin store
  instead of through the coin counter the rest of the game reads. Swift adds them like
  every other Mystery Coin.
- **Some Mine kills never reached the Bestiary.** The kill was saved under an ID built from
  the name ("mine-mine-bat") that doesn't match the Bestiary's ("mine-bat"). Swift records
  them by name.
- **Leaving the Mine from the menu** only warned about your hands; the chest was silently
  lost too. Swift's warning counts both.
- **The Mine's gun never needed charging or reloading.** It fired every turn, unlike the
  same gun everywhere else. In Swift it charges, empties and reloads the same way in every mode.
- **The iCloud backup left most of the save behind.** It saved only twelve keys
  (characters, unlocks, achievements …), so gold, diamonds, items, Home, spirits, the
  Mine's and guns' saves and more never reached iCloud. Swift backs up the whole save,
  alongside the old twelve fields so the old app can still read it.
- **Two Void code prizes did nothing.** "5/10 Mystery Coins" were put on each character,
  where nothing reads them, and "2x XP for your next run" saved a flag nothing read. Swift
  adds the coins to your Mystery Coins and doubles your XP for the next run.
- **The Void Reaper paid only the killing blow — and to the wrong place.** The screen
  promised 2000 gold and 50 Mystery Coins to everyone who struck, but only the player who
  landed the last hit was paid, and the gold went onto the character where nothing reads
  it. In Swift everyone who struck in a cycle that ends in a kill collects (the kill is
  remembered in the shared record), into your real gold and Mystery Coins.
- **Two Void Reaper strikes at the same moment could erase each other.** Each one read the
  HP, subtracted, and wrote it back. Swift strikes in a database transaction.
- **The Void Curse (enemies +50%) came from a value only the web version could see.**
  Swift reads the same shared record and applies it to every enemy and boss.
- **The Siege fought every hero as the same nobody.** It read the character's max HP,
  attack and level, which characters don't store, so everyone had 150 HP and 8–14 attack.
  Swift uses your class and level.
- **The Siege's Minion Attack was free and endless.** It cost no turn, so it could be
  pressed over and over. In Swift it takes your turn.
- **Station Minion stationed your first minion again every time.** Swift sends the next
  minion you haven't stationed.
- **No one could win the Siege.** Enemies got 20% stronger in everything every wave, so
  the tenth hit five times harder than the first with nothing given back. In Swift enemy
  attack grows 10% a wave (HP still 20%) and you get 20% of your HP back between waves.
  A strong hero can now clear Easy; Normal and Nightmare stay hard.
- **"Moving..." and then silence.** When a move started a fight, the compass button you
  had pressed disappeared and VoiceOver jumped to the new buttons, cutting off the room
  announcement after "Moving north". Swift waits for that jump before speaking.
- **Daily Dungeon modifiers never did anything.** They were switched on and then the
  dungeon set-up wiped them a moment later, so every Daily Dungeon played like a normal
  run. Swift keeps them on the run. "Stripped" (no shop) wasn't even read anywhere; it
  now removes the merchant.
- **The Gauntlet's last dungeon didn't exist.** It was listed as "Whispering Forest"
  instead of "The Whispering Forest", so the sixth stage (and some Daily Dungeons)
  pointed at nothing. Fixed.
- **The Gauntlet promised one life and gave the usual lives.** It now gives one.
- **The Gauntlet stole your character's home dungeon.** It moved the character into
  each Gauntlet dungeon and meant to move them back, but read the saved dungeon from the
  wrong place, so they stayed in The Whispering Forest. Swift never moves the character.
- **Leaving the app lost the Gauntlet.** Its progress lived only in memory; a resumed run
  was a normal run. Swift saves it with the run.
- **Endless characters could never finish a Challenge.** Endless has no boss, so the
  dungeon never ended. Challenges run on Wanderer for Endless characters.
- **Bounties said "in The Crypt" but counted kills anywhere.** A Wailing Wraith bounty
  for The Crypt went up in any dungeon. Swift only counts the dungeon the bounty names.
- **"In a single run" bounties added up across every run forever.** Swift starts the
  count again when a run starts.
- **"Reach floor 8 without dying" didn't care if you died.** Swift only pays it when you
  haven't lost a life on the run.
- **The hunter's "faster" second phase wasn't faster.** From floor 2 it announced it was
  moving faster, but it still came one room a turn. In Swift it takes an extra step every
  third turn. (Its idle rush, for standing still, was never called by anything, so it isn't
  in Swift either.)
- **Corruption Mode did almost nothing.** Corruption was only added on one rare kind of
  death (the Music Box trap), and reaching 50%, 75% and 100% only set flags that nothing
  read: no Corrupted Hunter, no backfiring skills, no doubled gold or legendary reward.
  Swift adds it for every life lost and does all four things the description promises.
- **The guide never cheered a level up, a victory or a death.** Those lines were written
  for all four personalities, but nothing ever called them. Swift says them.
- **A hard shake wasted your turn.** It asked the fight for an action called "skill0",
  which no part of the fight code handles, so you did nothing. Swift uses your first
  skill you can afford.
- **The Shadow World's events never corrupted you.** The Mirror, the Offering and the Two
  Doors added their corruption through the Whispering Forest's corruption meter, which does
  nothing outside the Whispering Forest. Swift adds Shadow Corruption, as their text says.
  Darkness Swallower's camera but played it centered. Swift plays it in 3D from that side.
- **The forest killed you again and again.** At 100% corruption the forest took a life, but
  the meter stayed full, so the next 8-second tick took another. Swift empties it after.
- **"Find the Music Box or use a potion" — potions did nothing.** The 75% warning told you
  to drink a potion, but potions never touched the meter. In Swift a healing potion pushes
  it back 10%.
- **The forest's corruption reset when you left.** It lived only in memory, so quitting
  and resuming cleared it. Swift saves it with the run.
- **"She Still Looks" could never be earned.** Nothing ever counted it. In Swift it's
  earned when a run ends with Medusa still searching for her father.
- **Every hunter was the same.** The hunt read HP, attack and defense fields that
  characters don't have, so everyone hunted with 100 HP and 8–14 attack. Swift uses the
  character's class stats.
- **Critical hunt strikes did nothing.** Kills could be "CRITICAL!" but paid the same, and
  rank 7's "Critical hunt strikes unlocked" changed nothing. From rank 7 a critical kill
  now pays double rank XP.
- **The Time Descender only came to The Hollow.** It was described as appearing in any
  dungeon, but its roll sat inside The Hollow's encounter list. Swift rolls it everywhere.
- **Chrono Armor froze the fight.** With the armor, phase 2 skipped the clock but never
  opened the strike window, so no attack could land and the fight couldn't end. Swift lets
  you strike freely.
- **One wandering NPC per app launch, not per run.** The "once a run" flag was never
  reset, so after the first NPC you'd never meet another until you restarted the game.
- **The Lost Child gave two Void Fragments at once.** Her reward and a second, separate
  call both added one. Swift gives one.
- **The Wanderers Rune couldn't be used.** It was a rune with no effect, so using it did
  nothing. In Swift it's a keepsake you can sell.
- **Beating The Unlucky One ended the whole dungeon.** It was marked as a boss, and killing a
  boss means victory, so a Black Box on floor 2 could win the run on the spot. In Swift it's
  a tough elite.
- **The Abyssal Deep's conditions did almost nothing.** Only Thermal Vent's heal worked;
  Crushing Depth, Bioluminescent Bloom, The Current and Midnight Zone were announced but
  never applied. Swift applies them.
- **Several conditions were only words.** Stronger potions (Divine Blessing, Cooled Ashes,
  Crypt Mist, Hallowed Ground, Library Silence), Fever Run's extra damage taken, Ancient
  Curse, Forest Blessing's heal per kill and the Hollow's Full Moon gold never did anything.
  Swift applies them all.
- **Conditions vanished when you left.** They lived only in memory, so a resumed run had
  none. Swift saves them with the run.
- **The Witching Hour's "enemy critical hits doubled" isn't in Swift**, because enemies
  don't land critical hits in either version. Its description now says what it does.
- **Seven of the eight Run Modifiers did nothing.** Only the gold boosts and Berserk's
  no-defend were ever read; fire damage, Frozen Floors, The Watching, Death March, Gold
  Curse's potion prices, Phantom Run and Berserk's damage were announced and ignored.
  Swift applies all of them.
- **The Friday the 13th reminder ignored its switch.** It was scheduled even when turned
  off. Swift honors it.
- **The Void Reaper warning wasn't about the Void Reaper.** It fired 14 hours after you
  opened the app, whether the Reaper was awake or not. Swift schedules it for two hours
  before the awake Reaper's window closes.
- **Forged weapons hit like a starter sword.** The forge saved a weapon's attack as
  `atkRange`, but attacks read `atkBase`, so every forged weapon hit for the default 5–8.
  Swift uses the recipe's range (and reads `atkRange` on weapons forged by the web version).
- **Forge effects did nothing.** Burning, Life Steal, Keen Edge, Venomous, Lucky, Arcane,
  Shattering, Swift, Thorned and Executioner were written on the weapon and never used in a
  fight. In Swift they all work. Enemies have no defense here, so Shattering cracks their
  guard instead: each hit landed adds 2 damage, up to 10.
- **A second forged weapon of the same name could disappear.** The stash keeps one weapon
  per name when a run loads it. Swift names the second one for its effect, such as
  "Iron Blade (Burning)".
- **Three alchemy potions did nothing.** Bloodfire's burn and Glacier Tonic's stun were
  set and never read, and the Time Potion's free attacks were never given. In Swift the
  next enemy burns or is stunned, and the Time Potion takes the enemy's next turns away.
- **Alchemist brews lost their bonus.** An Alchemist's Phantom Potion, Gravity Tonic, Leech
  Brew, Rage Tonic, Fog Flask, Time Potion and Corruption Flask were brewed stronger, but
  using one always gave the shop version's numbers. Swift uses what was brewed.
- **Most class traits did less than they said, or nothing.** The Ranger's Opening Shot and
  the Assassin's First Blood ("every combat") only worked in the first fight of a run. The
  Necromancer's risen enemy, the Bard's enemies leaving, the Wizard's enemy reading, the
  Paladin's stronger holy skills, the Naturalist's and Shaman's doubled weather, the Shaman's
  outdoor defense, the Elementalist's stronger spells, the Void Walker's phasing and sure void
  spells, the Shadow Mage's free shadow spells and the Time Mage's faster time spells were only
  flags nothing read. The Druid healed once a floor instead of every room in The Hollow. The
  Sorcerer's HP was cut twice (to 68%, not the 80% it says) and the Alchemist's potions healed
  2.7 times instead of double. Swift does what each trait says. Two the web version made up and
  never defined are left out: the Cleric's "one potion at a time" and the Time Mage's "always
  wins initiative" (you always act first anyway). "Attacks from darkness" for the Shadow Mage
  means at night, 8pm to 6am, like Night Shroud; "outdoors" for the Shaman means the Ashbound
  Wastes, Frosthold and the Whispering Forest.
- **Two Daily Challenges were only words.** Speed Run promised enemies hitting 25% harder and
  Cursed Day promised no potions in combat; neither was ever checked. Swift does both.
- **Most seasonal combat items did nothing.** The Patriot Cannon could never be used; the
  Freedom Potion's debuff immunity was never given; the Irish Stout, Leprechaun's Charm,
  Rainbow Shield, Enchanted Rose, Cupid's Arrow and Heart Shield applied their buff the moment
  you bought them, which from the menu meant to no run at all; the Love Potion just ended the
  fight. In Swift all ten wait in your next run's bag and do what they say when used (the Love
  Potion makes the enemy strike itself for 2 turns).
- **The Curse Shop's Cursed Modifier did nothing.** It promised a run modifier on your next
  run; Swift gives one, even with run modifiers turned off.
- **Two music files are WAV, not MP3** (music-blacksmith.mp3 and music-raid-victory.mp3).
  Browsers play them anyway; iOS played nothing. Swift opens each file by what it really holds.
- **Half the races did nothing.** The stat lines on the race cards (Human's "+All Stats",
  Elf's "+AGI +INT", Dwarf's "+STR +DEF", Orc's "+STR+STR -DEF", Tiefling, Shade, and the
  Gnome's and Merfolk's stats) were never applied; Golem had no code at all (no +5 defense,
  no immunity); Halfling's 15% dodge was set and never read; Vampires never lost the 20%
  max HP; Goblins never got their starting gold; Angels never healed on level up. In Swift
  each "+STAT" is one level point on that stat, "-STAT" takes one away (Orc defense never
  goes below zero), and Human gets half a point of every stat. Goblins start each run with
  30 gold, Angels heal 15 HP a level, Golems shrug off poison and freezing (burns still
  get through), Halflings slip 15% of attacks. Abilities follow the Class Traits setting
  like the web version's; stat lines always apply.
- **Effect potions couldn't be drunk at full health.** Berserker Brew, Shadow Cloak and the
  others were refused with "Your health is already full" even though they don't heal.
- **The Enchanter was never in the shop.** It was listed with a price but never stocked, so
  the only way to get one was luck the web version never rolled. Swift drops it from 2.5% of
  searches and kills, and using it from the bag tells you which weapon or armor it will add
  charges to at the Blacksmith (it stays in your bag).
- **Cursed Vials, Cursed Heirlooms and the Warding Bell did nothing when used.** Cursed items
  now roll one of six outcomes (heal 60, lose 30 HP, +25 SP, +6 attack, lose 2 defense and 15
  HP, or 40 gold). The Warding Bell senses the next trap when you search, like the Scholar and
  the Frost Sprite, with a radar ping.
- **Skill Orbs never reached anyone.** Orbs were made on every lost life, wiping your Home
  upgrades each time, and saved where no screen ever looked ("Check your global inventory"),
  so they could never be used. Swift makes them when the run ends in death and lists them at
  Home under Skill Upgrade, where a character of the same class can use them.
- **The Shapeshifter's Mask kept its power forever, and the Void Web did nothing.** The copied
  ability lasted past the fight (it says "this combat") and the web's Void Web was never
  woven. Swift keeps each ability to its fight and the web deals 8 a turn. "Corruption on
  hit" had no meaning outside the Whispering Forest; in Swift your next attack deals 10 more
  damage for each corruption stack the copied enemy inflicts.
- **Three first-run tips never showed.** The tips for your first fight, first boss and first
  elite were written but never called. Swift shows them.
- **Legacy Mode never kept your level.** It saved your level when you cleared a dungeon, but
  every new run started at level 1 anyway. Swift starts a Legacy run at your saved level
  (the Dungeon Tier scaling works as in the web version).
- **The Independence Tournament could be won every run.** It promised one tournament per event
  but restarted after each win. Swift gives it once a year.
- **Fireworks Corner XP went nowhere.** It was added to a character field nothing read; Swift
  gives it to your run.

- **The terminal character creator offered a difficulty that doesn't exist.** Its list had
  "Explorer" and was missing Ironblood and Insane; Swift lists the real ones. It also let a
  sixth character be made past the limit.
- **The Enemy Creator refused innocent names.** Its word filter matched inside words, so
  "Hellhound", "Shellback" or "Assassin" could not be submitted. Swift checks whole words.
- **Answering the abyss did nothing.** Winning the Leviathan's rhythm sequence promised +40%
  attack and +30% defense for 2 turns, but nothing ever read the bonus. Swift gives it.
- **Three professions were missing half their bonus.** The Tinkerer's "skills cost 2 less SP"
  worked, but the Warden's debuff immunity was set and never read. In Swift the Warden shrugs
  off the first freeze, burn, poison or stun each floor. (Street Rat's Smoke Bomb and the
  Tinkerer's potions needed the web version's start code, which Swift now has.)
- **The Echo Staff only had a description.** "Spells cast twice — second cast deals 50%
  damage" was never coded. Swift echoes every damaging spell for half.
