const jwt = require('jsonwebtoken');

// ruleid: slopguard.node.jwt-verify-without-algorithms
function verifyToken(token) {
  // No algorithms option: accepts 'none' and any other alg
  return jwt.verify(token, process.env.JWT_SECRET);
}

// ruleid: slopguard.node.jwt-verify-without-algorithms
app.use((req, res, next) => {
  const token = req.headers.authorization?.split(' ')[1];
  req.user = jwt.verify(token, config.secret);
  next();
});
