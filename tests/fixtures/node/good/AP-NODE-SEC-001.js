const { validate } = require('jsonschema');

// ok: slopguard.node.prototype-pollution-merge
function mergeConfig(defaults, overrides) {
  // Validate schema first; use Object.create(null) for accumulator
  const safe = Object.create(null);
  for (const key of Object.keys(overrides)) {
    if (Object.hasOwn(defaults, key)) {
      safe[key] = overrides[key];
    }
  }
  return Object.assign({}, defaults, safe);
}

// ok: slopguard.node.prototype-pollution-merge
app.post('/update', (req, res) => {
  const { allowed1, allowed2 } = req.body; // destructure only known fields
  const config = { allowed1, allowed2 };
  res.json(config);
});
