# The Last Signal: architecture

## Goals that shaped every decision

1. **Accessible first.** Every screen is built from real HTML: headings, lists, `<button>`, `<label>`, `<select>`. Screen readers, Switch Control, keyboards and touch all work without special cases. There is no canvas-only UI.
2. **Content is data.** Rooms, dialogue, documents and triggers are plain JavaScript objects with declarative conditions and effects. New story content does not need engine changes, and a validator checks it for mistakes.
3. **The engine runs headless.** The game core never touches the DOM or audio. It emits events, and the UI turns them into sound, speech and focus changes. Every story path can be tested in Node in milliseconds.
4. **Time passes when you act, not while you read.** Every action costs in-game minutes. Screen reader users read at very different speeds, so nothing in the game runs on a real-time clock that punishes slow reading. Emily's care and Prototype 001's movement will use this same clock.

## Layout

```
the-last-signal/
  www/                       The game. Static files, no build step.
    index.html               Page shell with two ARIA live regions.
    css/style.css            Dark, high-legibility theme; text size and contrast settings.
    js/
      main.js                Creates the services and starts the app.
      core/
        game.js              Engine: state, actions, triggers, timers. Returns text "beats".
        state.js             The save-game state shape (plain JSON).
        conditions.js        Declarative conditions: { flag }, { has }, { trustAtLeast } ...
        effects.js           Effect registry: systems register the effects they own.
        save.js              Versioned saves, slots, migrations, corruption handling.
        settings.js          Player preferences (kept separate from saves).
        validate.js          Static content checker used by the tests.
        events.js            Small event bus.
      systems/
        world.js             Rooms, exits, objects, inventory, look and listen.
        dialogue.js          Branching dialogue with conditional choices and routes.
        trust.js             Daniel's trust, honesty and lies (lies can be exposed later).
        journal.js           Documents, recordings, objectives.
      content/
        index.js             Picks the content to load.
        chapter1/            Rooms, dialogue, documents, triggers for Chapter 1.
      a11y/announcer.js      Speech: live regions, native iOS screen reader, self-voicing.
      audio/
        audio-engine.js      Web Audio engine: buses, stereo placement, ambience crossfades.
        cues.js              Every sound effect, synthesised (no audio files needed yet).
        soundscapes.js       Looping ambience per room, changes when power is restored.
      ui/
        app.js               Screen switching, focus, autosave, events to sound and speech.
        dom.js               Tiny DOM helpers.
        screens/             Game, menus, journal, settings.
  tests/
    engine.test.js           Content validation and full playthroughs of each branch.
    browser-smoke.mjs        Plays Chapter 1 in a real browser through the UI.
  docs/                      This file, the story bible, the accessibility checklist.
```

## How one action flows

1. The player presses a button, for example "Take the facility radio".
2. The UI calls `game.act('front_desk', 'take_radio')`.
3. The engine applies the action's effects (`give`, `setFlag`, `objective`), advances the clock, then runs any due timers and triggers. Here the `first_contact` trigger starts Daniel's dialogue.
4. Everything that happened comes back as one **beat**: an ordered list of lines (narration, speech with speaker, system messages).
5. The UI renders the beat into the narration block and **moves focus to it**, so VoiceOver reads it at once. Sound cues were already played through events. The game autosaves.
6. Swiping right from the narration reaches the next set of choices.

## Speech: three modes

| Mode | Who it is for | How text is delivered |
|---|---|---|
| Screen reader (default) | VoiceOver, TalkBack, NVDA, JAWS users | Focus moves to new text. Short notices go to an ARIA live region, or to the native iOS screen reader through the Capacitor ScreenReader plugin once the game is wrapped as an app. |
| Built-in voice | Players who want audio but do not use a screen reader | The browser's speech synthesis reads new text and every control as it is focused. |
| Text only | Sighted players who prefer reading | No speech from the game. |

The first launch asks which mode to use, in plain buttons a screen reader can read.

## Sound language

All sounds are synthesised for now, so the full sound design exists from day one and recorded assets can replace any cue later through `audio.registerSample(name, url)` without code changes.

- **Space:** things on the left play in the left ear, right in the right, ahead in the centre. This applies to objects, exits and focus ticks. "Mono audio" turns it off; directions are always also spoken in text.
- **Categories:** interface sounds are short, high and clean; world sounds are filtered noise; story sounds (the signal, trust) are tonal. The "How to play" screen has a sound glossary that plays each one.
- **Ambience** is deliberately quiet so it never masks the screen reader, and each room changes when emergency power comes on.

## Trust and honesty

- `trust` (-100 to 100) is what Daniel feels. `honestAnswers` counts honesty. They are separate on purpose: telling Daniel an unwelcome truth can still lower his trust.
- A `lie` costs nothing when told. If it is exposed later (`exposeLie`), trust drops sharply. Chapter 1 shows this: claim to be a contractor, and Daniel hears your police call sign when dispatch checks in.
- Every change is stored with its reason, for the chapter summary and future dialogue that remembers what you did.
- Feedback is a setting: a soft sound (default), sound and speech, or nothing.

## Planned systems (next increments)

These plug into the same engine. Each one is a new file in `systems/` plus content.

- **Medical ward (Emily): built in Chapter 2.** `systems/ward.js`. Power and stability change every in-game minute through `ctx.onTick`. Warnings are staged and become part of the action's text. Content uses the effects `wardStart`, `wardMoveIn`, `wardAddPower`, `wardStabilize`, `wardReport` and the conditions `emilyAlive`, `emilyIn`, `wardActive`.
- **Prototype 001.** A `patrol.js` system: 001 moves between rooms on the in-game clock along a route. Its position is always audible as footsteps panned by direction and muffled by distance in rooms, so stealth is fully playable by ear. New actions: hide, hold still, and listen for its position.
- **Endings.** An ending is a trigger with conditions over flags, trust history, Emily's fate and discoveries, so nothing is locked in early and the creator can rebalance endings freely.
- **iOS app.** Wrap `www/` with Capacitor as its own app (its own bundle ID, separate from Dungeon Descent). Add the ScreenReader plugin, which the announcer already uses if present, plus an audio session set to "playback" so the silent switch does not mute the game.

## Adding content

- New room: add an entry to `content/chapter1/rooms.js` with exits pointing to it.
- New conversation: add to `dialogues.js`; start it with `{ startDialogue: 'id' }` from any effect list.
- New document: add to `journal.js`; give it with `{ addDocument: 'id' }`.
- Run `npm test`. The validator reports unknown rooms, items, documents, effects, condition names and broken dialogue links.
