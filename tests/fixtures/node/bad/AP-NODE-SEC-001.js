// ruleid: slopguard.node.prototype-pollution-merge
function mergeConfig(defaults, overrides) {
  for (const key in overrides) {
    defaults[key] = overrides[key]; // __proto__ key pollutes Object.prototype
  }
  return defaults;
}

// ruleid: slopguard.node.prototype-pollution-merge
app.post('/update', (req, res) => {
  const config = {};
  Object.assign(config, req.body); // body may contain __proto__
  res.json(config);
});

// ruleid: slopguard.node.prototype-pollution-merge
router.patch('/settings', async (req, res) => {
  const settings = await Settings.findOne();
  Object.assign(settings, req.query);
  await settings.save();
  res.json(settings);
});
