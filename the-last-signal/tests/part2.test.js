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
    if (!cs.some((c) => c.index === -1)) break;
    out += text(game.choose(-1)) + '\n';
  }
  return out;
}

// A save sitting on a Part One ending screen. `oldSave` mimics saves made
// before endings were stored as flags.
function fromEnding(ending, { emily = true, oldSave = false } = {}) {
  const game = createGame({ content, bus: createEventBus() });
  game.newGame();
  const s = game.state;
  for (const t of content.triggers) if (!t.id.startsWith('p2_')) s.firedTriggers[t.id] = true;
  Object.assign(s.flags, { daniel_contacted: true, ch7_started: true });
  if (emily) s.flags.emily_awake = true;
  Object.assign(s.ward, { active: false, emilyAlive: emily });
  if (!emily) s.flags.emily_dead = true;
  s.inventory.push('facility_radio');
  s.chapter = 7;
  s.ended = { chapter: 7, title: 'Ending', ending };
  if (!oldSave) s.flags[`ending_${ending}`] = true;
  assert.ok(game.hasNextChapter());
  const beat = game.startNextChapter();
  assert.equal(game.state.chapter, 8);
  assert.equal(game.state.location, 'apartment');
  return { game, beat: text(beat) + finishTalk(game) };
}

function untilArrest(game) {
  let t = '';
  for (let i = 0; i < 5 && game.state.dialogue.active?.id !== 'arrest'; i++) t += text(game.look());
  assert.equal(game.state.dialogue.active?.id, 'arrest');
  assert.match(t, /under arrest for the murder of Dr\. Alan Pryce/);
}

test('Part Two opens differently for each Part One ending', () => {
  assert.match(fromEnding('romance').beat, /I love you, Em/);
  assert.match(fromEnding('restored').beat, /On my own legs/);
  assert.match(fromEnding('prototype').beat, /practising soup/);
  assert.match(fromEnding('revenge').beat, /walked out into the rain/);
  assert.match(fromEnding('lost', { emily: false }).beat, /clicks on by itself/);
  assert.match(fromEnding('abandon').beat, /clicks on by itself/);
});

test('Part Two: saves from before this update still get the right opening', () => {
  assert.match(fromEnding('romance', { oldSave: true }).beat, /I love you, Em/);
});

test('Part Two: the romantic route, arrest, alibi, call Emily, the voice in the vent', () => {
  const { game } = fromEnding('romance');
  assert.ok(game.state.flags.p2_love_said);
  untilArrest(game);
  choose(game, 'Is this about the facility');
  const cuffs = text(game.choose(-1));
  assert.equal(game.state.location, 'interview_room');
  assert.match(cuffs, /note with your badge number/);
  assert.ok(game.state.journal.documents.includes('doc_p2_scene'));
  choose(game, 'tell you everything');
  choose(game, 'with Emily and Daniel');
  finishTalk(game);
  choose(game, 'Call Emily');
  finishTalk(game);
  assert.ok(game.state.flags.help_emily);
  assert.equal(game.state.location, 'holding_cell');
  const heard = text(game.listen()) + finishTalk(game);
  assert.match(heard, /You should have left it closed/);
  assert.equal(game.view().mode, 'chapterEnd');
  assert.equal(game.view().ended.title, 'End of Part Two, Chapter 1');
});

test('Part Two: lying to Ruiz gets caught; alone you can only call a lawyer; the vent finds you anyway', () => {
  const { game } = fromEnding('abandon', { emily: false });
  untilArrest(game);
  choose(game, 'Go quietly');
  choose(game, 'never anywhere near');
  assert.ok(game.state.flags.caught_lying_to_ruiz);
  choose(game, 'I want a lawyer');
  finishTalk(game);
  const options = game.view().choices.map((c) => c.text);
  assert.deepEqual(options, ['Call the public defender’s night line']);
  choose(game, 'public defender');
  finishTalk(game);
  // Without listening, the tapping still comes.
  for (let i = 0; i < 8 && game.view().mode !== 'chapterEnd'; i++) { game.look(); finishTalk(game); }
  assert.equal(game.view().mode, 'chapterEnd');
});

test('Part Two: in the revenge ending, Daniel answers his phone', () => {
  const { game } = fromEnding('revenge');
  untilArrest(game);
  choose(game, 'Go quietly');
  choose(game, 'I want a lawyer');
  finishTalk(game);
  const t = text(choose(game, 'number Daniel left you'));
  assert.match(t, /It wasn’t me/);
});
