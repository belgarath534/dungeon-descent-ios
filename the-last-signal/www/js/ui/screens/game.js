// The main play screen.
//
// Layout, in reading order (this is what a screen reader user swipes through):
//   1. Heading: where you are            (h1, also the page title)
//   2. Status: time                      (plain text)
//   3. Narration: what just happened     (receives focus after every action)
//   4. Controls, each group under its own h2 so the VoiceOver rotor can jump:
//        explore  -> Actions / Around you / Exits / Menu
//        object   -> the object's actions / Back
//        dialogue -> Respond / Menu
//        chapter end -> summary and choices
//
// After every action focus moves to the narration, so the screen reader
// reads the result immediately; swiping right from there reaches the
// controls for the next decision.

import { h, button, buttonGroup, focusEl } from '../dom.js';
import { DIRECTION_PAN } from '../../systems/world.js';

const POSITION_WORD = { left: 'on your left', right: 'on your right', ahead: 'ahead', behind: 'behind you' };
const DIR_WORD = { north: 'North', south: 'South', east: 'East', west: 'West', up: 'Up', down: 'Down', in: 'In', out: 'Out' };

export function gameScreen(app) {
  const { game } = app;
  let submenu = null; // object id while its action menu is open
  let lastBeat = [];

  const title = h('h1', { id: 'room-title' });
  const status = h('p', { class: 'status' });
  const beatEl = h('p', { id: 'beat', class: 'beat', tabindex: '-1', 'data-quiet': '' });
  const controls = h('div', { class: 'controls' });
  const el = h('div', { class: 'screen game-screen' }, title, status, beatEl, controls);

  // ---- narration ----------------------------------------------------------
  function lineText(l) {
    if (l.kind === 'speech') return `${l.speaker}: “${l.text}”`;
    return l.text;
  }

  function showBeat(lines) {
    const notes = app.takeNotes().map((text) => ({ text, kind: 'system' }));
    const all = [...lines, ...notes];
    if (!all.length) all.push({ text: 'Nothing happens.', kind: 'system' });
    lastBeat = all;
    app.recordBeat(all);
    beatEl.replaceChildren();
    all.forEach((l, i) => {
      if (i > 0) beatEl.append(h('br'), h('br'));
      beatEl.append(h('span', { class: `line line-${l.kind}${l.speakerId ? ` speaker-${l.speakerId}` : ''}` }, lineText(l)));
    });
    app.announcer.narrate(all.map(lineText).join(' '));
  }

  function perform(fn, { closeSubmenu = false } = {}) {
    const beat = fn();
    if (closeSubmenu) submenu = null;
    showBeat(beat.lines);
    render();
    app.autosave();
    focusEl(beatEl);
  }

  // ---- controls -----------------------------------------------------------
  function render() {
    const v = game.view();
    title.textContent = v.mode === 'chapterEnd' ? v.ended.title : v.room.name;
    status.textContent = `Time: ${v.clock}`;
    document.title = `${title.textContent} — The Last Signal`;

    if (submenu && !v.objects.some((o) => o.id === submenu)) submenu = null;
    if (v.mode !== 'explore') submenu = null;

    const groups = [];
    if (v.mode === 'chapterEnd') groups.push(...chapterEndControls(v));
    else if (v.mode === 'dialogue') groups.push(dialogueControls(v));
    else if (submenu) groups.push(objectControls(v.objects.find((o) => o.id === submenu)));
    else groups.push(...exploreControls(v));

    if (v.mode !== 'chapterEnd') groups.push(menuControls(v));
    controls.replaceChildren(...groups.filter(Boolean));
  }

  function exploreControls(v) {
    const actions = v.roomActions.map((a) =>
      button(a.label, () => perform(() => game.roomAction(a.id))),
    );

    const objects = v.objects.map((o) =>
      button(`${o.name}, ${POSITION_WORD[o.position] || ''}`.replace(/, $/, ''), () => {
        app.audio.cue('ui.select');
        submenu = o.id;
        render();
        focusEl(controls.querySelector('h2'));
      }, { 'data-pan': DIRECTION_PAN[o.position] ?? 0, 'data-object-id': o.id }),
    );

    const exits = v.exits.map((e) => {
      const dir = DIR_WORD[e.dir];
      const label = e.dir === 'in' || e.dir === 'out' ? e.label : `${dir}: ${e.label}`;
      return button(e.lockedKnown ? `${label}, locked` : label, () => perform(() => game.go(e.id)), {
        'data-pan': DIRECTION_PAN[e.dir] ?? 0,
      });
    });

    return [
      buttonGroup('Actions', actions),
      buttonGroup('Around you', objects),
      buttonGroup('Exits', exits),
    ];
  }

  function objectControls(obj) {
    const actions = game.objectActions(obj.id).map((a) =>
      button(a.label, () => perform(() => game.act(obj.id, a.id)), { 'data-pan': DIRECTION_PAN[obj.position] ?? 0 }),
    );
    actions.push(
      button(`Back to the room`, () => {
        app.audio.cue('ui.back');
        const id = submenu;
        submenu = null;
        render();
        focusEl([...controls.querySelectorAll('button')].find((b) => b.dataset.objectId === id) || controls.querySelector('h2'));
      }),
    );
    return buttonGroup(obj.name, actions);
  }

  function dialogueControls(v) {
    const choices = v.choices.map((c, i) =>
      button(`${i + 1}. ${c.text}`, () => perform(() => game.choose(c.index)), { class: 'btn choice' }),
    );
    return buttonGroup('Respond', choices);
  }

  function menuControls(v) {
    const items = [
      button('Repeat last', repeat),
      button('Journal', () => app.open('journal')),
      button('Inventory', () => app.open('inventory')),
      button('Pause menu', () => app.open('pause')),
    ];
    if (v.mode === 'dialogue') items.splice(2, 1);
    return buttonGroup('Menu', items);
  }

  function chapterEndControls(v) {
    const s = game.state;
    const totals = game.ctx.content.totals;
    const t = s.trust.daniel;
    const lines = [];
    lines.push(`Daniel seems ${app.trustLevel().label} toward you.`);
    if (s.flags.daniel_named) lines.push('You learned his name: Daniel.');
    if (s.flags.daniel_opened_elevator) lines.push('Daniel opened the way down for you.');
    else if (s.flags.used_override) lines.push('You found your own way down.');
    for (const lie of Object.values(t.lies)) {
      lines.push(lie.exposed ? `Daniel caught you lying about ${lie.about}.` : `You lied to Daniel about ${lie.about}. He has not found out. Yet.`);
    }
    lines.push(`Documents found: ${s.journal.documents.length} of ${totals.documents}.`);
    lines.push(`Recordings found: ${s.journal.recordings.length} of ${totals.recordings}.`);
    lines.push(`Hidden discoveries: ${s.stats.secretsFound} of ${totals.secrets}.`);

    const summary = h(
      'section',
      { class: 'group', 'aria-labelledby': 'summary-h' },
      h('h2', { id: 'summary-h' }, 'Your choices so far'),
      h('ul', { class: 'summary' }, lines.map((l) => h('li', {}, l))),
      h('p', {}, 'This is the end of the current build. Your progress is saved.'),
    );
    const next = buttonGroup('What next', [
      button('Keep exploring Chapter 1', () => perform(() => game.continueAfterChapter())),
      button('Return to the main menu', () => app.show('title')),
    ]);
    return [summary, next];
  }

  function repeat() {
    app.announcer.narrate(lastBeat.map(lineText).join(' '));
    focusEl(beatEl);
  }

  return {
    el,
    title: 'Game',
    focusTarget: () => beatEl,

    onShow(params) {
      if (params.newGame) showBeat(game.newGame().lines);
      else if (params.resume) showBeat(game.resume().lines);
      else if (!lastBeat.length) showBeat(game.resume().lines);
      render();
      if (params.newGame || params.resume) app.autosave();
    },

    onKey(key) {
      const v = game.view();
      if (key === 'Escape') {
        if (submenu) {
          submenu = null;
          render();
          focusEl(controls.querySelector('h2'));
        } else app.open('pause');
        return true;
      }
      if (key === 'r' || key === 'R') return repeat(), true;
      if (key === 'j' || key === 'J') return app.open('journal'), true;
      if ((key === 'i' || key === 'I') && v.mode !== 'dialogue') return app.open('inventory'), true;
      if (v.mode === 'explore' && (key === 'l' || key === 'L')) return perform(() => game.look(), { closeSubmenu: true }), true;
      if (/^[1-9]$/.test(key)) {
        const btn = controls.querySelectorAll('.btn-list')[0]?.querySelectorAll('button')[Number(key) - 1];
        if (btn) btn.click();
        return !!btn;
      }
      return false;
    },
  };
}
