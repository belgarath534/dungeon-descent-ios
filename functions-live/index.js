import { http } from '@google-cloud/functions-framework';
import admin from 'firebase-admin';
import { CloudTasksClient } from '@google-cloud/tasks';
import crypto from 'node:crypto';
import http2 from 'node:http2';

// Endless Descent's Live Activity, kept current while the app is closed.
//
// iOS pauses the app soon after you leave it, so it can't update its own
// Live Activity. When you leave mid-run, the app works out the next fights
// ahead of time (the same rolls it will use when you come back) and sends
// them here as a plan. Each fight becomes a Cloud Task due at that fight's
// time, which calls /send, which pushes that fight's state to the Lock
// Screen through Apple's push service. A newer plan (you used a potion from
// the watch, or opened the app) replaces the old one: older tasks see a
// different planId and do nothing.
//
// Config (Cloud Run env / secrets): APNS_KEY (the .p8, a secret),
// APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC (the app's bundle ID).

admin.initializeApp();
const db = admin.firestore();
const tasks = new CloudTasksClient();

const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || 'dungeon-descent-fbaf2';
const QUEUE = tasks.queuePath(PROJECT, 'us-central1', 'live-activity');
const MAX_STATES = 600;          // 2.5 hours at one fight every 15 seconds
const TOPIC = (process.env.APNS_TOPIC || 'com.dungeon.descent') + '.push-type.liveactivity';

const sign = (body) => crypto.createHmac('sha256', process.env.APNS_KEY || '').update(body).digest('hex');

// ── Apple push ──

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

function push(token, payload, priority, sandbox) {
  const host = sandbox ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
  return new Promise((resolve) => {
    const req = apnsSession(host).request({
      ':method': 'POST',
      ':path': '/3/device/' + token,
      authorization: 'bearer ' + apnsJwt(),
      'apns-push-type': 'liveactivity',
      'apns-topic': TOPIC,
      'apns-priority': String(priority),
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

// ── Endpoints ──

http('liveActivity', async (req, res) => {
  if (req.method !== 'POST') { res.status(405).send('POST only'); return; }
  const path = (req.path || '/').replace(/\/+$/, '');
  try {
    if (path.endsWith('/send')) return await send(req, res);
    return await plan(req, res);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e && e.message || e) });
  }
});

// The app's plan: { token, planId, sandbox, states: [{ at, state, alert?, end? }] }.
// No states cancels whatever is queued (the app is open again).
async function plan(req, res) {
  const m = (req.get('Authorization') || '').match(/^Bearer (.+)$/);
  if (!m) { res.status(401).json({ error: 'Missing auth token' }); return; }
  let uid;
  try { uid = (await admin.auth().verifyIdToken(m[1])).uid; }
  catch { res.status(401).json({ error: 'Invalid auth token' }); return; }

  const b = req.body || {};
  const planId = String(b.planId || '').slice(0, 64);
  const token = String(b.token || '').replace(/[^0-9a-fA-F]/g, '').slice(0, 200);
  const states = Array.isArray(b.states) ? b.states.slice(0, MAX_STATES) : [];
  if (!planId) { res.status(400).json({ error: 'Missing planId' }); return; }

  await db.collection('liveActivity').doc(uid).set({
    planId, token, updatedAt: admin.firestore.FieldValue.serverTimestamp(), count: states.length,
  });
  if (!token || !states.length) { res.json({ ok: true, queued: 0 }); return; }

  // This function's own /send. Through cloudfunctions.net its name is part
  // of the path; on its run.app address it isn't.
  const host = req.get('host');
  const url = 'https://' + host + (host.endsWith('cloudfunctions.net') ? '/liveActivity/send' : '/send');
  const now = Date.now() / 1000;
  const jobs = states.filter((s) => s && typeof s.at === 'number' && s.state && s.at > now - 5 && s.at < now + 6 * 3600);
  let queued = 0;
  for (let i = 0; i < jobs.length; i += 25) {
    await Promise.all(jobs.slice(i, i + 25).map(async (s) => {
      const body = JSON.stringify({ uid, planId, token, sandbox: !!b.sandbox, at: s.at, state: s.state,
                                    alert: s.alert ? String(s.alert).slice(0, 200) : null, end: !!s.end });
      await tasks.createTask({ parent: QUEUE, task: {
        scheduleTime: { seconds: Math.floor(s.at), nanos: Math.round((s.at % 1) * 1e9) },
        httpRequest: { httpMethod: 'POST', url, headers: { 'Content-Type': 'application/json', 'X-Sig': sign(body) },
                       body: Buffer.from(body).toString('base64') },
      } });
      queued++;
    }));
  }
  res.json({ ok: true, queued });
}

// One fight's update, from its Cloud Task.
async function send(req, res) {
  const raw = req.rawBody ? req.rawBody.toString() : JSON.stringify(req.body);
  const sig = req.get('X-Sig') || '';
  const want = sign(raw);
  if (sig.length !== want.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(want))) {
    res.status(403).send('bad signature'); return;
  }
  const t = JSON.parse(raw);
  const doc = await db.collection('liveActivity').doc(t.uid).get();
  if (!doc.exists || doc.get('planId') !== t.planId || doc.get('token') !== t.token) {
    res.json({ skipped: 'replaced' }); return;
  }
  const now = Math.floor(Date.now() / 1000);
  const aps = { timestamp: now, event: t.end ? 'end' : 'update', 'content-state': t.state, 'stale-date': Math.floor(t.at) + 45 };
  if (t.end) aps['dismissal-date'] = now + 30 * 60;
  if (t.alert) aps.alert = { title: 'Endless Descent', body: t.alert, sound: 'default' };
  const r = await push(t.token, { aps }, t.alert || t.end ? 10 : 5, t.sandbox);
  if (r.status !== 200) console.warn('APNs', r.status, r.body);
  // A dead token stops the rest of the plan.
  if (r.status === 410 || /BadDeviceToken|ExpiredToken/.test(r.body)) {
    await db.collection('liveActivity').doc(t.uid).set({ planId: 'dead' }, { merge: true });
  }
  res.json({ status: r.status });
}
