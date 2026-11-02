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

// As if Part Two, Chapter 1 just ended.
function startP2C2({ ending = 'romance', flags = {} } = {}) {
  const game = createGame({ content, bus: createEventBus() });
  game.newGame();
  const s = game.state;
  for (const t of content.triggers) if (!t.id.startsWith('p2c2')) s.firedTriggers[t.id] = true;
  Object.assign(s.flags, { daniel_contacted: true, daniel_named: true, p2_started: true, emily_awake: true, [`ending_${ending}`]: true, ...flags });
  Object.assign(s.ward, { active: false, emilyAlive: true });
  s.location = 'holding_cell';
  s.chapter = 8;
  s.ended = { chapter: 8, title: 'End of Part Two, Chapter 1' };
  const beat = text(game.startNextChapter()) + finishTalk(game);
  assert.equal(game.state.chapter, 9);
  assert.equal(game.state.location, 'street');
  return { game, beat };
}

test('Part Two Ch2: bail depends on who you called', () => {
  assert.match(startP2C2({ flags: { help_emily: true } }).beat, /Emily pays it/);
  assert.match(startP2C2({ flags: { help_daniel: true } }).beat, /Daniel pays it/);
  assert.match(startP2C2({ flags: { lawyer_called: true } }).beat, /four minutes flat/);
});

test('Part Two Ch2: meet Sarah, gather witnesses, Emily teases you, and the chapter ends', () => {
  const { game } = startP2C2({ flags: { help_emily: true, marcus_arrested: true } });
  game.go('north');
  game.act('okafor', 'talk');
  finishTalk(game);
  assert.equal(game.state.objectives.find_witnesses, 'active');
  game.go('south');

  game.go('east');
  assert.equal(game.state.dialogue.active?.id, 'sarah_meet');
  const meet = text(choose(game, 'Who are you')) + finishTalk(game);
  assert.match(meet, /Sarah Quinn/);
  assert.match(meet, /You were the only one who quit/);
  choose(game, 'How do you know all that');
  finishTalk(game);
  assert.ok(game.state.flags.sarah_met);
  game.go('west');

  game.go('west');
  game.act('ana', 'talk');
  choose(game, 'tell a court');
  finishTalk(game);
  game.act('priya', 'talk');
  choose(game, 'You owe me');
  finishTalk(game);
  assert.ok(game.state.flags.priya_refused);
  game.act('theo', 'talk');
  choose(game, 'I was framed');
  choose(game, 'answered that radio');
  finishTalk(game);
  assert.ok(game.state.flags.witness_theo);
  game.go('east');

  game.go('emily');
  game.act('emily', 'talk');
  const tease = finishTalk(game);
  assert.match(tease, /You thanked the wrong person for it/);
  assert.match(tease, /whether you took sugar/);
  game.go('out');

  game.go('jail');
  game.act('marcus', 'talk');
  finishTalk(game);
  assert.ok(game.state.flags.knows_pryce_motive);
  game.go('out');

  game.go('north');
  game.act('okafor', 'talk');
  const end = finishTalk(game);
  assert.match(end, /The address is the courthouse/);
  choose(game, 'I’m noticing now');
  finishTalk(game);
  assert.ok(game.state.flags.sarah_spark);
  assert.equal(game.view().mode, 'chapterEnd');
  assert.equal(game.view().ended.title, 'End of Part Two, Chapter 2');
});

test('Part Two Ch2: Okafor will not move on with too few witnesses', () => {
  const { game } = startP2C2({ ending: 'abandon', flags: { lawyer_called: true } });
  game.state.flags.emily_awake = false;
  game.go('north');
  game.act('okafor', 'talk');
  finishTalk(game);
  assert.match(text(game.act('okafor', 'talk')), /Not enough people yet/);
  game.go('south');
  game.go('west');
  game.act('ana', 'talk');
  choose(game, 'tell a court');
  finishTalk(game);
  game.act('priya', 'talk');
  choose(game, 'You don’t owe me');
  finishTalk(game);
  game.go('east');
  game.go('north');
  const last = text(game.act('okafor', 'talk'));
  assert.match(last, /still don.t know who else knew that sound/);
});
