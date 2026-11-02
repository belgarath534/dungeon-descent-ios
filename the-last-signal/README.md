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

**Foundation:** accessible menus, first-run setup, three speech modes, spatial sound effects and room ambience, journal, inventory, message history, autosave and 3 save slots, settings (speech, volumes, mono audio, startle reduction, trust feedback, text size, high contrast, keyboard shortcuts), and a sound glossary.

## Documents

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the code is organised and what comes next.
- [docs/STORY_BIBLE.md](docs/STORY_BIBLE.md): the canon from the brief, what was added in Chapter 1 and needs approval, and open questions.
- [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md): the VoiceOver testing checklist.
- [docs/AUDIO_CREDITS.md](docs/AUDIO_CREDITS.md): where every sound and song came from (all CC0).

Live build: https://the-last-signal-game-bk6r.netlify.app
