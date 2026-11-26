// Dungeon Descent Chat rules (firestore.rules, "Dungeon Descent Chat" part).
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { doc, setDoc, updateDoc, deleteDoc, getDoc, getDocs, collection, writeBatch, serverTimestamp, Timestamp, deleteField } from 'firebase/firestore';

const env = await initializeTestEnvironment({ projectId: 'demo-dd-chat', firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8085 } });
const DEV = 'WgqZGmnPKeYIymlMkx0aAg8G2T52';
const cache = {};
const db = (u) => cache[u ?? '-'] ??= (u ? env.authenticatedContext(u) : env.unauthenticatedContext()).firestore();
let pass = 0, fail = 0;
async function t(name, p, ok) {
  try { await (ok ? assertSucceeds(p) : assertFails(p)); pass++; }
  catch (e) { fail++; console.log('FAIL', name, '-', e.message.slice(0, 200)); }
}
const old = Timestamp.fromMillis(Date.now() - 3 * 86400e3);

// Setup: usernames, channels, members (alice is a day-old member, mod is a moderator,
// tess a tester, newbie joined just now).
await env.withSecurityRulesDisabled(async c => {
  const f = c.firestore();
  for (const [uid, name] of [['alice', 'Alice'], ['bob', 'Bob'], ['mod1', 'Sebastian'], ['tess', 'Tess'], ['newbie', 'Newbie'], ['carol', 'Carol'], ['banned', 'Baddie'], ['quiet', 'Quiet']]) {
    await setDoc(doc(f, 'usernames/' + name.toLowerCase()), { uid, username: name });
  }
  await setDoc(doc(f, 'usernames/zed'), { uid: 'zed', username: 'Zed' });
  const member = (name, extra = {}) => ({ username: name, createdAt: old, lastPostAt: old, agreedAt: old, ...extra });
  await setDoc(doc(f, 'chat_members/alice'), member('Alice'));
  await setDoc(doc(f, 'chat_members/bob'), member('Bob'));
  await setDoc(doc(f, 'chat_members/mod1'), member('Sebastian', { mod: true }));
  await setDoc(doc(f, 'chat_members/tess'), member('Tess', { tester: true }));
  await setDoc(doc(f, 'chat_members/newbie'), member('Newbie', { createdAt: Timestamp.now() }));
  await setDoc(doc(f, 'chat_members/banned'), member('Baddie'));
  await setDoc(doc(f, 'chat_members/quiet'), member('Quiet', { dmOff: true }));
  await setDoc(doc(f, 'chat_members/carol'), member('Carol', { agreedAt: null }));
  await setDoc(doc(f, 'chat_bans/banned'), { by: 'mod1', reason: 'spam', at: old });
  await setDoc(doc(f, 'chat_channels/general'), { name: 'general', order: 1 });
  await setDoc(doc(f, 'chat_channels/announcements'), { name: 'announcements', order: 0, modsPost: true });
  await setDoc(doc(f, 'chat_channels/testers'), { name: 'dungeon-descent-testers', order: 9, testersOnly: true });
  await setDoc(doc(f, 'chat_channels/testers/messages/m0'), { uid: 'tess', username: 'Tess', text: 'secret build', ts: old });
  await setDoc(doc(f, 'chat_members/alice/blocks/bob'), { at: old });
});

function post(u, path, text, extra = {}, name) {
  const d = db(u); const b = writeBatch(d);
  const id = 'm' + Math.random().toString(36).slice(2);
  b.set(doc(d, path + '/messages/' + id), { uid: u, username: name, text, ts: serverTimestamp(), ...extra });
  b.update(doc(d, 'chat_members/' + u), { lastPostAt: serverTimestamp() });
  return b.commit();
}
const names = { zed: 'Zed', alice: 'Alice', bob: 'Bob', mod1: 'Sebastian', tess: 'Tess', newbie: 'Newbie', banned: 'Baddie', carol: 'Carol', quiet: 'Quiet', [DEV]: 'Leonardo' };
const say = (u, path, text, extra) => post(u, path, text, extra, names[u]);
const wait = (ms) => new Promise(r => setTimeout(r, ms));

// Joining
function join(u, name, extra = {}) {
  return setDoc(doc(db(u), 'chat_members/' + u), { username: name, createdAt: serverTimestamp(), lastPostAt: serverTimestamp(), dmOff: false, ...extra });
}
await t('join with own username', join('zed', 'Zed'), true);
await t('join with someone else\'s username', join('erin', 'Alice'), false);
await t('join as moderator', join('frank', 'Frank', { mod: true }), false);
await t('join claiming a new username in the same batch', (() => {
  const d = db('gus'); const b = writeBatch(d);
  b.set(doc(d, 'usernames/gus'), { uid: 'gus', username: 'Gus' });
  b.set(doc(d, 'chat_members/gus'), { username: 'Gus', createdAt: serverTimestamp(), lastPostAt: serverTimestamp() });
  return b.commit();
})(), true);
await t('reserved name', (() => {
  const d = db('hal'); const b = writeBatch(d);
  b.set(doc(d, 'usernames/dd_admin'), { uid: 'hal', username: 'DD_Admin' });
  b.set(doc(d, 'chat_members/hal'), { username: 'DD_Admin', createdAt: serverTimestamp(), lastPostAt: serverTimestamp() });
  return b.commit();
})(), false);
await t('signed out reads members', getDoc(doc(db(), 'chat_members/alice')), false);
await t('zed agrees to the rules', updateDoc(doc(db('zed'), 'chat_members/zed'), { agreedAt: serverTimestamp() }), true);
await t('zed makes himself mod', updateDoc(doc(db('zed'), 'chat_members/zed'), { mod: true }), false);
await t('zed renames himself', updateDoc(doc(db('zed'), 'chat_members/zed'), { username: 'Alice' }), false);
await t('zed sets lastPostAt to the past', updateDoc(doc(db('zed'), 'chat_members/zed'), { lastPostAt: old }), false);
await t('zed is online (lastSeen now)', updateDoc(doc(db('zed'), 'chat_members/zed'), { lastSeen: serverTimestamp() }), true);
await t('zed fakes lastSeen in the future', updateDoc(doc(db('zed'), 'chat_members/zed'), { lastSeen: Timestamp.fromMillis(Date.now() + 864e5) }), false);
await t('zed appears offline (removes lastSeen)', updateDoc(doc(db('zed'), 'chat_members/zed'), { lastSeen: deleteField() }), true);
await t('alice marks zed online', updateDoc(doc(db('alice'), 'chat_members/zed'), { lastSeen: serverTimestamp() }), false);

// Posting in channels
await t('alice posts', say('alice', 'chat_channels/general', 'Hello everyone, who wants to co-op?'), true);
await t('alice posts again at once (rate limit)', say('alice', 'chat_channels/general', 'Anyone?'), false);
await t('bob bad word', say('bob', 'chat_channels/general', 'this is shit'), false);
await t('bob bad word variant', say('bob', 'chat_channels/general', 'FUCKING boss'), false);
await t('bob: "class" and "assassin" are fine', say('bob', 'chat_channels/general', 'My class is Assassin, best class'), true);
await t('as someone else', post('newbie', 'chat_channels/general', 'I am Alice', {}, 'Alice'), false);
await t('without updating lastPostAt', setDoc(doc(db('tess'), 'chat_channels/general/messages/x1'), { uid: 'tess', username: 'Tess', text: 'hi', ts: serverTimestamp() }), false);
await t('empty message', say('tess', 'chat_channels/general', ''), false);
await t('too long', say('tess', 'chat_channels/general', 'a'.repeat(1001)), false);
await t('extra field', say('tess', 'chat_channels/general', 'hi', { pinned: true }), false);
await t('banned player posts', say('banned', 'chat_channels/general', 'hello'), false);
await t('not agreed yet', say('carol', 'chat_channels/general', 'hello'), false);
await t('member posts announcement', say('tess', 'chat_channels/announcements', 'Free gold!'), false);
await t('moderator posts announcement', say('mod1', 'chat_channels/announcements', 'Version 12.2.1 is out!'), true);
await t('developer posts announcement', (async () => {
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'chat_members/' + DEV), { username: 'Leonardo', createdAt: old, lastPostAt: old, agreedAt: old }));
  return say(DEV, 'chat_channels/announcements', 'Welcome to Dungeon Descent Chat!');
})(), true);
await t('reply', say('newbie', 'chat_channels/general', 'Me!', { replyTo: 'm1' }), true);
await t('edit a message', (async () => {
  const id = 'edit1';
  await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'chat_channels/general/messages/' + id), { uid: 'bob', username: 'Bob', text: 'typo', ts: old }));
  return updateDoc(doc(db('bob'), 'chat_channels/general/messages/' + id), { text: 'shit' });
})(), false);
await t('delete own message', deleteDoc(doc(db('bob'), 'chat_channels/general/messages/edit1')), true);
await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'chat_channels/general/messages/del2'), { uid: 'bob', username: 'Bob', text: 'x', ts: old }));
await t('delete someone else\'s', deleteDoc(doc(db('alice'), 'chat_channels/general/messages/del2')), false);
await t('moderator deletes it', deleteDoc(doc(db('mod1'), 'chat_channels/general/messages/del2')), true);
await t('signed out reads general', getDocs(collection(db(), 'chat_channels/general/messages')), false);
await t('member reads general', getDocs(collection(db('bob'), 'chat_channels/general/messages')), true);
await t('member reads testers channel', getDocs(collection(db('bob'), 'chat_channels/testers/messages')), false);
await t('tester reads testers channel', getDocs(collection(db('tess'), 'chat_channels/testers/messages')), true);
await t('moderator reads testers channel', getDocs(collection(db('mod1'), 'chat_channels/testers/messages')), true);
await wait(2100);
await t('member posts in testers channel', say('bob', 'chat_channels/testers', 'let me in'), false);
await t('tester posts in testers channel', say('tess', 'chat_channels/testers', 'Build 125 works'), true);
await t('member makes a channel', setDoc(doc(db('alice'), 'chat_channels/mine'), { name: 'mine' }), false);
await t('developer makes a channel', setDoc(doc(db(DEV), 'chat_channels/strategy'), { name: 'strategy', order: 5 }), true);
await t('alice posts after 2 seconds', say('alice', 'chat_channels/general', 'Still here?'), true);

// Moderation
await t('mod makes bob a tester', updateDoc(doc(db('mod1'), 'chat_members/bob'), { tester: true }), true);
await t('mod makes bob a mod', updateDoc(doc(db('mod1'), 'chat_members/bob'), { mod: true }), false);
await t('dev makes Sebastian... a mod again', updateDoc(doc(db(DEV), 'chat_members/mod1'), { mod: true, trusted: true }), true);
await t('member bans', setDoc(doc(db('alice'), 'chat_bans/bob'), { by: 'alice', reason: 'x', at: serverTimestamp() }), false);
await t('mod bans', setDoc(doc(db('mod1'), 'chat_bans/zed'), { by: 'mod1', reason: 'spam', at: serverTimestamp() }), true);
await t('mod bans himself', setDoc(doc(db('mod1'), 'chat_bans/mod1'), { by: 'mod1', reason: 'x', at: serverTimestamp() }), false);
await t('banned unbans himself', deleteDoc(doc(db('banned'), 'chat_bans/banned')), false);
await t('mod unbans', deleteDoc(doc(db('mod1'), 'chat_bans/zed')), true);

// Private messages
const pair = (a, b) => [a, b].sort();
function startDm(u, other, name1, name2) {
  const m = pair(u, other);
  return setDoc(doc(db(u), 'chat_dms/' + m.join('_')), { members: m, names: { [u]: name1, [other]: name2 }, lastAt: serverTimestamp() });
}
await t('tess starts a DM with bob', startDm('tess', 'bob', 'Tess', 'Bob'), true);
await t('bob → alice (alice blocked bob)', startDm('bob', 'alice', 'Bob', 'Alice'), false);
await t('alice → bob (she blocked him)', startDm('alice', 'bob', 'Alice', 'Bob'), false);
await t('newbie starts a DM (one day wait)', startDm('newbie', 'alice', 'Newbie', 'Alice'), false);
await t('DM someone with DMs off', startDm('tess', 'quiet', 'Tess', 'Quiet'), false);
await t('banned starts a DM', startDm('banned', 'tess', 'Baddie', 'Tess'), false);
await t('DM with someone who isn\'t a member', startDm('tess', 'nobody', 'Tess', 'X'), false);
await t('DM between two others', setDoc(doc(db('tess'), 'chat_dms/alice_bob'), { members: ['alice', 'bob'], names: {}, lastAt: serverTimestamp() }), false);
await t('wrong conversation id', setDoc(doc(db('tess'), 'chat_dms/zzz'), { members: pair('tess', 'alice'), names: {}, lastAt: serverTimestamp() }), false);
await t('alice starts a DM with newbie', startDm('alice', 'newbie', 'Alice', 'Newbie'), true);
const tb = pair('tess', 'bob').join('_'), an = pair('alice', 'newbie').join('_');
await wait(2100);
await t('tess writes to bob', say('tess', 'chat_dms/' + tb, 'Hi Bob! Want to raid?'), true);
await t('bob reads it', getDocs(collection(db('bob'), 'chat_dms/' + tb + '/messages')), true);
await t('alice can\'t read it', getDocs(collection(db('alice'), 'chat_dms/' + tb + '/messages')), false);
await t('moderator can\'t read it', getDocs(collection(db('mod1'), 'chat_dms/' + tb + '/messages')), false);
await t('alice can\'t see the conversation', getDoc(doc(db('alice'), 'chat_dms/' + tb)), false);
await t('bob answers with a bad word', say('bob', 'chat_dms/' + tb, 'you suck, bitch'), false);
await t('bob answers', say('bob', 'chat_dms/' + tb, 'Sure, 10 minutes?'), true);
await t('newbie answers alice (new players can answer)', say('newbie', 'chat_dms/' + an, 'Hi Alice!'), true);
await t('alice writes into tess and bob\'s conversation', say('alice', 'chat_dms/' + tb, 'hi'), false);
await env.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), 'chat_members/bob/blocks/tess'), { at: old }));
await wait(2100);
await t('tess writes after bob blocked her', say('tess', 'chat_dms/' + tb, 'hello?'), false);
await t('bob\'s blocks are private', getDocs(collection(db('tess'), 'chat_members/bob/blocks')), false);
await t('alice blocks someone', setDoc(doc(db('alice'), 'chat_members/alice/blocks/tess'), { at: serverTimestamp() }), true);

// Group chats
const G = 'chat_groups/raiders';
const mkGroup = (u, name, members) => setDoc(doc(db(u), G.replace('raiders', name.replace(/\W/g, '').toLowerCase())),
  { name, owner: u, members, createdAt: serverTimestamp(), lastAt: serverTimestamp() });
await t('tess makes a group', mkGroup('tess', 'Raiders', { tess: 'Tess' }), true);
await t('newbie makes a group (one day wait)', mkGroup('newbie', 'Newbies', { newbie: 'Newbie' }), false);
await t('group with others already in it', mkGroup('tess', 'Crew', { tess: 'Tess', mod1: 'Sebastian' }), false);
await t('group owned by someone else', setDoc(doc(db('tess'), 'chat_groups/fake'), { name: 'Fake', owner: 'mod1', members: { tess: 'Tess' }, createdAt: serverTimestamp(), lastAt: serverTimestamp() }), false);
await t('bad group name', mkGroup('tess', 'Shit Squad', { tess: 'Tess' }), false);
await t('owner adds Sebastian', updateDoc(doc(db('tess'), G), { 'members.mod1': 'Sebastian', added: 'mod1' }), true);
await t('owner adds newbie', updateDoc(doc(db('tess'), G), { 'members.newbie': 'Newbie', added: 'newbie' }), true);
await t('owner adds two at once', updateDoc(doc(db('tess'), G), { 'members.zed': 'Zed', 'members.gus': 'Gus', added: 'zed' }), false);
await t('owner adds under a fake name', updateDoc(doc(db('tess'), G), { 'members.gus': 'Leonardo', added: 'gus' }), false);
await t('owner adds someone with DMs off', updateDoc(doc(db('tess'), G), { 'members.quiet': 'Quiet', added: 'quiet' }), false);
await t('owner adds someone who blocked them', updateDoc(doc(db('tess'), G), { 'members.bob': 'Bob', added: 'bob' }), false);
await t('owner adds a banned player', updateDoc(doc(db('tess'), G), { 'members.banned': 'Baddie', added: 'banned' }), false);
await t('member adds someone', updateDoc(doc(db('newbie'), G), { 'members.gus': 'Gus', added: 'gus' }), false);
await t('member renames the group', updateDoc(doc(db('newbie'), G), { name: 'Mine' }), false);
await t('owner renames it', updateDoc(doc(db('tess'), G), { name: 'Raid Night' }), true);
await t('outsider reads the group', getDoc(doc(db('alice'), G)), false);
await t('member reads the group', getDoc(doc(db('newbie'), G)), true);
await wait(2100);
await t('member writes in the group', say('mod1', G, 'Raid at 8?'), true);
await t('newbie writes in the group (new players can talk in groups)', say('newbie', G, 'Count me in'), true);
await t('outsider writes in the group', say('zed', G, 'hi'), false);
await t('outsider reads messages', getDocs(collection(db('alice'), G + '/messages')), false);
await t('member reads messages', getDocs(collection(db('newbie'), G + '/messages')), true);
await t('newbie removes Sebastian', updateDoc(doc(db('newbie'), G), { 'members.mod1': deleteField() }), false);
await t('newbie leaves', updateDoc(doc(db('newbie'), G), { 'members.newbie': deleteField() }), true);
await t('owner leaves without handing over', updateDoc(doc(db('tess'), G), { 'members.tess': deleteField() }), false);
await t('owner hands it to Sebastian', updateDoc(doc(db('tess'), G), { owner: 'mod1' }), true);
await t('new owner removes tess', updateDoc(doc(db('mod1'), G), { 'members.tess': deleteField() }), true);
await t('former member deletes it', deleteDoc(doc(db('tess'), G)), false);
await t('owner deletes it', deleteDoc(doc(db('mod1'), G)), true);

// Reports
const report = (u, extra = {}) => setDoc(doc(db(u), 'chat_reports/r' + Math.random().toString(36).slice(2)), {
  by: u, byName: names[u], kind: 'message', path: 'chat_channels/general/messages/x', author: 'bob', authorName: 'Bob',
  text: 'rude', context: [], reason: 'rude', at: serverTimestamp(), ...extra });
await t('member reports', report('alice'), true);
await t('report as someone else', report('alice', { by: 'tess' }), false);
await t('member reads reports', getDocs(collection(db('alice'), 'chat_reports')), false);
await t('moderator reads reports', getDocs(collection(db('mod1'), 'chat_reports')), true);

// Push settings and deleting your account
await t('own push settings', setDoc(doc(db('alice'), 'chat_members/alice/private/push'), { token: 'abc', sounds: { dm: 'sfx-ach-gold' } }), true);
await t('someone else\'s push settings', getDoc(doc(db('bob'), 'chat_members/alice/private/push')), false);
await t('delete own chat account', deleteDoc(doc(db('alice'), 'chat_members/alice')), true);
await t('delete someone else\'s', deleteDoc(doc(db('bob'), 'chat_members/tess')), false);

console.log(`${pass} passed, ${fail} failed`);
await env.cleanup();
process.exit(fail ? 1 : 0);
