// The Realtime Database rules (database.rules.json) in the emulator: chat
// messages can be added but not changed or wiped, rooms work one at a time
// but the whole list can't be erased, and the shared Void Reaper still works.
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';

const env = await initializeTestEnvironment({
  projectId: 'demo-dd',
  database: { rules: readFileSync(new URL('../database.rules.json', import.meta.url), 'utf8'), host: '127.0.0.1', port: 9000 },
});
const DEV = 'WgqZGmnPKeYIymlMkx0aAg8G2T52';
const cache = {};
const db = (u) => cache[u ?? '-'] ??= (u ? env.authenticatedContext(u) : env.unauthenticatedContext()).database();
let pass = 0, fail = 0;
async function t(name, p, ok) {
  try { await (ok ? assertSucceeds(p) : assertFails(p)); pass++; }
  catch (e) { fail++; console.log('FAIL', name, e.message.slice(0, 200)); }
}
const msg = { username: 'Leo', message: 'hi', timestamp: Date.now() };

await t('post chat (signed out)', db().ref('global_chat/m1').set(msg), true);
await t('post with push', db().ref('global_chat').push(msg), true);
await t('void event message', db().ref('global_chat').push({ username: '⚔ VOID EVENT', message: 'It wakes.', timestamp: 1, system: true }), true);
await t('read chat', db().ref('global_chat').orderByChild('timestamp').limitToLast(50).once('value'), true);
await t('edit someone else\'s message', db().ref('global_chat/m1/message').set('changed'), false);
await t('overwrite a message', db().ref('global_chat/m1').set({ ...msg, message: 'changed' }), false);
await t('delete a message', db().ref('global_chat/m1').remove(), false);
await t('wipe the chat', db().ref('global_chat').remove(), false);
await t('long message', db().ref('global_chat').push({ ...msg, message: 'x'.repeat(201) }), false);
await t('long name', db().ref('global_chat').push({ ...msg, username: 'x'.repeat(21) }), false);
await t('no timestamp', db().ref('global_chat').push({ username: 'Leo', message: 'hi' }), false);
await t('developer deletes a message', db(DEV).ref('global_chat/m1').remove(), true);

await t('make a pvp room', db().ref('pvp_rooms/AB12').set({ host: { name: 'Leo' }, state: 'waiting' }), true);
await t('join it', db().ref('pvp_rooms/AB12').update({ guest: { name: 'Mia' } }), true);
await t('ready', db().ref('pvp_rooms/AB12/guest/ready').set(true), true);
await t('co-op room', db().ref('pvp_rooms/coop_XY9Z').set({ host: 'Leo', max: 5 }), true);
await t('read a room', db().ref('pvp_rooms/AB12').once('value'), true);
await t('close a room', db().ref('pvp_rooms/AB12').remove(), true);
await t('wipe every room', db().ref('pvp_rooms').remove(), false);
await t('overwrite every room', db().ref('pvp_rooms').set({ x: 1 }), false);
await t('hide and seek room', db().ref('hs_rooms/QQ11').set({ host: 'Leo' }), true);
await t('wipe hide and seek', db().ref('hs_rooms').remove(), false);
await t('presence', db().ref('presence/abc123').set({ online: true, t: 1 }), true);
await t('leave presence', db().ref('presence/abc123').remove(), true);
await t('wipe presence', db().ref('presence').remove(), false);
await t('void reaper state', db().ref('void_reaper').set({ awake: true, currentHp: 100 }), true);
await t('void reaper hit', db().ref('void_reaper').update({ currentHp: 90 }), true);
await t('somewhere else', db().ref('other/x').set(1), false);

console.log(`${pass} passed, ${fail} failed`);
await env.cleanup();
process.exit(fail ? 1 : 0);
