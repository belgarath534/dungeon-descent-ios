// Declarative conditions used everywhere in content: exits, objects,
// actions, dialogue choices, triggers. Keeping them as data (not code)
// means writers can add story content without touching the engine, and
// tests can check content for typos.
//
// A condition is:
//   - null/undefined            -> always true
//   - an array                  -> every entry must be true
//   - a function(state)         -> escape hatch for unusual logic
//   - an object; every key must hold:
//       flag / notFlag          string | string[]
//       has / notHas            item id | item id[]
//       visited / notVisited    room id
//       read                    document id (opened in the journal)
//       found                   document or recording id (in journal)
//       trustAtLeast / trustBelow   number (Daniel's trust)
//       lied / lieExposed       lie id
//       objective               { id, status }
//       minutesAtLeast          number of in-game minutes elapsed
//       at                      room id | room id[] (player's location)
//       inDialogue              boolean
//       all / any               condition[]
//       not                     condition

const asList = (v) => (Array.isArray(v) ? v : [v]);

const CHECKS = {
  flag: (v, s) => asList(v).every((f) => !!s.flags[f]),
  notFlag: (v, s) => asList(v).every((f) => !s.flags[f]),
  has: (v, s) => asList(v).every((i) => s.inventory.includes(i)),
  notHas: (v, s) => asList(v).every((i) => !s.inventory.includes(i)),
  visited: (v, s) => asList(v).every((r) => !!s.visited[r]),
  notVisited: (v, s) => asList(v).every((r) => !s.visited[r]),
  read: (v, s) => asList(v).every((d) => !!s.journal.read[d]),
  found: (v, s) =>
    asList(v).every((d) => s.journal.documents.includes(d) || s.journal.recordings.includes(d)),
  trustAtLeast: (v, s) => s.trust.daniel.value >= v,
  trustBelow: (v, s) => s.trust.daniel.value < v,
  lied: (v, s) => !!s.trust.daniel.lies[v],
  lieExposed: (v, s) => s.trust.daniel.lies[v]?.exposed === true,
  objective: (v, s) => s.objectives[v.id] === v.status,
  minutesAtLeast: (v, s) => s.time.minutes >= v,
  at: (v, s) => asList(v).includes(s.location),
  inDialogue: (v, s) => !!s.dialogue.active === !!v,
  all: (v, s) => v.every((c) => evaluate(c, s)),
  any: (v, s) => v.some((c) => evaluate(c, s)),
  not: (v, s) => !evaluate(v, s),
};

export const CONDITION_KEYS = Object.keys(CHECKS);

export function evaluate(cond, state) {
  if (cond == null) return true;
  if (typeof cond === 'function') return !!cond(state);
  if (Array.isArray(cond)) return cond.every((c) => evaluate(c, state));
  if (typeof cond !== 'object') throw new Error(`Bad condition: ${JSON.stringify(cond)}`);

  for (const [key, value] of Object.entries(cond)) {
    const check = CHECKS[key];
    if (!check) throw new Error(`Unknown condition "${key}"`);
    if (!check(value, state)) return false;
  }
  return true;
}
