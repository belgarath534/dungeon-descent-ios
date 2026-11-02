import { test } from 'node:test';
import assert from 'node:assert/strict';

import { createGame } from '../www/js/core/game.js';
import { createEventBus } from '../www/js/core/events.js';
import { evaluate } from '../www/js/core/conditions.js';
import { createSaveManager } from '../www/js/core/save.js';
import { createInitialState } from '../www/js/core/state.js';
import { validateContent } from '../www/js/core/validate.js';
import { content } from '../www/js/content/index.js';

function memoryStorage() {
  const m = new Map();
  return {
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
    removeItem: (k) => m.delete(k),
  };
}

function newGame() {
  const bus = createEventBus();
  const events = [];
  bus.on('trust:changed', (e) => events.push(e));
  const game = createGame({ content, bus });
  game.newGame();
  return { game, events };
}

const text = (beat) => beat.lines.map((l) => l.text).join('\n');
const choose = (game, fragment) => {
  const c = game.view().choices.find((x) => x.text.includes(fragment));
  assert.ok(c, `choice containing "${fragment}" not offered; have: ${game.view().choices.map((x) => x.text).join(' | ')}`);
  return game.choose(c.index);
};
const continueAll = (game) => {
  // Click "Continue" until the conversation offers a real choice or ends.
  for (let i = 0; i < 20; i++) {
    const v = game.view();
    if (v.mode !== 'dialogue' || v.choices.length !== 1 || v.choices[0].index !== -1) return;
    game.choose(-1);
  }
};

test('content passes validation', () => {
  const { game } = newGame();
  const problems = validateContent(content, game.ctx.effects.names());
  assert.deepEqual(problems, []);
});

test('conditions', () => {
  const s = createInitialState({ startRoom: 'patrol_car' });
  s.flags.a = true;
  s.inventory.push('flashlight');
  s.trust.daniel.value = 15;
  assert.equal(evaluate(null, s), true);
  assert.equal(evaluate({ flag: 'a' }, s), true);
  assert.equal(evaluate({ flag: ['a', 'b'] }, s), false);
  assert.equal(evaluate({ notFlag: 'b', has: 'flashlight' }, s), true);
  assert.equal(evaluate({ any: [{ flag: 'b' }, { trustAtLeast: 10 }] }, s), true);
  assert.equal(evaluate({ not: { trustAtLeast: 10 } }, s), false);
  assert.equal(evaluate({ at: 'patrol_car' }, s), true);
  assert.throws(() => evaluate({ nonsense: 1 }, s), /Unknown condition/);
});

test('corridor needs a light', () => {
  const { game } = newGame();
  game.go('out');
  game.go('north');
  const beat = game.go('north');
  assert.match(text(beat), /completely black/);
  assert.equal(game.state.location, 'reception');
  assert.ok(game.view().exits.find((e) => e.id === 'north').lockedKnown);
});

test('honest path: Daniel opens the elevator and the chapter ends', () => {
  const { game, events } = newGame();
  game.act('glovebox', 'open');
  assert.ok(game.state.inventory.includes('flashlight'));
  game.go('out');
  game.go('north');

  const beat = game.act('front_desk', 'take_radio');
  assert.match(text(beat), /You picked it up/);
  assert.equal(game.view().mode, 'dialogue');
  assert.equal(beat.lines.find((l) => l.kind === 'speech').speaker, 'Unknown voice, over the radio');

  choose(game, 'Police');
  continueAll(game);
  choose(game, 'on it');
  continueAll(game);
  assert.equal(game.view().mode, 'explore');
  assert.equal(game.state.objectives.restore_power, 'active');
  assert.equal(game.state.trust.daniel.value, 5);
  assert.equal(events.length, 1);

  game.go('east');
  game.act('breaker', 'restore');
  // Power dialogue starts automatically through the speakers.
  assert.equal(game.view().mode, 'dialogue');
  choose(game, 'here to help');
  continueAll(game);
  assert.equal(game.state.objectives.find_way_down, 'active');

  // Walk around until dispatch checks in (scheduled 12 minutes after contact).
  let guard = 0;
  while (game.view().mode !== 'dialogue' && guard++ < 30) game.look();
  assert.equal(game.state.dialogue.active.id, 'dispatch_checkin');
  choose(game, 'On scene');
  continueAll(game);
  assert.equal(game.state.trust.daniel.value, 13);

  game.roomAction('radio_daniel');
  choose(game, 'Who are you?');
  assert.ok(game.state.flags.daniel_named);
  continueAll(game);
  choose(game, 'open the elevator');
  assert.ok(game.state.flags.elevator_unlocked);
  continueAll(game);
  choose(game, 'Signing off');

  game.go('west');
  game.go('north');
  game.go('north');
  assert.equal(game.view().mode, 'chapterEnd');
  assert.ok(game.state.flags.chapter_1_complete);

  game.continueAfterChapter();
  assert.equal(game.view().mode, 'explore');
  assert.equal(game.state.location, 'main_corridor');
});

test('lying path: the lie is exposed and the player must find the override card', () => {
  const { game } = newGame();
  game.act('glovebox', 'open');
  game.go('out');
  game.go('north');
  game.act('front_desk', 'take_radio');
  choose(game, 'contractor');
  assert.ok(game.state.trust.daniel.lies.identity);
  continueAll(game);
  choose(game, 'on it');
  continueAll(game);

  game.go('east');
  game.act('breaker', 'restore');
  choose(game, 'Tell me who you are');
  continueAll(game);

  let guard = 0;
  while (game.view().mode !== 'dialogue' && guard++ < 30) game.look();
  choose(game, 'On scene');
  continueAll(game);
  assert.equal(game.state.trust.daniel.lies.identity.exposed, true);
  assert.equal(game.state.trust.daniel.value, -20);

  game.roomAction('radio_daniel');
  choose(game, 'open the elevator');
  assert.ok(!game.state.flags.elevator_unlocked);
  continueAll(game);
  choose(game, 'Signing off');

  // The hidden locker is only revealed by listening.
  assert.ok(!game.objectActions('lockers').some((a) => a.id === 'force'));
  game.listen();
  game.act('lockers', 'force');
  assert.ok(game.state.inventory.includes('override_card'));
  assert.equal(game.state.stats.secretsFound, 1);

  game.go('west');
  game.go('north');
  game.act('elevator_panel', 'swipe');
  continueAll(game); // Daniel reacts to the card
  if (game.view().mode === 'dialogue') game.choose(-1);
  game.go('north');
  assert.equal(game.view().mode, 'chapterEnd');
});

test('reading Daniel’s proposal unlocks guessing his name', () => {
  const { game } = newGame();
  game.act('glovebox', 'open');
  game.go('out');
  game.go('north');
  game.act('front_desk', 'take_radio');
  choose(game, 'Say nothing');
  continueAll(game);
  choose(game, 'on it');
  continueAll(game);
  game.go('north');
  game.go('west');
  game.act('desk', 'read');
  game.markRead('doc_proposal');
  game.roomAction('radio_daniel');
  choose(game, 'Daniel. Is that you?');
  choose(game, 'Lucky guess');
  assert.equal(game.state.trust.daniel.lies.office.exposed, true);
});

test('saves round-trip, survive corruption and resume mid-conversation', () => {
  const storage = memoryStorage();
  const saves = createSaveManager(storage);
  const { game } = newGame();
  game.act('glovebox', 'open');
  game.go('out');
  game.go('north');
  game.act('front_desk', 'take_radio');
  saves.save('1', game.snapshot(), game.saveMeta());
  assert.equal(saves.latest(), '1');

  const loaded = saves.load('1');
  assert.equal(loaded.meta.room, 'Reception lobby');

  const bus = createEventBus();
  const g2 = createGame({ content, bus });
  g2.loadState(loaded.state);
  const beat = g2.resume();
  assert.match(text(beat), /Who sent you/);
  assert.equal(g2.view().mode, 'dialogue');

  storage.setItem('tls.save.2', '{not json');
  assert.equal(saves.load('2'), null);
  assert.equal(saves.list().find((s) => s.slot === '2').corrupt, true);
  assert.equal(saves.load('3'), null);
});
