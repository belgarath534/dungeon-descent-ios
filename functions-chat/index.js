import { http } from '@google-cloud/functions-framework';
import admin from 'firebase-admin';
import { getFirestore } from 'firebase-admin/firestore';
import crypto from 'node:crypto';
import http2 from 'node:http2';

// Dungeon Descent Chat's push notifications.
//
// After sending a message, the app calls this with its sign-in token and the
// room ({ kind: "channel" | "dm" | "group", room: id }). The newest message
// by that player in that room (from the last minute) is what's announced, so
// nobody can make it notify text they didn't post. Everyone who asked for
// that room (chat_members/{uid}/private/push) gets an Apple push with their
// chosen game sound, except the sender and anyone who blocked them.
//
// Config: APNS_KEY (secret, the team's .p8; shared with liveActivity),
// APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC (default com.dungeon.descent.chat).

admin.initializeApp();
const db = getFirestore(admin.app(), 'dungeon-descent');
const TOPIC = process.env.APNS_TOPIC || 'com.dungeon.descent.chat';

let jwtCache = { token: '', at: 0 };
function apnsJwt() {
  const now = Math.floor(Date.now() / 1000);
  if (jwtCache.token && now - jwtCache.at < 40 * 60) return jwtCache.token;
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const data = b64({ alg: 'ES256', kid: process.env.APNS_KEY_ID }) + '.' + b64({ iss: process.env.APNS_TEAM_ID, iat: now });
  const sig = crypto.sign('sha256', Buffer.from(data), { key: process.env.APNS_KEY, dsaEncoding: 'ieee-p1363' });
  jwtCache = { token: data + '.' + sig.toString('base64url'), at: now };
  return jwtCache.token;
}

const sessions = {};
function apnsSession(host) {
  const s = sessions[host];
  if (s && !s.closed && !s.destroyed) return s;
  const n = http2.connect('https://' + host);
  n.on('error', () => { delete sessions[host]; });
  n.on('goaway', () => { delete sessions[host]; });
  sessions[host] = n;
  return n;
}

function push(token, payload, sandbox, collapse) {
  const host = sandbox ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
  return new Promise((resolve) => {
    const req = apnsSession(host).request({
      ':method': 'POST', ':path': '/3/device/' + token,
      authorization: 'bearer ' + apnsJwt(),
      'apns-push-type': 'alert', 'apns-topic': TOPIC, 'apns-priority': '10',
      ...(collapse ? { 'apns-collapse-id': collapse.slice(0, 64) } : {}),
      'content-type': 'application/json',
    });
    let status = 0, body = '';
    req.on('response', (h) => { status = h[':status']; });
    req.on('data', (c) => { body += c; });
    req.on('end', () => resolve({ status, body }));
    req.on('error', (e) => resolve({ status: 0, body: String(e) }));
    req.setTimeout(10000, () => { req.close(); resolve({ status: 0, body: 'timeout' }); });
    req.end(JSON.stringify(payload));
  });
}

// The sound a person chose for this room ("" = the iPhone's own).
function soundFor(prefs, key) {
  const s = prefs.sounds || {};
  const own = prefs.custom ? s[key] : null;
  const name = own && own !== 'default' ? own : (s.default ?? 'dd-ach-gold');
  return name ? name + '.caf' : 'default';
}

http('chatPush', async (req, res) => {
  // The web chat (chat.html) calls this from the browser: allow it. Every
  // call still needs a player's Firebase sign-in token.
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') { res.status(204).send(''); return; }
  try {
    if (req.method !== 'POST') { res.status(405).send('POST only'); return; }
    const m = (req.get('Authorization') || '').match(/^Bearer (.+)$/);
    if (!m) { res.status(401).json({ error: 'Missing auth token' }); return; }
    let uid;
    try { uid = (await admin.auth().verifyIdToken(m[1])).uid; }
    catch { res.status(401).json({ error: 'Invalid auth token' }); return; }
    const route = (req.path || '').replace(/\/+$/, '');
    if (route.endsWith('/legend')) return await legend(uid, req.body || {}, res);
    if (route.endsWith('/react')) return await reaction(uid, req.body || {}, res);
    const { kind, room } = req.body || {};
    if (!['channel', 'dm', 'group'].includes(kind) || typeof room !== 'string' || !/^[\w-]{1,128}$/.test(room)) {
      res.status(400).json({ error: 'Bad room' }); return;
    }
    const path = (kind === 'channel' ? 'chat_channels/' : kind === 'dm' ? 'chat_dms/' : 'chat_groups/') + room;
    const roomDoc = await db.doc(path).get();
    if (!roomDoc.exists) { res.status(404).json({ error: 'No such room' }); return; }
    const r = roomDoc.data();

    // The sender's newest message here, from the last minute.
    const recent = await db.collection(path + '/messages').orderBy('ts', 'desc').limit(20).get();
    const msg = recent.docs.find((d) => d.get('uid') === uid);
    if (!msg || Date.now() - msg.get('ts').toMillis() > 60000) { res.json({ sent: 0, note: 'no recent message' }); return; }
    if (msg.get('pushed')) { res.json({ sent: 0, note: 'already sent' }); return; }
    await msg.ref.update({ pushed: true }).catch(() => {});
    const from = msg.get('username') || 'Someone';
    const text = String(msg.get('text') || '').slice(0, 300);

    // Who's in the room, and who asked to be told.
    let members = null, key = kind, title = '', allowed = () => true;
    if (kind === 'dm') { members = r.members || []; title = from; key = 'dm'; }
    else if (kind === 'group') { members = Object.keys(r.members || {}); title = r.name || 'Group'; key = 'group'; }
    else {
      title = '#' + (r.name || room); key = room;
      if (r.testersOnly) {
        allowed = async (id) => { const d = (await db.doc('chat_members/' + id).get()).data() || {};
          return d.mod === true || d.tester === true || id === 'WgqZGmnPKeYIymlMkx0aAg8G2T52'; };
      }
    }
    const prefsDocs = members
      ? (await Promise.all(members.filter((id) => id !== uid).map((id) => db.doc('chat_members/' + id + '/private/push').get()))).filter((d) => d.exists)
      : (await db.collectionGroup('private').get()).docs.filter((d) => d.id === 'push');
    // @mentions: those players hear about it even if they don't follow the room.
    const mentioned = new Set();
    for (const [, name] of text.matchAll(/@([A-Za-z0-9_]{3,20})\b/g)) {
      const n = await db.doc('usernames/' + name.toLowerCase()).get();
      if (n.exists && n.get('uid') !== uid) mentioned.add(n.get('uid'));
    }
    // A reply: the person replied to hears about it too.
    let replyUid = null;
    const replyTo = msg.get('replyTo');
    if (typeof replyTo === 'string' && /^[\w-]{1,128}$/.test(replyTo)) {
      const orig = await db.doc(path + '/messages/' + replyTo).get();
      const author = orig.exists ? (orig.get('uid') === 'hall-of-legends' ? orig.get('about') : orig.get('uid')) : null;
      if (typeof author === 'string' && author !== uid) replyUid = author;
    }
    const whereName = kind === 'channel' ? title : kind === 'group' ? title : 'a private message';
    // Activity (chat_members/{uid}/activity): mentions and replies, for
    // whoever can read this room and hasn't blocked the sender.
    const targets = new Map();
    for (const id of mentioned) targets.set(id, 'mention');
    if (replyUid) targets.set(replyUid, 'reply');
    await Promise.all([...targets].map(async ([id, type]) => {
      if (members ? !members.includes(id) : !(await allowed(id))) return;
      if (!(await db.doc('chat_members/' + id).get()).exists) return;
      if ((await db.doc('chat_members/' + id + '/blocks/' + uid).get()).exists) return;
      await db.doc('chat_members/' + id + '/activity/' + type + '_' + msg.id).set({
        type, from, fromUid: uid, text: text.slice(0, 200), kind, room, where: whereName, mid: msg.id,
        ts: admin.firestore.FieldValue.serverTimestamp() });
    })).catch((e) => console.warn('activity', e));
    let sent = 0;
    await Promise.all(prefsDocs.map(async (d) => {
      const id = d.ref.parent.parent.id;
      const p = d.data();
      if (id === uid || !p.token) return;
      const isMention = mentioned.has(id);
      const isReply = id === replyUid;
      const wants = isMention || isReply || (kind === 'dm' ? p.dms !== false : kind === 'group' ? p.groups !== false : (p.channels || []).includes(room));
      if (!wants) return;
      if ((await db.doc('chat_members/' + id + '/blocks/' + uid).get()).exists) return;
      if (!(await allowed(id))) return;
      const body = kind === 'dm' ? text : from + ': ' + text;
      const where = whereName;
      const heading = isReply && kind !== 'dm' ? from + ' replied to you in ' + where : isMention ? from + ' mentioned you in ' + where : title;
      const payload = { aps: { alert: { title: heading, body },
                               sound: soundFor(p, key), 'thread-id': kind + ':' + room },
                        kind, room, mid: msg.id };
      const out = await push(p.token, payload, p.env === 'sandbox', null);
      if (out.status === 200) sent++;
      else if (out.status === 410 || /BadDeviceToken|Unregistered/.test(out.body)) await d.ref.update({ token: admin.firestore.FieldValue.delete() }).catch(() => {});
      else console.warn('APNs', out.status, out.body);
    }));
    res.json({ sent });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e && e.message || e) });
  }
});

// ── #hall-of-legends: big moments posted by the game ──
//
// The game (signed in) calls /legend with an event; the post is written
// here, from a fixed sentence per event (never the player's own text), as
// "Hall of Legends", at most once every 10 minutes per player, and only for
// chat members who haven't turned it off (private/push: legends false).
// GameData.dungeons in DungeonCore (the same names as the web version).
const DUNGEONS = ['Crypt of Malachar', 'The Ashbound Wastes', 'Frosthold Abyss', 'The Sunken Archives', 'The Hollow',
  'The Whispering Forest', 'The Infernal Descent', 'The Abyssal Deep', 'The Shadow World'];
const DIFFICULTIES = ['Wanderer', 'Ironblood', 'Condemned', 'Forsaken', 'Nightmare', 'Insane'];
const LEGEND_ROOM = 'hall-of-legends';

async function legend(uid, b, res) {
  const memberDoc = await db.doc('chat_members/' + uid).get();
  if (!memberDoc.exists) { res.json({ posted: false, note: 'not a chat member' }); return; }
  const member = memberDoc.data();
  if ((await db.doc('chat_bans/' + uid).get()).exists) { res.json({ posted: false, note: 'banned' }); return; }
  const prefs = (await db.doc('chat_members/' + uid + '/private/push').get()).data() || {};
  if (prefs.legends === false) { res.json({ posted: false, note: 'turned off' }); return; }
  const last = member.lastLegendAt ? member.lastLegendAt.toMillis() : 0;
  if (Date.now() - last < 10 * 60 * 1000) { res.json({ posted: false, note: 'too soon' }); return; }
  const name = member.username;
  const cls = typeof b.cls === 'string' && /^[A-Za-z ]{2,20}$/.test(b.cls) ? b.cls : null;
  const floor = Number.isInteger(b.floor) ? b.floor : 0;
  let text = null;
  if (b.event === 'victory' && DUNGEONS.includes(b.dungeon) && DIFFICULTIES.includes(b.difficulty))
    text = `🏆 ${name} conquered ${b.dungeon} on ${b.difficulty}` + (cls ? ` as a ${cls}!` : '!');
  else if (b.event === 'endless' && floor >= 25 && floor % 25 === 0 && floor <= 100000)
    text = `⬇️ ${name} reached floor ${floor} in Endless Descent!`;
  else if (b.event === 'spire' && floor >= 10 && floor % 10 === 0 && floor <= 10000)
    text = `🗼 ${name} climbed to floor ${floor} of The Spire!`;
  if (!text) { res.status(400).json({ error: 'Unknown event' }); return; }
  const chan = await db.doc('chat_channels/' + LEGEND_ROOM).get();
  if (!chan.exists) { res.json({ posted: false, note: 'no hall-of-legends channel' }); return; }
  await db.collection('chat_channels/' + LEGEND_ROOM + '/messages').add({
    uid: 'hall-of-legends', username: 'Hall of Legends', text, about: uid, ts: admin.firestore.FieldValue.serverTimestamp(), pushed: true });
  await memberDoc.ref.update({ lastLegendAt: admin.firestore.FieldValue.serverTimestamp() });
  // Notify whoever follows #hall-of-legends (not the player it's about).
  const docs = (await db.collectionGroup('private').get()).docs.filter((d) => d.id === 'push');
  let sent = 0;
  await Promise.all(docs.map(async (d) => {
    const id = d.ref.parent.parent.id, p = d.data();
    if (id === uid || !p.token || !(p.channels || []).includes(LEGEND_ROOM)) return;
    const payload = { aps: { alert: { title: '#' + (chan.get('name') || LEGEND_ROOM), body: text }, sound: soundFor(p, LEGEND_ROOM),
                             'thread-id': 'channel:' + LEGEND_ROOM }, kind: 'channel', room: LEGEND_ROOM };
    const out = await push(p.token, payload, p.env === 'sandbox', null);
    if (out.status === 200) sent++;
  }));
  res.json({ posted: true, sent });
}

// ── Reactions: "Sebastian reacted 🔥 to your message" ──
//
// After reacting (or taking a reaction back), the app calls /react with
// { kind, room, mid }. The reaction is read from the message itself, so
// nobody can claim one they didn't make. The message's author gets an
// Activity item (one per person per message: a new emoji replaces it) and,
// unless they turned it off (private/push: reactions false), a push. A
// Hall of Legends post counts as the player it's about.
async function reaction(uid, b, res) {
  const { kind, room, mid } = b;
  if (!['channel', 'dm', 'group'].includes(kind) || typeof room !== 'string' || !/^[\w-]{1,128}$/.test(room)
      || typeof mid !== 'string' || !/^[\w-]{1,128}$/.test(mid)) { res.status(400).json({ error: 'Bad message' }); return; }
  const path = (kind === 'channel' ? 'chat_channels/' : kind === 'dm' ? 'chat_dms/' : 'chat_groups/') + room;
  const [roomDoc, msg, me] = await Promise.all([db.doc(path).get(), db.doc(path + '/messages/' + mid).get(), db.doc('chat_members/' + uid).get()]);
  if (!roomDoc.exists || !msg.exists || !me.exists) { res.status(404).json({ error: 'No such message' }); return; }
  const author = msg.get('uid') === 'hall-of-legends' ? msg.get('about') : msg.get('uid');
  if (typeof author !== 'string' || author === uid) { res.json({ sent: 0, note: 'your own message' }); return; }
  const r = roomDoc.data();
  if (kind === 'dm' && !(r.members || []).includes(author)) { res.json({ sent: 0 }); return; }
  if (kind === 'group' && !(r.members || {})[author]) { res.json({ sent: 0 }); return; }
  const ref = db.doc('chat_members/' + author + '/activity/react_' + mid + '_' + uid);
  const emoji = (msg.get('reactions') || {})[uid];
  if (!emoji) { await ref.delete().catch(() => {}); res.json({ sent: 0, note: 'removed' }); return; }
  if ((await db.doc('chat_members/' + author + '/blocks/' + uid).get()).exists) { res.json({ sent: 0 }); return; }
  const from = me.get('username') || 'Someone';
  const where = kind === 'channel' ? '#' + (r.name || room) : kind === 'group' ? (r.name || 'Group') : 'a private message';
  const text = String(msg.get('text') || '').slice(0, 200);
  const before = await ref.get();
  if (before.exists && before.get('emoji') === emoji) { res.json({ sent: 0, note: 'same' }); return; }
  await ref.set({ type: 'reaction', emoji, from, fromUid: uid, text, kind, room, where, mid, ts: admin.firestore.FieldValue.serverTimestamp() });
  const p = (await db.doc('chat_members/' + author + '/private/push').get()).data() || {};
  if (!p.token || p.reactions === false) { res.json({ sent: 0 }); return; }
  const names = { '👍': 'thumbs up', '❤️': 'heart', '😂': 'laughing', '🔥': 'fire', '😮': 'wow', '😢': 'sad' };
  const payload = { aps: { alert: { title: from + ' reacted ' + emoji + ' to your message', body: text },
                           sound: soundFor(p, 'reactions'), 'thread-id': 'activity' },
                    kind, room, mid, reaction: names[emoji] || emoji };
  const out = await push(p.token, payload, p.env === 'sandbox', 'react-' + mid);
  res.json({ sent: out.status === 200 ? 1 : 0 });
}
