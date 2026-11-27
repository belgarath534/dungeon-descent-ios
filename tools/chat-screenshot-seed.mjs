// Fills the local Firebase emulators with sample players, channels and
// messages for Dungeon Descent Chat's App Store screenshots (the "Chat app
// screenshots" workflow). Never touches the real database: it talks only to
// the emulators on this machine. Prints the screenshot player's email.
//
//   node tools/chat-screenshot-seed.mjs
const PROJECT = 'dungeon-descent-fbaf2';
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo';
const FS = `http://127.0.0.1:8085/v1/projects/${PROJECT}/databases/dungeon-descent/documents/`;
const DEV = 'WgqZGmnPKeYIymlMkx0aAg8G2T52';
const PASSWORD = 'screenshots123';

const now = Date.now();
const ago = (min) => new Date(now - min * 60000);

function val(v) {
  if (v === null) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(val) } };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'object') return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, val(x)])) } };
  return { stringValue: String(v) };
}
async function put(path, obj) {
  const fields = Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, val(v)]));
  const r = await fetch(FS + path, { method: 'PATCH', headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' },
                                     body: JSON.stringify({ fields }) });
  if (!r.ok) throw new Error(path + ' ' + r.status + ' ' + await r.text());
}
async function account(email) {
  const r = await fetch(AUTH, { method: 'POST', headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify({ email, password: PASSWORD, returnSecureToken: true }) });
  const j = await r.json();
  if (!j.localId) throw new Error('signUp ' + JSON.stringify(j));
  return j.localId;
}

// ── Players ──
const players = {
  me:     { name: 'RavenBlade', bio: 'Blind player since day one. Sorcerer main, Endless Descent addict.', cls: 'Sorcerer', online: true },
  seb:    { name: 'Sebastian', bio: 'Moderator. Ask me anything about co-op.', cls: 'Paladin', online: true, mod: true },
  mira:   { name: 'MiraNightshade', bio: 'Speedrunning the Crypt on Nightmare.', cls: 'Assassin', online: true },
  thorne: { name: 'Thorne', bio: 'Tank for hire. Will block for snacks.', cls: 'Sentinel', online: true },
  kael:   { name: 'KaelTheBold', bio: 'Spire floor 120 and climbing.', cls: 'Berserker', online: false },
  nyx:    { name: 'NyxEmber', bio: 'I make community enemies. Fear the Ash Goblin.', cls: 'Necromancer', online: true },
  juno:   { name: 'Juno_Plays', bio: 'VoiceOver user. Bard forever.', cls: 'Bard', online: false },
};
for (const [key, p] of Object.entries(players)) p.uid = await account(`${key}@screenshots.dev`);
players.dev = { uid: DEV, name: 'Leonardo', bio: 'I make Dungeon Descent.', cls: 'Wizard', online: true };
const P = players;

for (const [key, p] of Object.entries(P)) {
  await put('usernames/' + p.name.toLowerCase(), { uid: p.uid, username: p.name });
  await put('users/' + p.uid, { username: p.name });
  const m = { username: p.name, createdAt: ago(60 * 24 * (key === 'me' ? 6 : 30)), lastPostAt: ago(90), agreedAt: ago(60 * 24 * 5),
              dmOff: false, bio: p.bio, favClass: p.cls };
  if (p.mod) m.mod = true;
  if (key === 'me') m.trusted = true;
  if (p.online) m.lastSeen = new Date(now + 3 * 3600000); // stays "online" while the screenshots are taken
  await put('chat_members/' + p.uid, m);
}
await put(`chat_members/${P.me.uid}/private/push`, { chosen: true, channels: ['announcements', 'general', 'hall-of-legends'],
  dms: true, groups: true, sounds: { default: 'dd-ach-gold' }, custom: false, legends: true, reactions: true });

// ── Channels (tools/chat-seed.py) ──
const CHANNELS = [
  ['announcements', 'News and updates from the developer', true],
  ['general', 'Talk about anything Dungeon Descent', false],
  ['help', 'Questions about the game? Ask here', false],
  ['strategy', 'Classes, builds and tips', false],
  ['bug-reports', 'Something broken? Tell us what happened and on which device', false],
  ['ideas', 'Suggestions for the game', false],
  ['hall-of-legends', 'Show off your best runs', false],
  ['co-op-rooms', 'Find players for co-op dungeons and raids', false],
  ['community-enemies', 'Share the enemies you made', false],
  ['community-dungeons', 'Share the dungeons you made', false],
];
for (const [i, [id, topic, mods]] of CHANNELS.entries()) await put('chat_channels/' + id, { name: id, topic, order: i, modsPost: mods });

let n = 0;
async function msg(room, who, text, minAgo, extra = {}) {
  const id = 'm' + String(++n).padStart(4, '0');
  const p = typeof who === 'string' ? P[who] : who;
  await put(`${room}/messages/${id}`, { uid: p.uid, username: p.name, text, ts: ago(minAgo), ...extra });
  return id;
}
const C = (id) => 'chat_channels/' + id;

// #general
await msg(C('general'), 'thorne', 'Anyone else stuck on the Frosthold boss? It froze me three turns in a row 🥶', 95);
await msg(C('general'), 'mira', 'Bring fire potions and save your shield for phase 2. Worked for me on Nightmare.', 90,
          { reactions: { [P.thorne.uid]: '👍', [P.kael.uid]: '🔥' } });
await msg(C('general'), 'kael', 'Just hit floor 120 in the Spire. My hands are shaking', 70,
          { reactions: { [P.mira.uid]: '🔥', [P.seb.uid]: '🔥', [P.nyx.uid]: '😮', [P.me.uid]: '🔥' } });
const ravenQ = await msg(C('general'), 'me', 'Is the Weekly Ladder worth it with a level 8 Sorcerer?', 42);
await msg(C('general'), 'seb', 'Definitely. The modifiers this week are kind to casters, go for it!', 38, { replyTo: ravenQ });
await msg(C('general'), 'nyx', 'Just made a new community enemy: the Ash Goblin. Good luck 😈', 21,
          { reactions: { [P.me.uid]: '😂', [P.juno.uid]: '😂' } });
await msg(C('general'), 'juno', 'The new VoiceOver labels in 12.2 are so good. Thank you Leonardo!', 12,
          { reactions: { [DEV]: '❤️', [P.me.uid]: '❤️', [P.seb.uid]: '👍' } });
const mention = await msg(C('general'), 'mira', '@RavenBlade want to do a co-op run tonight? I need a caster', 6);
await msg(C('general'), 'thorne', "I'm in too, I'll tank 🛡", 4);

// #announcements
await msg(C('announcements'), 'dev', '🎉 Welcome to Dungeon Descent Chat! A place for the community that works great with VoiceOver. Be kind, have fun.', 60 * 24 * 3,
          { reactions: { [P.me.uid]: '❤️', [P.mira.uid]: '🔥', [P.seb.uid]: '❤️', [P.juno.uid]: '❤️' }, pinned: true });
await msg(C('announcements'), 'dev', 'Version 12.2.1 is on its way: the Hall of Legends now posts your big moments here automatically 🏆', 180,
          { reactions: { [P.kael.uid]: '🔥', [P.nyx.uid]: '😮' } });

// #hall-of-legends
const legend = (text, about, min) => msg(C('hall-of-legends'), { uid: 'hall-of-legends', name: 'Hall of Legends' }, text, min, { about: P[about].uid, pushed: true });
await legend('🏆 MiraNightshade conquered Crypt of Malachar on Nightmare as an Assassin!', 'mira', 300);
await legend('🗼 KaelTheBold climbed to floor 120 of The Spire!', 'kael', 72);
const myLegend = await legend('⬇️ RavenBlade reached floor 75 in Endless Descent!', 'me', 30);
await legend('🏆 Thorne conquered Frosthold Abyss on Forsaken as a Sentinel!', 'thorne', 15);
await put(`${C('hall-of-legends')}/messages/${myLegend}`, { uid: 'hall-of-legends', username: 'Hall of Legends', text: '⬇️ RavenBlade reached floor 75 in Endless Descent!',
          ts: ago(30), about: P.me.uid, pushed: true, reactions: { [P.mira.uid]: '🔥', [P.seb.uid]: '👍', [P.juno.uid]: '🔥' } });

// #strategy, #co-op-rooms
await msg(C('strategy'), 'seb', 'Tip: Paladins can stack Divine Shield before the boss. Saves a potion every time.', 200);
await msg(C('co-op-rooms'), 'thorne', 'Room DRAGON open for a Crypt run, 2 spots left', 25);

// ── A private conversation and a group ──
const pair = [P.me.uid, P.seb.uid].sort().join('_');
await put('chat_dms/' + pair, { members: [P.me.uid, P.seb.uid].sort(), names: { [P.me.uid]: P.me.name, [P.seb.uid]: P.seb.name }, lastAt: ago(8) });
await msg('chat_dms/' + pair, 'seb', 'Hey! Thanks for the bug report about the Spire, Leonardo fixed it 🙌', 30);
await msg('chat_dms/' + pair, 'me', 'No way, that was fast! Thank you both', 25, { reactions: { [P.seb.uid]: '❤️' } });
await msg('chat_dms/' + pair, 'seb', 'Want to join the raid group tonight at 8?', 8);
const pair2 = [P.me.uid, P.juno.uid].sort().join('_');
await put('chat_dms/' + pair2, { members: [P.me.uid, P.juno.uid].sort(), names: { [P.me.uid]: P.me.name, [P.juno.uid]: P.juno.name }, lastAt: ago(240) });
await msg('chat_dms/' + pair2, 'juno', 'Your Endless build is amazing, what spirit do you use?', 240);

await put('chat_groups/raidnight', { name: 'Raid Night', owner: P.seb.uid, createdAt: ago(60 * 24 * 2), lastAt: ago(3),
  members: { [P.seb.uid]: P.seb.name, [P.me.uid]: P.me.name, [P.mira.uid]: P.mira.name, [P.thorne.uid]: P.thorne.name } });
await msg('chat_groups/raidnight', 'seb', 'Raid at 8 PM tonight, everyone in?', 40);
await msg('chat_groups/raidnight', 'mira', 'In! Bringing my Assassin', 35, { reactions: { [P.seb.uid]: '👍' } });
await msg('chat_groups/raidnight', 'thorne', "I'll tank, someone bring healing", 3);
await put('chat_groups/guildwolves', { name: 'Iron Wolves Guild', owner: P.thorne.uid, createdAt: ago(60 * 24 * 4), lastAt: ago(120),
  members: { [P.thorne.uid]: P.thorne.name, [P.me.uid]: P.me.name, [P.kael.uid]: P.kael.name } });
await msg('chat_groups/guildwolves', 'kael', 'Guild Boss is at 20% HP, finish it today!', 120);

// ── Activity for the screenshot player ──
const act = (id, d) => put(`chat_members/${P.me.uid}/activity/${id}`, d);
await act('mention_' + mention, { type: 'mention', from: P.mira.name, fromUid: P.mira.uid, text: '@RavenBlade want to do a co-op run tonight? I need a caster',
  kind: 'channel', room: 'general', where: '#general', mid: mention, ts: ago(6) });
await act('react_' + myLegend + '_' + P.mira.uid, { type: 'reaction', emoji: '🔥', from: P.mira.name, fromUid: P.mira.uid, text: '⬇️ RavenBlade reached floor 75 in Endless Descent!',
  kind: 'channel', room: 'hall-of-legends', where: '#hall-of-legends', mid: myLegend, ts: ago(20) });
const sebReply = (await fetch(FS + `${C('general')}/messages`, { headers: { Authorization: 'Bearer owner' } }).then(r => r.json()))
  .documents.find(d => d.fields.replyTo)?.name.split('/').pop();
await act('reply_' + sebReply, { type: 'reply', from: P.seb.name, fromUid: P.seb.uid, text: 'Definitely. The modifiers this week are kind to casters, go for it!',
  kind: 'channel', room: 'general', where: '#general', mid: sebReply, ts: ago(38) });
await act('react_' + ravenQ + '_' + P.juno.uid, { type: 'reaction', emoji: '❤️', from: P.juno.name, fromUid: P.juno.uid, text: 'Is the Weekly Ladder worth it with a level 8 Sorcerer?',
  kind: 'channel', room: 'general', where: '#general', mid: ravenQ, ts: ago(90) });

// ── The game's leaderboards ──
function isoWeek(d) {
  const t = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  t.setDate(t.getDate() - (t.getDay() + 6) % 7 + 3);
  const y = t.getFullYear(), first = new Date(y, 0, 4);
  const w = 1 + Math.round(((t - first) / 864e5 - 3 + (first.getDay() + 6) % 7) / 7);
  return `weekly-${y}-W${String(w).padStart(2, '0')}`;
}
const scores = { mira: 184200, kael: 162750, me: 141300, thorne: 98400, seb: 87150, nyx: 64900, juno: 51200 };
const titles = { mira: 'Shadowblade', kael: 'Spire King', me: 'Voidwalker', thorne: 'The Wall', seb: 'Guardian', nyx: 'Bonecaller', juno: 'Songweaver' };
for (const [k, s] of Object.entries(scores)) {
  await put('leaderboard/' + P[k].uid, { uid: P[k].uid, username: `${P[k].name} · ${titles[k]}`, score: s, tag: titles[k], updatedAt: now });
  await put(`tournament/${isoWeek(new Date())}/scores/${P[k].uid}`, { uid: P[k].uid, email: P[k].name, score: Math.round(s / 40), character: P[k].cls });
  await put(`tournament/afk-rivals/scores/${P[k].uid}`, { uid: P[k].uid, email: P[k].name, score: k === 'me' ? 75 : Math.round(s / 1900), character: P[k].cls });
  await put(`tournament/worldboss-${new Date().toISOString().slice(0, 10)}/scores/${P[k].uid}`, { uid: P[k].uid, email: P[k].name, score: Math.round(s / 30) });
}
console.log(`me@screenshots.dev ${PASSWORD} ${P.me.uid} ${pair}`);
