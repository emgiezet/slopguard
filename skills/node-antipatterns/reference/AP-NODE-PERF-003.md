# AP-NODE-PERF-003 — CPU-bound work on the event loop or flooding the libuv thread pool

**Category:** performance | **Severity:** warn | **CWE:** CWE-400
**Frameworks:** [plain]

## Summary
CPU-intensive operations (image processing, encryption, compression) executed on the main thread block the event loop for all concurrent requests. Offload them to `worker_threads` or a task queue. Equally, spawning many `fs.*` operations in parallel floods the libuv thread pool; use a concurrency limiter.

## Do Not Write
```javascript
app.post('/resize', (req, res) => {
  const img = sharp(req.body).resize(800).toBufferSync(); // blocks event loop
});
```

## Instead Write
```javascript
const { resize } = require('./workers/imageWorker');
app.post('/resize', async (req, res) => {
  const img = await resize(req.body, 800);
  res.send(img);
});
```

## References
- https://cwe.mitre.org/data/definitions/400.html
