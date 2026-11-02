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

// As if Chapter 5 just ended, with the given story so far.
function startChapter6({ emily = 'awake', trust = 40, badge = true, confided = true, core = true } = {}) {
  const game = createGame({ content, bus: createEventBus() });
  game.newGame();
  const s = game.state;
  for (const t of content.triggers) if (t.id !== 'ch6_marcus') s.firedTriggers[t.id] = true;
  Object.assign(s.flags, {
    daniel_contacted: true, power_on: true, elevator_unlocked: true, found_emily: true, saw_001: true,
    ward_door_powered: true, ch3_started: true, woke_001: true, ch4_started: true, saw_body: true,
    ch5_started: true, elevator_up: true, chain_cut: true, told_body_alive: true,
  });
  if (emily === 'awake') Object.assign(s.flags, { emily_awake: true, emily_daniel_talked: true });
  if (emily === 'dead') s.flags.emily_dead = true;
  if (confided) s.flags.emily_confided = true;
  Object.assign(s.ward, { active: false, location: 'ward', emilyAlive: emily !== 'dead', warned: {} });
  s.trust.daniel.value = trust;
  s.inventory.push('facility_radio', 'key_001', 'flashlight');
  if (badge) s.inventory.push('emily_badge');
  if (core) s.inventory.push('core_001');
  // 001 docked and recharging in storage.
  Object.assign(s.stalker, { active: true, room: 'storage', step: 0, nextMoveAt: 9999, rechargeUntil: 9999 });
  s.chapter = 5;
  s.ended = { chapter: 5 };
  game.startNextChapter();
  assert.equal(game.state.location, 'isolation');
  return game;
}

// Chapter 6 the long way: lanyard, restore 001, hear Marcus out.
function playChapter6(game, { marcus = 'help', badgeChoice = 'hers to say' } = {}) {
  choose(game, 'What happened');
  finishTalk(game);
  if (game.state.inventory.includes('emily_badge')) {
    game.act('daniel', 'badge');
    choose(game, badgeChoice);
    finishTalk(game);
  }
  if (game.state.inventory.includes('core_001')) {
    game.go('out'); game.go('up'); game.go('north'); // stairwell, corridor, elevator car
    game.go('down'); game.go('west'); // landing, storage
    game.act('restore_001', 'install');
    choose(game, 'How do you know Emily');
    finishTalk(game);
    assert.ok(game.state.flags.ally_001);
    assert.equal(game.state.stalker.active, false, 'restored 001 no longer hunts you');
    game.go('east'); game.go('up'); // landing, surface corridor
  } else {
    game.go('out'); game.go('up');
  }
  game.go('south'); // reception: Marcus is there
  assert.equal(game.state.dialogue.active?.id, 'marcus');
  choose(game, 'Who are you');
  finishTalk(game);
  choose(game, 'Take the remote');
  finishTalk(game);
  if (marcus === 'help') {
    choose(game, 'Tell me everything');
    finishTalk(game);
    choose(game, 'help us undo it');
  } else if (marcus === 'arrest') {
    choose(game, 'under arrest');
  } else {
    choose(game, 'You decide');
    choose(game, 'All right, Daniel');
  }
  finishTalk(game);
  assert.equal(game.view().mode, 'chapterEnd');
  assert.equal(game.view().ended.title, 'End of Chapter 6');
  game.startNextChapter();
  assert.equal(game.state.dialogue.active?.id, 'finale');
}

test('chapter 6: Daniel in person, the lanyard, 001 restored, and Marcus', () => {
  const game = startChapter6();
  playChapter6(game);
  assert.ok(game.state.flags.badge_given);
  assert.ok(game.state.flags.kept_confidence);
  assert.ok(game.state.flags.knows_copy);
  assert.ok(game.state.flags.marcus_helping);
  assert.ok(game.state.inventory.includes('marcus_remote'));
});

test('finale: Two Coffees, the romantic ending', () => {
  const game = startChapter6({ trust: 45 });
  playChapter6(game);
  assert.ok(game.state.trust.daniel.value >= 50, `trust ${game.state.trust.daniel.value}`);
  const t = text(choose(game, 'bring you home')) + finishTalk(game);
  assert.match(t, /never a mistake/);
  assert.equal(game.view().ended.ending, 'romance');
});

test('finale: Home, if the romance is not earned', () => {
  const game = startChapter6({ trust: 30, badge: false });
  playChapter6(game);
  choose(game, 'bring you home');
  finishTalk(game);
  assert.equal(game.view().ended.ending, 'restored');
});

test('finale: inventing Emily’s words closes the romance', () => {
  const game = startChapter6({ trust: 60 });
  playChapter6(game, { badgeChoice: 'never left' });
  choose(game, 'bring you home');
  finishTalk(game);
  assert.equal(game.view().ended.ending, 'restored');
});

test('finale: Silence, when Daniel does not trust you enough', () => {
  const game = startChapter6({ trust: 5, badge: false });
  playChapter6(game);
  const t = text(choose(game, 'bring you home')) + finishTalk(game);
  assert.match(t, /switched himself off/);
  assert.equal(game.view().ended.ending, 'lost');
});

test('finale: Silence, by the red button, with a chance to change your mind', () => {
  const game = startChapter6();
  playChapter6(game, { marcus: 'arrest' });
  choose(game, 'red button');
  choose(game, 'Take your thumb away');
  assert.equal(game.view().mode, 'dialogue');
  choose(game, 'red button');
  choose(game, 'Press it');
  finishTalk(game);
  assert.equal(game.view().ended.ending, 'lost');
});

test('finale: Names, the revenge ending', () => {
  const game = startChapter6();
  playChapter6(game, { marcus: 'revenge' });
  assert.ok(game.state.flags.revenge_marcus);
  const t = text(choose(game, 'Open the clamps')) + finishTalk(game);
  assert.match(t, /Marcus was the first/);
  assert.equal(game.view().ended.ending, 'revenge');
});

test('finale: The First of Its Kind, the secret connection', () => {
  const game = startChapter6();
  playChapter6(game);
  choose(game, '001 is what you were trying to build');
  finishTalk(game);
  assert.equal(game.view().ended.ending, 'prototype');
});

test('finale: Code Four, walking away; and "not yet" lets you come back', () => {
  const game = startChapter6({ emily: 'dead', badge: false, core: false });
  playChapter6(game, { marcus: 'arrest' });
  assert.ok(!game.view().choices.some((c) => c.text.includes('bring you home')), 'no way home without Emily or Marcus');
  choose(game, 'Not yet');
  assert.equal(game.view().mode, 'explore');
  game.act('decide', 'ready');
  choose(game, 'leaving');
  finishTalk(game);
  assert.equal(game.view().ended.ending, 'abandon');
});

test('a lie about his body is exposed when Marcus speaks', () => {
  const game = startChapter6();
  delete game.state.flags.told_body_alive;
  game.state.trust.daniel.lies.body = { exposed: false, at: 0, about: 'his body' };
  playChapter6(game);
  assert.equal(game.state.trust.daniel.lies.body.exposed, true);
});
