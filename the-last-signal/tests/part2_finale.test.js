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

function startFinale(flags = {}) {
  const game = createGame({ content, bus: createEventBus() });
  game.newGame();
  const s = game.state;
  for (const t of content.triggers) if (!t.id.startsWith('p2c5')) s.firedTriggers[t.id] = true;
  Object.assign(s.flags, {
    daniel_named: true, power_on: true, ch4_started: true, sarah_named: true, voss_named: true, ending_romance: true, free: true, ...flags,
  });
  s.location = 'evidence_room';
  s.chapter = 11;
  s.ended = { chapter: 11, title: 'End of Part Two, Chapter 4' };
  const beat = text(game.startNextChapter());
  assert.equal(game.state.chapter, 12);
  assert.equal(game.state.location, 'b1_landing');
  const reply = text(choose(game, 'I can hear you'));
  return { game, beat: beat + reply + finishTalk(game) };
}

// From the landing to the switching room: storage, freight lift, hall, monitoring.
function walkDown(game, onHall) {
  game.go('west');
  game.go('down');
  game.go('north');
  if (game.view().mode === 'dialogue') onHall(game);
  game.go('east');
  game.go('east');
  assert.equal(game.state.location, 'switching_room');
}

test('Found You: resist the fake voices, check it is really Sarah, let her make you blush, save Daniel', () => {
  const { game, beat } = startFinale();
  assert.match(beat, /She’s in the room with me/);
  assert.ok(game.state.flags.corridor_sealed);
  assert.match(text(game.go('north')), /security shutter/);
  game.roomAction('radio_sarah');
  assert.match(text(choose(game, 'only thing keeping me sane')), /apologising to the floor/);
  game.roomAction('radio_sarah');
  assert.match(text(choose(game, 'something only you would know')), /You thanked Priya/);
  assert.ok(game.state.flags.verified_sarah);
  game.look();
  game.look();
  assert.equal(game.state.dialogue.active?.id, 'fake_sarah');
  choose(game, 'Check your radio first');
  finishTalk(game);
  walkDown(game, (g) => assert.equal(g.state.dialogue.active?.id, 'fake_daniel'));
  game.act('panel', 'use');
  choose(game, 'saving Daniel');
  const end = finishTalk(game);
  assert.match(end, /You’re blushing, she says/);
  assert.equal(game.view().ended.ending, 'found_you');
  assert.ok(game.state.flags.saved_daniel_copy);
});

test('Clean Line: Daniel saved, but no romance yet', () => {
  const { game } = startFinale();
  game.roomAction('radio_sarah');
  choose(game, 'something only you would know');
  game.look(); game.look();
  choose(game, 'Check your radio first');
  finishTalk(game);
  walkDown(game, () => {});
  game.act('panel', 'use');
  choose(game, 'saving Daniel');
  finishTalk(game);
  assert.equal(game.view().ended.ending, 'clean_line');
});

test('Scorched Wire: if you never checked it was Sarah, you cannot trust her instructions', () => {
  const { game } = startFinale();
  game.look(); game.look();
  choose(game, 'Check your radio first');
  finishTalk(game);
  walkDown(game, (g) => choose(g, 'Ignore it'));
  game.act('panel', 'use');
  const t = text(choose(game, 'saving Daniel'));
  assert.match(t, /you cannot be sure/);
  choose(game, 'Pull the big lever');
  finishTalk(game);
  assert.equal(game.view().ended.ending, 'scorched_wire');
});

test('Her Voice: follow both fake voices and you are too late', () => {
  const { game } = startFinale();
  game.look(); game.look();
  assert.match(text(choose(game, 'Run to the medical ward')), /Daniel’s exact voice/);
  walkDown(game, (g) => choose(g, 'Run to containment'));
  assert.equal(game.state.counters.lost_time, 2);
  game.act('panel', 'use');
  finishTalk(game);
  assert.equal(game.view().ended.ending, 'her_voice');
});
