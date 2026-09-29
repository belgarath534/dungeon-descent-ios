const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();

// Set once via: firebase functions:secrets:set ELEVENLABS_KEY
const elevenlabsKey = defineSecret('ELEVENLABS_KEY');

const BRIAN_VOICE_ID = 'nPczCjzI2devNBz1zQrb';

// A single request can only ask for this many characters — keeps any one
// call cheap regardless of what text the client sends.
const MAX_TEXT_LENGTH = 300;
// Per signed-in user, per day. Generous for a single player's AFK hunts,
// small enough that one compromised or careless client can't run up a
// real bill before the day resets.
const DAILY_CALL_CAP = 300;
const DAILY_CHAR_CAP = 20000;

// Proxies Hunting Grounds narrator lines to ElevenLabs. The API key never
// reaches the client — it only lives here, in Secret Manager. Every
// caller must present a valid Firebase Auth ID token, and usage is rate
// limited per user in Firestore so a leaked or scraped endpoint still
// can't drain the account the way the old hardcoded client key did.
exports.narrateHuntLine = onRequest({ secrets: [elevenlabsKey], cors: true }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const authHeader = req.get('Authorization') || '';
  const match = authHeader.match(/^Bearer (.+)$/);
  if (!match) {
    res.status(401).json({ error: 'Missing auth token' });
    return;
  }

  let uid;
  try {
    const decoded = await admin.auth().verifyIdToken(match[1]);
    uid = decoded.uid;
  } catch (e) {
    res.status(401).json({ error: 'Invalid auth token' });
    return;
  }

  const text = ((req.body && req.body.text) || '').toString().trim().slice(0, MAX_TEXT_LENGTH);
  if (!text) {
    res.status(400).json({ error: 'Missing text' });
    return;
  }

  const db = admin.firestore();
  const today = new Date().toISOString().slice(0, 10);
  const usageRef = db.collection('ttsUsage').doc(uid);

  try {
    const allowed = await db.runTransaction(async (tx) => {
      const doc = await tx.get(usageRef);
      const data = doc.exists ? doc.data() : {};
      const isToday = data.date === today;
      const count = isToday ? (data.count || 0) : 0;
      const chars = isToday ? (data.chars || 0) : 0;
      if (count >= DAILY_CALL_CAP || chars + text.length > DAILY_CHAR_CAP) return false;
      tx.set(usageRef, { date: today, count: count + 1, chars: chars + text.length }, { merge: true });
      return true;
    });
    if (!allowed) {
      res.status(429).json({ error: 'Daily narration limit reached' });
      return;
    }
  } catch (e) {
    console.error('Rate limit check failed:', e);
    res.status(500).json({ error: 'Rate limit check failed' });
    return;
  }

  try {
    const elResponse = await fetch('https://api.elevenlabs.io/v1/text-to-speech/' + BRIAN_VOICE_ID, {
      method: 'POST',
      headers: {
        'xi-api-key': elevenlabsKey.value(),
        'Content-Type': 'application/json',
        'Accept': 'audio/mpeg'
      },
      body: JSON.stringify({
        text,
        model_id: 'eleven_monolingual_v1',
        voice_settings: { stability: 0.5, similarity_boost: 0.75 }
      })
    });
    if (!elResponse.ok) {
      console.error('ElevenLabs error:', elResponse.status, await elResponse.text());
      res.status(502).json({ error: 'Narration service error' });
      return;
    }
    const arrayBuf = await elResponse.arrayBuffer();
    res.set('Content-Type', 'audio/mpeg');
    res.status(200).send(Buffer.from(arrayBuf));
  } catch (e) {
    console.error('Narration proxy error:', e);
    res.status(500).json({ error: 'Narration proxy failed' });
  }
});
