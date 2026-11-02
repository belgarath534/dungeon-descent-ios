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

// As if Chapter 4 just ended. 001 is switched off here; Chapter 3 tests cover it.
function startChapter5({ emilyAlive = true } = {}) {
  const game = createGame({ content, bus: createEventBus() });
  game.newGame();
  const s = game.state;
  for (const t of content.triggers) s.firedTriggers[t.id] = true;
  Object.assign(s.flags, {
    daniel_contacted: true, power_on: true, elevator_unlocked: true, found_emily: true, saw_001: true,
    ward_door_powered: true, ch3_started: true, woke_001: true, ch4_started: true, saw_body: true,
  });
  if (emilyAlive) Object.assign(s.flags, { emily_awake: true, emily_daniel_talked: true });
  else s.flags.emily_dead = true;
  Object.assign(s.ward, { active: false, location: 'ward', emilyAlive, warned: {} });
  s.trust.daniel.value = 40;
  s.inventory.push('facility_radio', 'key_001', 'flashlight');
  s.chapter = 4;
  s.ended = { chapter: 4 };
  const beat = game.startNextChapter();
  assert.equal(game.state.chapter, 5);
  assert.equal(game.state.location, 'medical_ward');
  return { game, beat };
}

function climbAndOpen(game) {
  game.go('west'); // landing
  game.go('west'); // storage
  game.act('tool_crate', 'search');
  assert.ok(game.state.inventory.includes('bolt_cutters'));
  game.go('east');
  game.act('elevator_controls', 'trick');
  game.go('up');
  assert.equal(game.state.location, 'main_corridor');
  game.act('chain', 'cut');
  assert.equal(game.state.dialogue.active?.id, 'ch5_chain');
}

test('chapter 5: Emily knows the way, confides in you, and sends her lanyard', () => {
  const { game, beat } = startChapter5();
  assert.match(text(beat), /He won’t tell you where he is/);
  choose(game, 'Do you know');
  const way = text(choose(game, 'What is he'));
  assert.match(way, /eleven years/);
  finishTalk(game);
  assert.ok(game.state.flags.emily_told_way);
  assert.ok(game.state.flags.emily_confided);
  assert.ok(game.state.inventory.includes('emily_badge'));

  climbAndOpen(game);
  const t = text(choose(game, 'Emily asked me'));
  assert.match(t, /What did she send/);
  finishTalk(game);
  game.go('stairs');
  assert.equal(game.state.location, 'stairwell');
  const heard = text(game.listen());
  assert.match(heard, /someone humming/);
  assert.equal(game.state.stats.secretsFound, 1);
  game.act('footprints', 'examine');

  game.act('isolation_door', 'tap');
  choose(game, 'Not yet');
  assert.equal(game.view().mode, 'explore', 'you can step back from the door');
  game.act('isolation_door', 'tap');
  const end = text(choose(game, 'Open the door'));
  assert.match(end, /You came anyway/);
  assert.equal(game.view().mode, 'chapterEnd');
  assert.equal(game.view().ended.title, 'End of Chapter 5');
});

test('chapter 5: without Emily, the board’s own papers show the way', () => {
  const { game, beat } = startChapter5({ emilyAlive: false });
  assert.match(text(beat), /capsule is silent/);
  finishTalk(game);
  // The elevator trick is unknown until the isolation order is read.
  game.go('west');
  assert.ok(!game.objectActions('elevator_controls').some((a) => a.id === 'trick'));
  game.go('west');
  game.go('down');
  assert.equal(game.state.location, 'b2_lift');
  game.go('north');
  game.go('west');
  game.act('board_safe', 'read');
  assert.ok(game.state.journal.documents.includes('doc_isolation_order'));
  game.go('east');
  game.go('south');
  game.go('up'); // freight lift back to storage
  game.act('tool_crate', 'search');
  game.go('east');
  game.act('elevator_controls', 'trick');
  game.go('up');
  game.act('chain', 'cut');
  choose(game, 'Whether you want me to or not');
  finishTalk(game);
  assert.ok(game.state.flags.told_coming);
  game.go('stairs');
  game.act('isolation_door', 'tap');
  choose(game, 'Open the door');
  assert.equal(game.view().mode, 'chapterEnd');
});

test('chapter 5: lying about going down is recorded', () => {
  const { game } = startChapter5();
  finishTalk(game);
  climbAndOpen(game);
  choose(game, 'only checking');
  assert.ok(game.state.trust.daniel.lies.coming);
});
