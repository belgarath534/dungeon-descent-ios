import { test } from 'node:test';
import assert from 'node:assert/strict';

import { createGame } from '../www/js/core/game.js';
import { createEventBus } from '../www/js/core/events.js';
import { content } from '../www/js/content/index.js';

const text = (beat) => beat.lines.map((l) => l.text).join('\n');

function choose(game, fragment) {
  const c = game.view().choices.find((x) => x.text.includes(fragment));
  assert.ok(c, `no choice "${fragment}"; have: ${game.view().choices.map((x) => x.text).join(' | ')}`);
  return game.choose(c.index);
}

// Finish whatever conversation is running: Continue/End where offered,
// otherwise the first reply. Returns all text produced.
function finishTalk(game) {
  let out = '';
  for (let i = 0; i < 30 && game.view().mode === 'dialogue'; i++) {
    const cs = game.view().choices;
    out += text(game.choose((cs.find((c) => c.index === -1) || cs[0]).index)) + '\n';
  }
  return out;
}

// Plays Chapter 1 the honest way and starts Chapter 2.
function startChapter2() {
  const game = createGame({ content, bus: createEventBus() });
  game.newGame();
  game.act('glovebox', 'open');
  game.go('out');
  game.go('north');
  game.act('front_desk', 'take_radio');
  choose(game, 'Police');
  finishTalk(game);
  game.go('east');
  game.act('breaker', 'restore');
  choose(game, 'here to help');
  finishTalk(game);
  for (let i = 0; i < 30 && game.view().mode !== 'dialogue'; i++) game.look();
  choose(game, 'On scene');
  finishTalk(game);
  game.roomAction('radio_daniel');
  choose(game, 'open the elevator');
  game.choose(-1);
  choose(game, 'Signing off');
  game.go('west');
  game.go('north');
  game.go('north');
  assert.equal(game.view().mode, 'chapterEnd');
  assert.ok(game.hasNextChapter());
  const beat = game.startNextChapter();
  assert.match(text(beat), /Sublevel one/);
  assert.equal(game.state.chapter, 2);
  finishTalk(game);
  return game;
}

test('chapter 2, honest path: Emily is saved and Daniel asks to wake 001', () => {
  const game = startChapter2();
  const trustBefore = game.state.trust.daniel.value;
  game.go('north');
  game.go('north');
  assert.equal(game.state.location, 'preservation_lab');

  const found = game.act('capsule', 'examine');
  assert.match(text(found), /CARTER, E\. She is alive/);
  assert.equal(game.state.ward.active, true);
  game.act('terminal', 'read');
  game.act('terminal', 'send');
  game.act('capsule', 'clamps');
  assert.ok(!game.objectActions('capsule').some((a) => a.id === 'move'), 'cannot move before the ward has power');

  // Leaving the lab: Daniel asks what you found.
  game.go('south');
  assert.equal(game.state.dialogue.active.id, 'daniel_found_emily');
  choose(game, 'Emily Carter');
  finishTalk(game);
  assert.ok(game.state.flags.told_daniel_emily);
  assert.ok(game.state.trust.daniel.value > trustBefore);

  game.go('west');
  finishTalk(game); // "Don't stay in there long."
  game.act('workbench', 'take_cell');
  game.go('east');
  game.go('south');
  game.act('ward_panel', 'insert');
  finishTalk(game);
  assert.ok(game.state.flags.ward_door_powered);
  game.go('west');
  game.act('rack', 'take');
  game.act('tarp', 'examine');
  finishTalk(game);
  game.go('east');
  game.go('north');
  game.go('north');
  finishTalk(game);
  game.act('capsule', 'move');
  finishTalk(game);
  assert.equal(game.state.location, 'medical_ward');
  assert.equal(game.state.ward.location, 'ward');

  game.act('power_bay', 'insert');
  game.act('emily', 'check');
  assert.ok(game.state.ward.stability > 95, 'checking on her restores her');
  assert.equal(game.state.dialogue.active.id, 'daniel_001_request');
  choose(game, 'wake it');
  finishTalk(game);
  assert.equal(game.view().mode, 'chapterEnd');
  assert.ok(game.state.flags.agreed_activate_001);
  assert.ok(game.state.ward.emilyAlive);
  assert.equal(game.hasNextChapter(), false);
});

test('chapter 2: lying about Emily is exposed by her alarm on the radio', () => {
  const game = startChapter2();
  game.go('north');
  game.go('north');
  game.act('capsule', 'examine');
  game.go('south');
  choose(game, 'Old equipment');
  finishTalk(game);
  assert.ok(game.state.trust.daniel.lies.emily);
  assert.equal(game.state.trust.daniel.lies.emily.exposed, false);

  // The quiet 50 percent chirp is not enough for Daniel to hear.
  for (let i = 0; i < 12; i++) game.look();
  finishTalk(game);
  assert.ok(game.state.ward.power < 50);
  assert.equal(game.state.trust.daniel.lies.emily.exposed, false);

  // Wait for her power to fall to 25 percent: the alarm goes over the radio.
  let heard = '';
  for (let i = 0; i < 40 && !game.state.trust.daniel.lies.emily.exposed; i++) {
    heard += text(game.look());
    heard += finishTalk(game);
  }
  assert.match(heard, /Radio alarm/);
  assert.match(heard, /That’s what you said/);
  assert.equal(game.state.trust.daniel.lies.emily.exposed, true);
});

test('chapter 2: neglecting Emily kills her, with warnings first', () => {
  const game = startChapter2();
  game.go('north');
  game.go('north');
  game.act('capsule', 'examine');
  let log = '';
  for (let i = 0; i < 120 && game.state.ward.emilyAlive; i++) log += text(game.look());
  assert.equal(game.state.ward.emilyAlive, false);
  assert.ok(game.state.flags.emily_dead);
  // Every warning came before the end.
  const order = ['power is at 25', 'almost gone', 'power has run out', 'getting worse', 'Emily is critical', 'flatlined'];
  let at = -1;
  for (const w of ['power is at 25', 'almost gone', 'power has run out']) {
    const i = log.indexOf(w);
    assert.ok(i > at, `warning "${w}" missing or out of order`);
    at = i;
  }
  for (const w of order) assert.ok(log.includes(w), `missing "${w}"`);
  assert.ok(log.indexOf('Emily is critical') < log.indexOf('flatlined'));

  // The chapter still ends, and Daniel's lines change.
  game.go('south');
  finishTalk(game);
  game.go('south');
  game.go('west');
  const beat = game.act('tarp', 'examine');
  assert.match(text(beat) + finishTalk(game), /heard her monitor stop/);
  assert.equal(game.state.objectives.save_emily, 'failed');
  assert.equal(game.state.objectives.keep_emily_alive, undefined);
});

test('saves from chapter 1 (no ward data) still load and play chapter 2', () => {
  const game = startChapter2();
  const snap = game.snapshot();
  delete snap.ward;
  const g2 = createGame({ content, bus: createEventBus() });
  g2.loadState(snap);
  g2.go('north');
  g2.go('north');
  g2.act('capsule', 'examine');
  assert.equal(g2.state.ward.active, true);
});
