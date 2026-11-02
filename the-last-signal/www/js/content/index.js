// All game content. Chapters are merged into one world, so flags, trust,
// lies and Emily's fate carry from one chapter into the next.
import { chapter1 } from './chapter1/index.js';
import { chapter2 } from './chapter2/index.js';

const CHAPTERS = [chapter1, chapter2];

const merge = (key, tag) =>
  Object.assign(
    {},
    ...CHAPTERS.map((c) =>
      tag ? Object.fromEntries(Object.entries(c[key] || {}).map(([id, v]) => [id, { chapter: c.number, ...v }])) : c[key] || {},
    ),
  );

export const content = {
  start: chapter1.start,
  chapters: Object.fromEntries(
    CHAPTERS.map((c) => [c.number, { title: c.title, start: c.start, secrets: c.secrets, summary: c.summary || [], afterEnd: c.afterEnd }]),
  ),
  rooms: merge('rooms'),
  items: merge('items'),
  documents: merge('documents', true),
  recordings: merge('recordings', true),
  objectives: merge('objectives'),
  speakers: merge('speakers'),
  dialogues: merge('dialogues'),
  events: merge('events'),
  triggers: CHAPTERS.flatMap((c) => c.triggers || []),
  globalActions: CHAPTERS.flatMap((c) => c.globalActions || []),
};
