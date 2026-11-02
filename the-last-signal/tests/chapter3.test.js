import { test } from 'node:test';
import assert from 'node:assert/strict';

import { createGame } from '../www/js/core/game.js';
import { createEventBus } from '../www/js/core/events.js';
import { content } from '../www/js/content/index.js';

const text = (beat) => beat.lines.map((l) => (l.speaker ? `${l.speaker}: ` : '') + l.text).join('\n');
const choose = (game, fragment) => {
  const c = game.view().choices.find((x) => x.text.includes(fragment));
  assert.ok(c, `no choice "${fragment}"; have: ${game.view().choices.map((x) => x.text).join(' | ')}`);
  return game.choose(c.index);
};
function finishTalk(game) {
  let out = '';
  for (let i = 0; i < 30 && game.view().mode === 'dialogue'; i++) {
    const cs = game.view().choices;
    out += text(game.choose((cs.find((c) => c.index === -1) || cs[0]).index)) + '\n';
  }
  return out;
}

// Build a Chapter 3 start directly from a fresh state: what matters here is
// 001, not the earlier chapters (those have their own tests).
function startChapter3({ readProposal = false } = {}) {
  const game = createGame({ content, bus: createEventBus() });
  game.newGame();
  const s = game.state;
  Object.assign(s.flags, { daniel_contacted: true, power_on: true, told_daniel_emily: true, found_emily: true, saw_001: true, ward_door_powered: true });
  if (readProposal) s.journal.read.doc_proposal = true;
  s.inventory.push('facility_radio');
  s.chapter = 2;
  s.ended = { chapter: 2 };
  const beat = game.startNextChapter();
  assert.equal(game.state.chapter, 3);
  assert.equal(game.state.location, 'storage');
  assert.ok(beat.checkpoint, 'chapter start saves a checkpoint');
  choose(game, 'How do I wake it');
  finishTalk(game);
  const woke = game.act('wake_001', 'wake');
  assert.match(text(woke), /three short tones, and one long/);
  assert.match(text(woke), /Intruder detected/);
  finishTalk(game);
  assert.equal(game.state.stalker.active, true);
  assert.equal(game.state.stalker.room, 'b1_landing');
  return game;
}

test('chapter 3: Daniel reveals he sent the signal and did not know about Emily', () => {
  const game = createGame({ content, bus: createEventBus() });
  game.newGame();
  Object.assign(game.state.flags, { daniel_contacted: true, told_daniel_emily: true });
  game.state.chapter = 2;
  game.state.ended = { chapter: 2 };
  game.startNextChapter();
  const t = text(choose(game, 'Did you know they had Emily'));
  assert.match(t, /They told me she resigned/);
  finishTalk(game);
  const woke = game.act('wake_001', 'wake') ;
  const all = text(woke) + finishTalk(game);
  assert.match(all, /That was 001’s heartbeat/);
});

test('chapter 3: listen tracks 001 by direction, and you are warned before it walks in', () => {
  const game = startChapter3();
  const heard = text(game.listen());
  assert.match(heard, /001 is close: in the elevator landing, on your right, to the east/);
  // Wander between rooms until it comes toward the player: a warning must come first.
  game.go('east'); // into the landing... 001 has moved on by now
  let log = '';
  for (let i = 0; i < 30 && game.view().mode !== 'dialogue'; i++) log += text(game.look());
  assert.equal(game.state.dialogue.active?.id, 'encounter_001');
  assert.match(log, /It is coming toward you/);
});

test('chapter 3: caught once hurts, caught again kills, and the checkpoint brings you back', () => {
  const game = startChapter3();
  const checkpoint = game.snapshot();
  const meet = () => {
    for (let i = 0; i < 40 && game.view().mode !== 'dialogue'; i++) game.look();
    assert.equal(game.state.dialogue.active?.id, 'encounter_001');
  };
  // Standing still in plain sight: the third time, it is not fooled.
  game.state.stalker.alert = 5;
  meet();
  choose(game, 'Hold completely still');
  assert.ok(game.state.flags.injured);
  assert.equal(game.view().mode, 'explore');
  game.state.stalker.alert = 5;
  meet();
  choose(game, 'Hold completely still');
  assert.equal(game.view().mode, 'gameOver');
  assert.match(game.view().gameOver.text, /three short, one long/);

  const g2 = createGame({ content, bus: createEventBus() });
  g2.loadState(checkpoint);
  assert.equal(g2.view().mode, 'explore');
  assert.ok(!g2.state.flags.injured);
});

test('chapter 3: hiding works, the ward heals you, and kindness makes it hesitate', () => {
  const game = startChapter3({ readProposal: true });
  game.state.flags.injured = true;
  game.go('east'); // landing
  game.go('east'); // medical ward
  game.act('supplies', 'treat');
  assert.ok(!game.state.flags.injured);
  for (let i = 0; i < 40 && game.view().mode !== 'dialogue'; i++) game.look();
  if (game.state.dialogue.active?.id === 'daniel_001_at_emily') finishTalk(game);
  for (let i = 0; i < 40 && game.state.dialogue.active?.id !== 'encounter_001'; i++) { finishTalk(game); game.look(); }
  const t = text(choose(game, 'kind'));
  assert.match(t, /Kindness is not a requirement/);
  assert.equal(game.state.stats.secretsFound, 1);
  assert.notEqual(game.state.stalker.room, game.state.location);
  for (let i = 0; i < 40 && game.state.dialogue.active?.id !== 'encounter_001'; i++) { finishTalk(game); game.look(); }
  choose(game, 'Slide under a bed sheet');
  assert.equal(game.view().mode, 'explore');
});

test('chapter 3: take the key while 001 recharges and ride the lift down', () => {
  const game = startChapter3();
  // Wait in storage for 001 to finish its round and dock.
  let log = '';
  for (let i = 0; i < 60 && !game.view().objects.some((o) => o.id === 'proto_001'); i++) {
    log += text(game.look());
    if (game.view().mode === 'dialogue') log += text(choose(game, 'Hide behind the shelving'));
  }
  assert.match(log, /docked to recharge/);
  const k = game.act('proto_001', 'take_key');
  assert.ok(game.state.inventory.includes('key_001'));
  assert.ok(k.checkpoint);
  game.act('freight_lift', 'ride');
  assert.equal(game.view().mode, 'chapterEnd');
  assert.equal(game.view().ended.title, 'End of Chapter 3');
});
