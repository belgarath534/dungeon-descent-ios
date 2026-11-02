// Static checks for content: catches typos in room ids, effect names,
// condition keys, dialogue links and missing documents before anyone
// plays the game. Run by the test suite; returns a list of problems.

import { CONDITION_KEYS } from './conditions.js';

export function validateContent(content, effectNames) {
  const problems = [];
  const effects = new Set(effectNames);
  const conds = new Set(CONDITION_KEYS);

  function checkCondition(cond, where) {
    if (cond == null || typeof cond === 'function' || typeof cond === 'boolean') return;
    if (Array.isArray(cond)) return cond.forEach((c, i) => checkCondition(c, `${where}[${i}]`));
    for (const [k, v] of Object.entries(cond)) {
      if (!conds.has(k)) problems.push(`${where}: unknown condition "${k}"`);
      if (k === 'all' || k === 'any') v.forEach((c, i) => checkCondition(c, `${where}.${k}[${i}]`));
      if (k === 'not') checkCondition(v, `${where}.not`);
      if ((k === 'has' || k === 'notHas') && ![].concat(v).every((i) => content.items[i])) problems.push(`${where}: unknown item in ${k}`);
      if ((k === 'visited' || k === 'notVisited' || k === 'at') && ![].concat(v).every((r) => content.rooms[r])) problems.push(`${where}: unknown room in ${k}`);
    }
  }

  function checkText(t, where) {
    if (Array.isArray(t)) t.forEach((v, i) => checkCondition(v.when, `${where}[${i}]`));
  }

  function checkEffects(list, where) {
    if (!list) return;
    [].concat(list).forEach((e, i) => {
      if (typeof e === 'function') return;
      for (const [name, v] of Object.entries(e)) {
        const at = `${where}[${i}].${name}`;
        if (!effects.has(name)) problems.push(`${at}: unknown effect`);
        if (name === 'give' && !content.items[v]) problems.push(`${at}: unknown item "${v}"`);
        if (name === 'addDocument' && !content.documents[v]) problems.push(`${at}: unknown document "${v}"`);
        if (name === 'addRecording' && !content.recordings[v]) problems.push(`${at}: unknown recording "${v}"`);
        if (name === 'startDialogue' && !content.dialogues[v]) problems.push(`${at}: unknown dialogue "${v}"`);
        if (name === 'moveTo' && !content.rooms[v]) problems.push(`${at}: unknown room "${v}"`);
        if (name === 'schedule' && !content.events[v.event]) problems.push(`${at}: unknown event "${v.event}"`);
        if (name === 'objective') {
          const id = typeof v === 'string' ? v : v.id;
          if (!content.objectives[id]) problems.push(`${at}: unknown objective "${id}"`);
        }
      }
    });
  }

  function checkRoute(next, nodes, where) {
    if (!next) return;
    const ids = typeof next === 'string' ? [next] : next.map((r) => r.node);
    if (Array.isArray(next)) next.forEach((r, i) => checkCondition(r.when, `${where}[${i}]`));
    ids.forEach((id) => !nodes[id] && problems.push(`${where}: missing node "${id}"`));
  }

  if (!content.rooms[content.start.room]) problems.push('start.room does not exist');
  checkEffects(content.start.effects, 'start.effects');

  for (const [rid, room] of Object.entries(content.rooms)) {
    const w = `rooms.${rid}`;
    if (room.id !== rid) problems.push(`${w}: id mismatch`);
    checkText(room.description, `${w}.description`);
    checkText(room.revisit, `${w}.revisit`);
    (room.details || []).forEach((d, i) => checkCondition(d.when, `${w}.details[${i}]`));
    if (room.listen) {
      checkText(room.listen.text, `${w}.listen.text`);
      (room.listen.details || []).forEach((d, i) => checkCondition(d.when, `${w}.listen.details[${i}]`));
      checkEffects(room.listen.effects, `${w}.listen.effects`);
    }
    const objIds = new Set();
    for (const obj of room.objects || []) {
      const ow = `${w}.objects.${obj.id}`;
      if (objIds.has(obj.id)) problems.push(`${ow}: duplicate id`);
      objIds.add(obj.id);
      checkCondition(obj.when, `${ow}.when`);
      const actIds = new Set();
      for (const a of obj.actions || []) {
        const aw = `${ow}.${a.id}`;
        if (actIds.has(a.id)) problems.push(`${aw}: duplicate action id`);
        actIds.add(a.id);
        checkCondition(a.when, `${aw}.when`);
        checkText(a.text, `${aw}.text`);
        checkText(a.afterText, `${aw}.afterText`);
        checkEffects(a.effects, `${aw}.effects`);
      }
    }
    for (const e of room.exits || []) {
      const ew = `${w}.exits.${e.id}`;
      if (!content.rooms[e.to]) problems.push(`${ew}: unknown room "${e.to}"`);
      checkCondition(e.when, `${ew}.when`);
      checkCondition(e.locked, `${ew}.locked`);
      checkText(e.lockedText, `${ew}.lockedText`);
      checkEffects(e.effects, `${ew}.effects`);
    }
  }

  for (const [did, d] of Object.entries(content.dialogues)) {
    const w = `dialogues.${did}`;
    checkRoute(d.start, d.nodes, `${w}.start`);
    for (const [nid, n] of Object.entries(d.nodes)) {
      const nw = `${w}.${nid}`;
      if (n.speaker && !content.speakers[n.speaker]) problems.push(`${nw}: unknown speaker "${n.speaker}"`);
      (n.lines || []).forEach((l, i) => typeof l === 'object' && checkCondition(l.when, `${nw}.lines[${i}]`));
      checkEffects(n.effects, `${nw}.effects`);
      checkRoute(n.next, d.nodes, `${nw}.next`);
      (n.choices || []).forEach((c, i) => {
        checkCondition(c.when, `${nw}.choices[${i}].when`);
        checkEffects(c.effects, `${nw}.choices[${i}].effects`);
        checkRoute(c.next, d.nodes, `${nw}.choices[${i}].next`);
      });
    }
  }

  for (const t of content.triggers) {
    checkCondition(t.when, `triggers.${t.id}`);
    checkEffects(t.effects, `triggers.${t.id}.effects`);
  }
  for (const [id, ev] of Object.entries(content.events)) {
    checkCondition(ev.when, `events.${id}`);
    checkEffects(ev.effects, `events.${id}.effects`);
  }
  for (const a of content.globalActions || []) {
    checkCondition(a.when, `globalActions.${a.id}`);
    checkEffects(a.effects, `globalActions.${a.id}.effects`);
  }
  for (const [id, d] of Object.entries({ ...content.documents, ...content.recordings })) {
    checkEffects(d.onRead, `journal.${id}.onRead`);
    if (!Array.isArray(d.text)) problems.push(`journal.${id}: text must be a list of paragraphs`);
  }
  for (const r of content.stalkerRoute || []) if (!content.rooms[r]) problems.push(`stalkerRoute: unknown room "${r}"`);
  for (const [n, ch] of Object.entries(content.chapters)) {
    if (!content.rooms[ch.start.room]) problems.push(`chapters.${n}.start.room does not exist`);
    checkEffects(ch.start.effects, `chapters.${n}.start.effects`);
    checkEffects(ch.afterEnd?.effects, `chapters.${n}.afterEnd.effects`);
    (ch.summary || []).forEach((l, i) => checkCondition(l.when, `chapters.${n}.summary[${i}]`));
    for (const id of ch.afterEnd?.resetTriggers || []) {
      if (!content.triggers.some((t) => t.id === id)) problems.push(`chapters.${n}.afterEnd: unknown trigger "${id}"`);
    }
  }

  return problems;
}
