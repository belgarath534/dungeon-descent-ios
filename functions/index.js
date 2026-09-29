import { http } from '@google-cloud/functions-framework';
import admin from 'firebase-admin';
import { PollyClient, SynthesizeSpeechCommand } from '@aws-sdk/client-polly';

admin.initializeApp();

// Brian — British English neural voice, closest match to the narrator
// voice the game already used on ElevenLabs.
const POLLY_VOICE_ID = 'Brian';
const POLLY_REGION = 'us-east-1';

// A single request can only ask for this many characters — keeps any one
// call cheap regardless of what text the client sends.
const MAX_TEXT_LENGTH = 300;
// Per signed-in user, per day. Generous for a single player's AFK hunts,
// small enough that one compromised or careless client can't run up a
// real bill before the day resets.
const DAILY_CALL_CAP = 300;
const DAILY_CHAR_CAP = 20000;

// Proxies Hunting Grounds narrator lines to Amazon Polly. The AWS
// credentials never reach the client — they only live here, bound as
// Secret Manager secrets on this Cloud Run service (AWS_ACCESS_KEY_ID /
// AWS_SECRET_ACCESS_KEY under "Variables & Secrets"). Every caller must
// present a valid Firebase Auth ID token, and usage is rate limited per
// user in Firestore so a leaked or scraped endpoint still can't run up a
// real AWS bill the way the old hardcoded client-side ElevenLabs key did.
http('narrateHuntLine', async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
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
    const polly = new PollyClient({
      region: POLLY_REGION,
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
      }
    });
    const command = new SynthesizeSpeechCommand({
      Text: text,
      OutputFormat: 'mp3',
      VoiceId: POLLY_VOICE_ID,
      Engine: 'neural'
    });
    const pollyResponse = await polly.send(command);
    const chunks = [];
    for await (const chunk of pollyResponse.AudioStream) {
      chunks.push(chunk);
    }
    const audioBuffer = Buffer.concat(chunks);
    res.set('Content-Type', 'audio/mpeg');
    res.status(200).send(audioBuffer);
  } catch (e) {
    console.error('Polly narration error:', e);
    res.status(502).json({ error: 'Narration service error' });
  }
});
