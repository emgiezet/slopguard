const express = require('express');
const app = express();

// ok: slopguard.node.express-no-body-limit
app.use(express.json({ limit: '100kb' }));

// ok: slopguard.node.express-no-body-limit
app.use(express.urlencoded({ extended: true, limit: '100kb' }));

app.post('/upload', (req, res) => {
  res.json({ received: Object.keys(req.body).length });
});
