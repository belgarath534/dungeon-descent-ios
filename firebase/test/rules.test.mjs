import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { doc, setDoc, updateDoc, deleteDoc, getDoc, getDocs, collection, writeBatch, deleteField, increment, addDoc } from 'firebase/firestore';

const env = await initializeTestEnvironment({ projectId: 'demo-dd', firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8085 } });
const DEV = 'WgqZGmnPKeYIymlMkx0aAg8G2T52';
const cache = {};
const db = (u) => cache[u ?? '-'] ??= (u ? env.authenticatedContext(u) : env.unauthenticatedContext()).firestore();
let pass = 0, fail = 0;
async function t(name, p, ok) {
  try { await (ok ? assertSucceeds(p) : assertFails(p)); pass++; }
  catch (e) { fail++; console.log('FAIL', name, e.message.slice(0, 200)); }
}

// Community enemies
await env.withSecurityRulesDisabled(async c => {
  const f = c.firestore();
  await setDoc(doc(f, 'community_enemies/e1'), { name: 'Rat', desc: 'd', type: 'common', icon: '👤', hp: 30, atk: 4, def: 1, kills: 0, approved: true, ownerUid: 'alice' });
  await setDoc(doc(f, 'community_enemies/old'), { name: 'Old', desc: 'd', type: 'common', icon: '👤', hp: 30, atk: 4, def: 1, kills: 2, approved: true });
});
await t('kill +1 anon', updateDoc(doc(db(), 'community_enemies/e1'), { kills: 1 }), true);
await t('kill +2 anon', updateDoc(doc(db(), 'community_enemies/e1'), { kills: 3 }), false);
await t('owner rename', updateDoc(doc(db('alice'), 'community_enemies/e1'), { name: 'Big Rat', hp: 500, atk: 50, def: 15, type: 'boss', editedAt: 1 }), true);
await t('owner too strong', updateDoc(doc(db('alice'), 'community_enemies/e1'), { hp: 9999 }), false);
await t('owner changes kills', updateDoc(doc(db('alice'), 'community_enemies/e1'), { name: 'x', kills: 99 }), false);
await t('owner changes ownerUid', updateDoc(doc(db('alice'), 'community_enemies/e1'), { ownerUid: 'bob' }), false);
await t('other edits', updateDoc(doc(db('bob'), 'community_enemies/e1'), { name: 'Mine now' }), false);
await t('anon edits', updateDoc(doc(db(), 'community_enemies/e1'), { name: 'Mine now' }), false);
await t('owner deletes (approved off)', updateDoc(doc(db('alice'), 'community_enemies/e1'), { approved: false, deletedByOwner: true, moderatedAt: 1 }), true);
await t('owner re-approves', updateDoc(doc(db('alice'), 'community_enemies/e1'), { approved: true }), false);
await t('unowned by player', updateDoc(doc(db('alice'), 'community_enemies/old'), { name: 'Claimed' }), false);
await t('dev edits unowned', updateDoc(doc(db(DEV), 'community_enemies/old'), { name: 'Fixed', hp: 40, editedAt: 2 }), true);
await t('hard delete', deleteDoc(doc(db('alice'), 'community_enemies/e1')), false);

// Guilds
function create(u, gid, name, extra = {}) {
  const d = db(u); const b = writeBatch(d);
  b.set(doc(d, 'guildNames/' + name.toLowerCase()), { gid, uid: u });
  b.set(doc(d, 'guilds/' + gid), { name, nameKey: name.toLowerCase(), desc: '', leader: u, leaderName: u, members: { [u]: u }, createdAt: 1, week: '2026-W48', weekDamage: 0, ...extra });
  return b.commit();
}
await t('create guild', create('alice', 'g1', 'Iron Wolves'), true);
await t('same name taken', create('bob', 'g2', 'Iron Wolves'), false);
await t('bad name chars', create('bob', 'g3', 'Wolves#Den'), false);
await t('guild without name doc', setDoc(doc(db('bob'), 'guilds/g4'), { name: 'Lone', nameKey: 'lone', desc: '', leader: 'bob', leaderName: 'b', members: { bob: 'b' }, createdAt: 1, week: 'w', weekDamage: 0 }), false);
await t('create with others as members', create('bob', 'g5', 'Crew', { members: { bob: 'b', carol: 'c' } }), false);
await t('create with damage', create('bob', 'g6', 'Cheaters', { weekDamage: 9999 }), false);
await t('anon create', create(null, 'g7', 'Ghosts'), false);
await t('bob joins', updateDoc(doc(db('bob'), 'guilds/g1'), { 'members.bob': 'Bob' }), true);
await t('bob adds carol', updateDoc(doc(db('bob'), 'guilds/g1'), { 'members.carol': 'Carol' }), false);
await t('bob long name', updateDoc(doc(db('erin'), 'guilds/g1'), { 'members.erin': 'x'.repeat(21) }), false);
await t('bob changes desc', updateDoc(doc(db('bob'), 'guilds/g1'), { desc: 'hacked' }), false);
await t('bob makes himself leader', updateDoc(doc(db('bob'), 'guilds/g1'), { leader: 'bob' }), false);
await t('leader desc', updateDoc(doc(db('alice'), 'guilds/g1'), { desc: 'We hunt.' }), true);
await t('leader adds dave', updateDoc(doc(db('alice'), 'guilds/g1'), { 'members.dave': 'Dave' }), false);
await t('leader renames guild', updateDoc(doc(db('alice'), 'guilds/g1'), { name: 'Other' }), false);
await t('leader leaves', updateDoc(doc(db('alice'), 'guilds/g1'), { 'members.alice': deleteField() }), false);
await t('bob strikes 3000', updateDoc(doc(db('bob'), 'guilds/g1'), { weekDamage: increment(3000) }), true);
await t('bob strikes 6000', updateDoc(doc(db('bob'), 'guilds/g1'), { weekDamage: increment(6000) }), false);
await t('bob lowers damage', updateDoc(doc(db('bob'), 'guilds/g1'), { weekDamage: 10 }), false);
await t('new week reset', updateDoc(doc(db('bob'), 'guilds/g1'), { week: '2026-W49', weekDamage: 2000 }), true);
await t('outsider damage', updateDoc(doc(db('zed'), 'guilds/g1'), { weekDamage: increment(100) }), false);
// Chat
await t('member posts', setDoc(doc(db('bob'), 'guilds/g1/chat/m1'), { uid: 'bob', username: 'Bob', message: 'hi', timestamp: 1 }), true);
await t('post as someone else', setDoc(doc(db('bob'), 'guilds/g1/chat/m2'), { uid: 'alice', username: 'A', message: 'hi', timestamp: 1 }), false);
await t('outsider posts', setDoc(doc(db('zed'), 'guilds/g1/chat/m3'), { uid: 'zed', username: 'Z', message: 'hi', timestamp: 1 }), false);
await t('long message', setDoc(doc(db('bob'), 'guilds/g1/chat/m4'), { uid: 'bob', username: 'Bob', message: 'x'.repeat(201), timestamp: 1 }), false);
await t('member reads chat', getDocs(collection(db('alice'), 'guilds/g1/chat')), true);
await t('outsider reads chat', getDocs(collection(db('zed'), 'guilds/g1/chat')), false);
await t('anon reads chat', getDocs(collection(db(), 'guilds/g1/chat')), false);
await t('anyone reads guild', getDoc(doc(db(), 'guilds/g1')), true);
await setDoc(doc(db('alice'), 'guilds/g1/chat/a1'), { uid: 'alice', username: 'A', message: 'yo', timestamp: 1 });
await t('member deletes other msg', deleteDoc(doc(db('bob'), 'guilds/g1/chat/a1')), false);
await t('leader deletes msg', deleteDoc(doc(db('alice'), 'guilds/g1/chat/m1')), true);
// Boss hits
await t('own hit', setDoc(doc(db('bob'), 'guilds/g1/boss/2026-W49/hits/bob'), { damage: increment(1200), name: 'Bob', updatedAt: 1 }, { merge: true }), true);
await t('own hit again', setDoc(doc(db('bob'), 'guilds/g1/boss/2026-W49/hits/bob'), { damage: increment(900), name: 'Bob', updatedAt: 2 }, { merge: true }), true);
await t('huge hit', setDoc(doc(db('bob'), 'guilds/g1/boss/2026-W49/hits/bob'), { damage: increment(9000), name: 'Bob', updatedAt: 3 }, { merge: true }), false);
await t('hit for alice by bob', setDoc(doc(db('bob'), 'guilds/g1/boss/2026-W49/hits/alice'), { damage: 100, name: 'A', updatedAt: 1 }), false);
await t('outsider hit', setDoc(doc(db('zed'), 'guilds/g1/boss/2026-W49/hits/zed'), { damage: 100, name: 'Z', updatedAt: 1 }), false);
// Membership, leadership, disband
await t('leader removes bob', updateDoc(doc(db('alice'), 'guilds/g1'), { 'members.bob': deleteField() }), true);
await updateDoc(doc(db('bob'), 'guilds/g1'), { 'members.bob': 'Bob' });
await t('pass to non-member', updateDoc(doc(db('alice'), 'guilds/g1'), { leader: 'zed', leaderName: 'Z' }), false);
await t('pass leadership', updateDoc(doc(db('alice'), 'guilds/g1'), { leader: 'bob', leaderName: 'Bob' }), true);
await t('old leader leaves', updateDoc(doc(db('alice'), 'guilds/g1'), { 'members.alice': deleteField() }), true);
await t('non-leader disbands', (async () => { const d = db('alice'); const b = writeBatch(d); b.delete(doc(d, 'guildNames/iron wolves')); b.delete(doc(d, 'guilds/g1')); await b.commit(); })(), false);
await t('leader disbands', (async () => { const d = db('bob'); const b = writeBatch(d); b.delete(doc(d, 'guildNames/iron wolves')); b.delete(doc(d, 'guilds/g1')); await b.commit(); })(), true);
// 20 members cap
await env.withSecurityRulesDisabled(async c => {
  const m = {}; for (let i = 0; i < 20; i++) m['u' + i] = 'U' + i;
  await setDoc(doc(c.firestore(), 'guilds/full'), { name: 'Full', nameKey: 'full', desc: '', leader: 'u0', leaderName: 'U0', members: m, createdAt: 1, week: 'w', weekDamage: 0 });
});
await t('21st member', updateDoc(doc(db('late'), 'guilds/full'), { 'members.late': 'Late' }), false);
await t('dev removes guild', deleteDoc(doc(db(DEV), 'guilds/full')), true);
// Existing rules still hold
await t('read other save', getDoc(doc(db('bob'), 'saves/alice')), false);
console.log(`${pass} passed, ${fail} failed`);
await env.cleanup();
process.exit(fail ? 1 : 0);
