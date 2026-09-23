# AP-NODE-PERF-002 — Unbounded JSON.parse or stringify on the event loop

**Category:** performance | **Severity:** warn | **CWE:** CWE-400
**Frameworks:** [express, plain]

## Summary
Parsing or serialising large JSON documents synchronously on the main thread blocks the event loop proportionally to the document size. Apply a body size limit at the middleware layer and stream or offload oversized payloads to a worker thread.

## Do Not Write
```javascript
app.post('/import', (req, res) => {
  const rows = JSON.parse(req.body); // may be megabytes
});
```

## Instead Write
```javascript
app.use(express.json({ limit: '1mb' }));
// Large imports: stream to a worker_thread or a queue processor
```

## References
- https://cwe.mitre.org/data/definitions/400.html
