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
const jury = (game) => game.state.counters.jury;

function startTrial(flags = {}) {
  const game = createGame({ content, bus: createEventBus() });
  game.newGame();
  const s = game.state;
  for (const t of content.triggers) if (!t.id.startsWith('p2c3')) s.firedTriggers[t.id] = true;
  Object.assign(s.flags, { daniel_named: true, p2_started: true, p2c2_started: true, emily_awake: true, ending_romance: true, sarah_named: true, ...flags });
  s.journal.documents.push('doc_p2_scene');
  s.location = 'okafor_office';
  s.chapter = 9;
  s.ended = { chapter: 9, title: 'End of Part Two, Chapter 2' };
  const beat = text(game.startNextChapter()) + finishTalk(game);
  assert.equal(game.state.chapter, 10);
  assert.equal(game.state.location, 'courtroom');
  return { game, beat };
}

test('the trial, done well: sharp questions, Lane exposed, every witness, testimony, and the voice in the dark', () => {
  const { game, beat } = startTrial({
    knows_early_tip: true, went_quietly: true,
    witness_emily: true, witness_daniel: true, witness_marcus: true, witness_theo: true, witness_sarah: true, witness_ana: true,
  });
  assert.match(beat, /The People against the accused/);
  assert.match(text(choose(game, 'When did the anonymous tip')), /Eight hours before the body was found/);
  choose(game, 'Where is my own police radio');
  choose(game, 'Did I resist arrest');
  choose(game, 'No further questions');
  const exposed = text(choose(game, 'what did you do for a living')) + finishTalk(game);
  assert.match(exposed, /That’s the man who answered the number/);
  assert.ok(game.state.flags.in_recess);

  game.go('out');
  game.act('sarah', 'talk');
  assert.ok(game.state.flags.evidence_room_lead);
  game.go('in');
  assert.equal(game.state.dialogue.active?.id, 'trial_defence');
  for (const w of ['Emily', 'Daniel', 'Marcus', 'Theo', 'Sarah', 'Ana']) {
    const t = text(choose(game, `Call ${w === 'Theo' ? 'Theo' : w === 'Emily' ? 'Dr. Emily' : w === 'Sarah' ? 'Sarah Quinn' : w === 'Marcus' ? 'Marcus Hale' : w}`));
    assert.ok(t.length > 40, `${w} actually testifies`);
  }
  choose(game, 'The defence rests');
  choose(game, 'I’ll testify');
  choose(game, 'I answered the call');
  choose(game, 'I never met him');
  choose(game, 'someone who did know him');
  choose(game, 'Ask anyone in this room');
  const end = text(choose(game, 'Let my people speak for me'));
  assert.match(end + finishTalk(game), /Including him/);
  assert.equal(game.view().mode, 'chapterEnd');
  assert.ok(jury(game) >= 12, `jury ${jury(game)}`);
});

test('the trial, done badly: a caught lie, no witnesses for Lane, and a jury that turns away', () => {
  const { game, beat } = startTrial({ caught_lying_to_ruiz: true, witness_ana: true, witness_priya: true });
  assert.match(beat, /You will see the tape/);
  choose(game, 'No further questions');
  assert.ok(!game.view().choices.some((c) => c.text.includes('living')), 'without Theo, you cannot expose Lane');
  choose(game, 'No questions');
  game.go('out');
  game.go('in');
  choose(game, 'Call Ana');
  choose(game, 'The defence rests');
  choose(game, 'I’ll testify');
  choose(game, 'I answered the call');
  choose(game, 'I misspoke');
  choose(game, 'I never met him');
  choose(game, 'I don’t know');
  choose(game, 'No.');
  choose(game, 'Tell them about the signal');
  finishTalk(game);
  assert.equal(game.view().mode, 'chapterEnd');
  assert.ok(jury(game) < 6, `jury ${jury(game)}`);
});
