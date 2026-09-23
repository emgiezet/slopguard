# AP-NODE-PERF-001 — Synchronous I/O or crypto in request handlers

**Category:** performance | **Severity:** error | **CWE:** CWE-400
**Frameworks:** [express, plain]

## Summary
Synchronous calls like `readFileSync`, `pbkdf2Sync`, or `execSync` block the Node.js event loop for their full duration, preventing all other requests from being served. Replace them with the async equivalents or run them in a worker thread.

## Do Not Write
```javascript
app.get('/file', (req, res) => {
  const data = fs.readFileSync('./data.json');  // blocks event loop
  res.json(JSON.parse(data));
});
```

## Instead Write
```javascript
app.get('/file', async (req, res) => {
  const data = await fs.promises.readFile('./data.json');
  res.json(JSON.parse(data));
});
```

## Detection
- eslint: `n/no-sync`

## References
- https://cwe.mitre.org/data/definitions/400.html
