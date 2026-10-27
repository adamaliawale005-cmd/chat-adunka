/**
 * TURN REST API credentials (coturn "use-auth-secret"):
 *   username   = "<unix expiry>:<uid>"
 *   credential = base64(HMAC-SHA1(sharedSecret, username))
 * Kept free of Firebase imports so it can be unit-tested in CI.
 */
const crypto = require('node:crypto');

function turnCredentialsFor(uid, secret, nowSeconds, ttlSeconds) {
  if (!uid || typeof uid !== 'string' || uid.includes(':')) throw new Error('invalid uid');
  if (!secret || secret.length < 16) throw new Error('TURN shared secret too short');
  if (!(ttlSeconds > 0 && ttlSeconds <= 24 * 3600)) throw new Error('invalid ttl');
  const username = `${nowSeconds + ttlSeconds}:${uid}`;
  const credential = crypto.createHmac('sha1', secret).update(username).digest('base64');
  return { username, credential, ttlSeconds };
}

module.exports = { turnCredentialsFor };
