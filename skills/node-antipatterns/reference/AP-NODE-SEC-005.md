# AP-NODE-SEC-005 — Timing-unsafe comparison of secrets with ===

**Category:** security | **Severity:** error | **CWE:** CWE-208
**Frameworks:** [plain]

## Summary
JavaScript's `===` short-circuits on the first mismatching byte, leaking information about how many characters of the secret match. Compare HMAC digests or tokens with `crypto.timingSafeEqual` to eliminate the timing side-channel.

## Do Not Write
```javascript
if (req.headers['x-api-key'] === process.env.API_KEY) { /* allow */ }
```

## Instead Write
```javascript
const a = Buffer.from(req.headers['x-api-key'] ?? '');
const b = Buffer.from(process.env.API_KEY);
if (a.length === b.length && crypto.timingSafeEqual(a, b)) { /* allow */ }
```

## Detection
- eslint: `security/detect-possible-timing-attacks`

## References
- https://cwe.mitre.org/data/definitions/208.html
