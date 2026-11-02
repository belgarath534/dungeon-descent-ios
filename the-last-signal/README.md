# The Last Signal

An accessibility-first, first-person psychological horror investigation game. It is designed to be played completely by sound and text, with VoiceOver or any other screen reader.

This folder is a separate project from Dungeon Descent. It shares the repository but nothing else: Dungeon Descent's builds only use the top-level `www/` folder and are not affected.

## Play it

The game is plain HTML and JavaScript with no build step. It needs to be served over HTTP (opening `index.html` directly from disk will not load the scripts).

```
cd the-last-signal
npm run serve
```

Then open http://localhost:8080. On an iPhone on the same Wi-Fi network, open `http://<your computer's IP>:8080` in Safari with VoiceOver on. Any static host also works (GitHub Pages, Netlify, Firebase Hosting).

## Test it

```
npm test                         # engine, content validation, every story branch (Node 20+)
node tests/browser-smoke.mjs     # plays Chapter 1 in a real browser (needs Playwright)
```

## What is in this build

**Part One is complete: seven chapters, six endings.** Part Two will continue inside this same game.

**Chapter 1: The Signal.** Patrol car, front gate, reception, security office, main corridor, Daniel's office, and the elevator to the sublevels.

- First contact with Daniel over the radio, with honest, evasive and dishonest answers.
- Trust that rises and falls, lies that are remembered and can be exposed later.
- Two ways down: earn Daniel's help, or find a hidden override card by listening.
- 7 documents, 1 recording, 2 hidden discoveries.
- A chapter summary of your choices.

**Chapter 2: Preservation.** Sublevel 1. Find Emily Carter alive in a failing preservation capsule, decide whether to tell Daniel, power the medical ward, move her there and keep her alive. Ends with Daniel asking you to wake Prototype 001.

- Emily's power and condition change as you act, with staged warnings over the radio. She can die.
- A lie about Emily can be discovered through her alarms or the records.
- 3 documents, 1 recording, 2 hidden discoveries. Choices from Chapter 1 carry over.

**Chapter 3: Awakening.** Wake Prototype 001 and learn who sent the signal. 001 patrols Sublevel 1, tracked entirely by sound: footsteps in the ear of its direction, warnings before it walks in, and Listen to locate it. Hide, hold still, back away, or speak to it. Take its key while it recharges and ride the freight lift to Sublevel 2.

- Caught once: hurt. Caught again before treatment: death, then retry from the last checkpoint.
- Emily still needs care while 001 roams.

**Chapter 4: Remains.** Sublevel 2. Find Daniel's body, kept breathing by machines, and the empty frame where his robotic body used to stand. Find Emily's revival codes, ride back up past 001, wake her, and let her speak to Daniel over the radio.

- Emily's care from a distance: Daniel can watch her if he trusts you, and a medical link can power her ward and run a partial check.
- 3 documents, 1 hidden discovery. Every earlier choice carries over.

**Chapter 5: Relocated.** Emily knows where the board hid the rest of Daniel. Get bolt cutters from storage past 001, take the elevator up with a maintenance trick, cut the chain on the stairwell door from Chapter 1, and open the isolation room with his own heartbeat. A quiet romantic thread between Emily and Daniel begins.

**Chapter 6: The Board.** Meet Daniel in person and give him Emily's lanyard. Give 001 back the kind core Daniel wrote. Then the last board member walks in: Marcus, the "M." from Chapter 1. Arrest him, hear him out, or let Daniel decide.

**Chapter 7: The Last Signal.** The finale of Part One, with six endings depending on everything you did: Two Coffees (romantic), Home, Silence, Code Four, Names, and The First of Its Kind. Endings found are remembered across playthroughs, and you can go back to the final choice to try another.

**Foundation:** accessible menus, first-run setup, three speech modes, spatial sound effects and room ambience, journal, inventory, message history, autosave and 3 save slots, settings (speech, volumes, mono audio, startle reduction, trust feedback, text size, high contrast, keyboard shortcuts), and a sound glossary.

## Documents

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the code is organised and what comes next.
- [docs/STORY_BIBLE.md](docs/STORY_BIBLE.md): the canon from the brief, what was added in Chapter 1 and needs approval, and open questions.
- [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md): the VoiceOver testing checklist.
- [docs/AUDIO_CREDITS.md](docs/AUDIO_CREDITS.md): where every sound and song came from (all CC0).

Live build: https://the-last-signal-game-bk6r.netlify.app
