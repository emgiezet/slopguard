const crypto = require('crypto');

// ok: slopguard.node.math-random-token
const sessionId = crypto.randomBytes(32).toString('hex');

// ok: slopguard.node.math-random-token
function generateToken() {
  return crypto.randomBytes(48).toString('base64url');
}

// ok: slopguard.node.math-random-token
const csrfToken = crypto.randomUUID();
