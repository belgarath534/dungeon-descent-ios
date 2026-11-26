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
  try {
    if (req.method !== 'POST') { res.status(405).send('POST only'); return; }
    const m = (req.get('Authorization') || '').match(/^Bearer (.+)$/);
    if (!m) { res.status(401).json({ error: 'Missing auth token' }); return; }
    let uid;
    try { uid = (await admin.auth().verifyIdToken(m[1])).uid; }
    catch { res.status(401).json({ error: 'Invalid auth token' }); return; }
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
    let sent = 0;
    await Promise.all(prefsDocs.map(async (d) => {
      const id = d.ref.parent.parent.id;
      const p = d.data();
      if (id === uid || !p.token) return;
      const wants = kind === 'dm' ? p.dms !== false : kind === 'group' ? p.groups !== false : (p.channels || []).includes(room);
      if (!wants) return;
      if ((await db.doc('chat_members/' + id + '/blocks/' + uid).get()).exists) return;
      if (!(await allowed(id))) return;
      const body = kind === 'dm' ? text : from + ': ' + text;
      const payload = { aps: { alert: { title, body }, sound: soundFor(p, key), 'thread-id': kind + ':' + room },
                        kind, room };
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
