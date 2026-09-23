const jwt = require('jsonwebtoken');

// ok: slopguard.node.jwt-verify-without-algorithms
function verifyToken(token) {
  return jwt.verify(token, process.env.JWT_PUBLIC_KEY, {
    algorithms: ['RS256'],
    issuer: process.env.JWT_ISSUER,
  });
}

// ok: slopguard.node.jwt-verify-without-algorithms
app.use((req, res, next) => {
  const token = req.headers.authorization?.split(' ')[1];
  req.user = jwt.verify(token, config.publicKey, { algorithms: ['ES256'] });
  next();
});
