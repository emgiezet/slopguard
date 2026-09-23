// ruleid: slopguard.node.math-random-token
const sessionId = Math.random().toString(36).slice(2);

// ruleid: slopguard.node.math-random-token
function generateToken() {
  return Math.random().toString(16).slice(2) + Math.random().toString(16).slice(2);
}

// ruleid: slopguard.node.math-random-token
const csrfToken = Buffer.from(Math.random().toString()).toString('base64');
