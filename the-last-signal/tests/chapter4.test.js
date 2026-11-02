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

// A state as if Chapter 3 just ended: Emily asleep in the ward, 001 on patrol.
function startChapter4({ trust = 30, toldEmily = true, liedEmily = false, emilyAlive = true } = {}) {
  const game = createGame({ content, bus: createEventBus() });
  game.newGame();
  const s = game.state;
  for (const t of content.triggers) if (!['ch4_end', 'ch4_emily_died', 'encounter_001'].includes(t.id)) s.firedTriggers[t.id] = true;
  Object.assign(s.flags, {
    daniel_contacted: true, power_on: true, found_emily: true, saw_001: true, ward_door_powered: true,
    ch3_started: true, woke_001: true, took_001_key: true, checked_emily: true, emily_conversation_done: true,
  });
  if (toldEmily) s.flags.told_daniel_emily = true;
  if (liedEmily) s.trust.daniel.lies.emily = { exposed: false, at: 0, about: 'finding Emily' };
  s.trust.daniel.value = trust;
  s.inventory.push('facility_radio', 'key_001');
  s.objectives.keep_emily_alive = 'active';
  Object.assign(s.ward, { active: emilyAlive, location: 'ward', power: 80, stability: 90, emilyAlive, warned: {} });
  if (!emilyAlive) s.flags.emily_dead = true;
  // 001 is far away on its route, between labs.
  Object.assign(s.stalker, { active: true, room: 'preservation_lab', step: 3, nextMoveAt: 999, rechargeUntil: 0 });
  s.chapter = 3;
  s.ended = { chapter: 3 };
  const beat = game.startNextChapter();
  assert.equal(game.state.chapter, 4);
  assert.equal(game.state.location, 'b2_lift');
  assert.ok(beat.checkpoint);
  return { game, beat };
}

test('chapter 4: a trusted Daniel offers to watch Emily, and her decline slows', () => {
  const { game, beat } = startChapter4({ trust: 30 });
  assert.match(text(beat), /They never turned anything off/);

  game.choose(-1);
  assert.match(game.view().choices.map((c) => c.text).join('|'), /Watch her for me/);
  choose(game, 'Watch her for me');
  finishTalk(game);
  assert.ok(game.state.flags.daniel_watching);
  const before = game.state.ward.stability;
  for (let i = 0; i < 20; i++) game.look();
  const watchedDrop = before - game.state.ward.stability;
  assert.ok(watchedDrop < 6, `slow decline while watched (dropped ${watchedDrop})`);
});

test('chapter 4: no offer if Daniel does not trust you or does not know about Emily', () => {
  for (const opts of [{ trust: 5 }, { toldEmily: false, liedEmily: true }]) {
    const { game } = startChapter4(opts);
    const t = finishTalk(game);
    assert.doesNotMatch(t, /watch her while you work/);
    assert.ok(!game.state.flags.daniel_watching);
  }
});

test('chapter 4: the monitoring link powers the ward and gives a partial check', () => {
  const { game } = startChapter4({ trust: 5 });
  finishTalk(game);
  game.go('north');
  game.go('east');
  assert.equal(game.state.location, 'monitoring');
  game.act('med_link', 'mains');
  assert.ok(game.state.flags.ward_mains);
  const power = game.state.ward.power;
  for (let i = 0; i < 10; i++) game.look();
  assert.equal(game.state.ward.power, power, 'power holds on mains');
  game.state.ward.stability = 30;
  game.act('med_link', 'remote_check');
  assert.ok(game.state.ward.stability >= 68 && game.state.ward.stability <= 70, 'remote check only reaches about 70');
});

test('chapter 4: codes, wake Emily, Emily and Daniel talk, find the body, chapter ends', () => {
  const { game } = startChapter4({ trust: 30 });
  finishTalk(game);
  game.go('north');
  game.go('west');
  game.act('cabinets', 'search');
  assert.ok(game.state.inventory.includes('revival_codes'));
  game.listen();
  game.act('archive_core', 'open');
  assert.ok(game.state.inventory.includes('core_001'));

  game.go('east');
  game.go('north');
  const body = game.act('bed', 'examine');
  assert.match(text(body), /It is Daniel/);
  choose(game, 'Machines are keeping it alive');
  const rest = finishTalk(game);
  assert.match(rest, /The rest of me is somewhere else/);
  assert.equal(game.view().mode, 'explore', 'chapter does not end before Emily and Daniel talk');

  game.state.stalker.active = false; // keep 001 out of this test
  game.go('south');
  game.go('south');
  game.go('up');
  assert.equal(game.state.location, 'storage');
  game.go('east');
  game.go('east');
  assert.equal(game.state.location, 'medical_ward');
  const trustBefore = game.state.trust.daniel.value;
  game.act('revive', 'enter');
  assert.ok(game.state.flags.emily_awake);
  assert.equal(game.state.ward.active, false);
  choose(game, 'safe');
  game.choose(-1);
  choose(game, 'alive. In a way');
  const call = text(choose(game, 'call Daniel'));
  assert.match(call, /Em\?/);
  const conv = finishTalk(game);
  assert.match(conv, /They told me you’d left/);
  assert.match(conv, /I can’t tell you that yet/);
  assert.ok(game.state.flags.emily_daniel_talked);
  assert.ok(game.state.trust.daniel.value >= trustBefore + 15);
  assert.equal(game.view().mode, 'chapterEnd');
  assert.equal(game.view().ended.title, 'End of Chapter 4');
});

test('chapter 4: a hidden lie about Emily comes out when she speaks to Daniel', () => {
  const { game } = startChapter4({ trust: 30, toldEmily: false, liedEmily: true });
  finishTalk(game);
  game.state.stalker.active = false;
  game.state.inventory.push('revival_codes');
  game.go('up');
  game.go('east');
  game.go('east');
  game.act('revive', 'enter');
  choose(game, 'Daniel sent me');
  game.choose(-1);
  choose(game, 'tell you himself');
  choose(game, 'call Daniel');
  const conv = finishTalk(game);
  assert.match(conv, /told me there was nothing in it/);
  assert.equal(game.state.trust.daniel.lies.emily.exposed, true);
});

test('chapter 4: if Emily died, the chapter ends once you find the body', () => {
  const { game } = startChapter4({ emilyAlive: false });
  finishTalk(game);
  game.go('north');
  game.go('north');
  game.act('bed', 'examine');
  choose(game, 'gone');
  assert.ok(game.state.trust.daniel.lies.body);
  const end = finishTalk(game);
  assert.match(end, /last thing she said to me/);
  assert.equal(game.view().mode, 'chapterEnd');
});
