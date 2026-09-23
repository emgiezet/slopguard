const express = require('express');
const app = express();

// ruleid: slopguard.node.express-no-body-limit
app.use(express.json());

// ruleid: slopguard.node.express-no-body-limit
app.use(express.urlencoded({ extended: true }));

app.post('/upload', (req, res) => {
  // Caller can send unlimited-size body
  res.json({ received: Object.keys(req.body).length });
});
