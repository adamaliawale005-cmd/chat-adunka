/**
 * AduChat Cloud Functions: push notifications when the app is closed.
 *
 * These run on Google's servers with trusted credentials, so no privileged
 * key is ever placed in the mobile app.
 *
 * Requires the Firebase Blaze (pay-as-you-go) plan. Blaze includes a free
 * monthly allowance (2 million invocations); small test groups normally
 * stay inside it, but a billing account must be attached.
 *
 * Deploy (after approving Blaze):
 *   cd functions && npm install && cp .env.example .env  (set the region)
 *   firebase deploy --only functions
 */
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { setGlobalOptions, logger } = require('firebase-functions/v2');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { turnCredentialsFor } = require('./turn');

initializeApp();
setGlobalOptions({
  region: process.env.FUNCTIONS_REGION || 'us-central1',
  maxInstances: 10,
});

const db = getFirestore();

const STALE_TOKEN_ERRORS = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

async function tokensFor(uid) {
  const snap = await db.collection('users').doc(uid).collection('devices').get();
  return snap.docs.map((d) => d.id);
}

async function prefsFor(uid) {
  const doc = await db.doc(`users/${uid}/private/account`).get();
  const n = (doc.data() || {}).notifications || {};
  return {
    messages: n.messages !== false,
    groups: n.groups !== false,
    calls: n.calls !== false,
    preview: n.preview !== false,
  };
}

async function hasBlocked(owner, other) {
  return (await db.doc(`users/${owner}/blocked/${other}`).get()).exists;
}

async function nameOf(uid) {
  const doc = await db.doc(`users/${uid}`).get();
  return (doc.data() || {}).displayName || 'AduChat';
}

/** Sends to every device of a user and removes tokens that no longer work. */
async function sendToUser(uid, message) {
  const tokens = await tokensFor(uid);
  if (tokens.length === 0) return;
  const res = await getMessaging().sendEachForMulticast({ tokens, ...message });
  const stale = [];
  res.responses.forEach((r, i) => {
    if (!r.success && r.error && STALE_TOKEN_ERRORS.has(r.error.code)) stale.push(tokens[i]);
  });
  await Promise.all(stale.map((t) => db.doc(`users/${uid}/devices/${t}`).delete()));
  if (res.failureCount > stale.length) {
    logger.warn('Some notifications failed', { uid, failures: res.failureCount });
  }
}

function previewOf(m) {
  switch (m.type) {
    case 'image':
      return '📷 Photo';
    case 'video':
      return '🎬 Video';
    case 'audio':
      return '🎤 Voice message';
    case 'file':
      return `📄 ${(m.attachment && m.attachment.name) || 'Document'}`;
    default:
      return String(m.text || '').slice(0, 200);
  }
}

/** New message -> notify the other members (respecting blocks and settings). */
exports.notifyNewMessage = onDocumentCreated('chats/{chatId}/messages/{messageId}', async (event) => {
  const m = event.data && event.data.data();
  if (!m || m.type === 'system') return;
  const { chatId } = event.params;
  const chat = (await db.doc(`chats/${chatId}`).get()).data();
  if (!chat) return;
  const sender = m.senderId;
  const senderName = await nameOf(sender);
  const isGroup = chat.type === 'group';
  const recipients = (chat.members || []).filter((u) => u !== sender);

  await Promise.all(recipients.map(async (uid) => {
    if (await hasBlocked(uid, sender)) return;
    const p = await prefsFor(uid);
    if (isGroup ? !p.groups : !p.messages) return;
    const body = p.preview ? previewOf(m) : 'New message';
    await sendToUser(uid, {
      notification: {
        title: isGroup ? chat.name : senderName,
        body: isGroup ? `${senderName}: ${body}` : body,
      },
      data: { type: 'message', chatId },
      android: {
        priority: 'high',
        notification: { channelId: 'messages', tag: chatId },
      },
    });
  }));
});

/** Ringing call -> high-priority data message that wakes the callee's phone. */
exports.notifyIncomingCall = onDocumentCreated('calls/{callId}', async (event) => {
  const c = event.data && event.data.data();
  if (!c || c.status !== 'ringing') return;
  if (await hasBlocked(c.calleeId, c.callerId)) return;
  const p = await prefsFor(c.calleeId);
  if (!p.calls) return;
  const callerName = await nameOf(c.callerId);
  await sendToUser(c.calleeId, {
    data: {
      type: 'call',
      callId: event.params.callId,
      title: callerName,
      body: c.type === 'video' ? 'Incoming video call' : 'Incoming voice call',
    },
    android: { priority: 'high', ttl: 45000 },
  });
});

/** Ringing call that was never answered -> "Missed call" notification. */
exports.notifyMissedCall = onDocumentUpdated('calls/{callId}', async (event) => {
  const before = event.data && event.data.before.data();
  const after = event.data && event.data.after.data();
  if (!before || !after || before.status !== 'ringing') return;
  if (after.status !== 'missed' && after.status !== 'cancelled') return;
  if (await hasBlocked(after.calleeId, after.callerId)) return;
  const p = await prefsFor(after.calleeId);
  if (!p.calls) return;
  const callerName = await nameOf(after.callerId);
  await sendToUser(after.calleeId, {
    notification: { title: 'Missed call', body: callerName },
    data: { type: 'missed_call', callId: event.params.callId },
    android: { notification: { channelId: 'calls', tag: event.params.callId } },
  });
});

// ---------------------------------------------------------------------------
// TURN relay credentials (short-lived, per user).
//
// Calls need a TURN relay on many mobile networks. Static TURN passwords
// must never be built into the APK or the web app (anyone can extract
// them and use the relay at the owner's cost). Instead the app asks this
// function for credentials that expire after TURN_TTL_SECONDS.
//
// Format: the standard "TURN REST API" shared-secret scheme supported by
// coturn (use-auth-secret / static-auth-secret) and most hosted relays:
//   username   = "<unix expiry>:<uid>"
//   credential = base64(HMAC-SHA1(sharedSecret, username))
// No custom cryptography is involved.
//
// Owner setup (needs Blaze and a TURN server or provider; not deployed
// automatically):
//   firebase functions:secrets:set TURN_SHARED_SECRET
//   functions/.env: TURN_URLS=turns:turn.example.com:5349?transport=tcp,turn:turn.example.com:3478
//   functions/.env: ENFORCE_APP_CHECK=false   (set true once App Check metrics look healthy)
// ---------------------------------------------------------------------------
const TURN_SHARED_SECRET = defineSecret('TURN_SHARED_SECRET');
const TURN_TTL_SECONDS = 6 * 3600;
const TURN_REQUESTS_PER_HOUR = 30;

/**
 * Fixed-window rate limit stored in rateLimits/{uid}_{name}. The rules
 * give clients no access to this collection.
 */
async function allowRate(uid, name, limitPerHour) {
  const ref = db.doc(`rateLimits/${uid}_${name}`);
  const windowStart = Math.floor(Date.now() / 3600000);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.exists ? snap.data() : {};
    const count = d.window === windowStart ? (d.count || 0) : 0;
    if (count >= limitPerHour) return false;
    tx.set(ref, { window: windowStart, count: count + 1, updatedAt: FieldValue.serverTimestamp() });
    return true;
  });
}


exports.turnCredentials = onCall(
  {
    secrets: [TURN_SHARED_SECRET],
    enforceAppCheck: process.env.ENFORCE_APP_CHECK === 'true',
    maxInstances: 10,
  },
  async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
    const urls = String(process.env.TURN_URLS || '').split(',').map((u) => u.trim()).filter(Boolean);
    if (urls.length === 0) throw new HttpsError('failed-precondition', 'TURN relay is not configured.');
    if (!(await allowRate(uid, 'turn', TURN_REQUESTS_PER_HOUR))) {
      throw new HttpsError('resource-exhausted', 'Too many requests. Try again later.');
    }
    const c = turnCredentialsFor(uid, TURN_SHARED_SECRET.value(), Math.floor(Date.now() / 1000), TURN_TTL_SECONDS);
    // Never log the credential.
    logger.info('TURN credentials issued', { uid: uid.slice(0, 6) + '…' });
    return { urls, username: c.username, credential: c.credential, ttlSeconds: c.ttlSeconds };
  },
);
