# AP-NODE-SEC-007 — Missing request body size limit or HTTP security headers

**Category:** security | **Severity:** error | **CWE:** CWE-400, CWE-693
**Frameworks:** [express, plain]

## Summary
Without a body size limit, a client can send gigabytes of JSON and exhaust server memory. Without security headers (Content-Security-Policy, X-Frame-Options, etc.) browsers apply permissive defaults. Set `express.json({ limit })` and use `helmet` or equivalent.

## Do Not Write
```javascript
app.use(express.json()); // no limit; no security headers
```

## Instead Write
```javascript
app.use(helmet());
app.use(express.json({ limit: '1mb' }));
```

## Detection
- opengrep: `slopguard.node.express-no-body-limit`

## References
- https://cwe.mitre.org/data/definitions/400.html
- https://cwe.mitre.org/data/definitions/693.html
