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

function startVerdict({ jury = 14, ending = 'romance', flags = {} } = {}) {
  const game = createGame({ content, bus: createEventBus() });
  game.newGame();
  const s = game.state;
  for (const t of content.triggers) s.firedTriggers[t.id] = true;
  Object.assign(s.flags, { daniel_named: true, p2_started: true, emily_awake: true, sarah_named: true, [`ending_${ending}`]: true, ...flags });
  s.counters = { jury };
  s.location = 'courtroom';
  s.chapter = 10;
  s.ended = { chapter: 10, title: 'End of Part Two, Chapter 3' };
  const beat = text(game.startNextChapter()) + finishTalk(game);
  assert.equal(game.state.chapter, 11);
  return { game, beat };
}

function meetVoss(game) {
  game.go('down');
  assert.equal(game.state.location, 'evidence_room');
  game.act('radio', 'examine');
  const a = text(game.act('terminal', 'speak'));
  const b = text(choose(game, 'Who are you'));
  const c = finishTalk(game);
  return a + b + c;
}

test('a strong trial: not guilty, then the voice in the basement', () => {
  const { game, beat } = startVerdict({ jury: 14, flags: { sarah_spark: true } });
  assert.match(beat, /we find the defendant not guilty/);
  assert.match(beat, /She hugs you/);
  assert.ok(game.state.flags.acquitted);
  const t = meetVoss(game);
  assert.match(t, /Helena Voss/);
  assert.match(t, /Daniel was the rehearsal/);
  assert.match(t, /Daniel thinks he is home/);
  choose(game, 'What do you want');
  choose(game, 'not to make a deal');
  finishTalk(game);
  assert.equal(game.view().mode, 'chapterEnd');
  assert.equal(game.view().ended.title, 'End of Part Two, Chapter 4');
});

test('a weak trial: guilty, until Ruiz walks in with the radio', () => {
  const { game, beat } = startVerdict({ jury: 3, ending: 'abandon' });
  assert.match(beat, /we find the defendant guilty/);
  assert.match(beat, /this is the rest of my life/i);
  assert.match(beat, /I arrested Victor Lane/);
  assert.ok(game.state.flags.saved_by_ruiz);
  const t = meetVoss(game);
  assert.match(t, /His body is still breathing in containment/);
});
