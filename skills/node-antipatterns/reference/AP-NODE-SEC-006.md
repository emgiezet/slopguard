# AP-NODE-SEC-006 — Math.random used for tokens or session IDs

**Category:** security | **Severity:** blocker | **CWE:** CWE-330
**Frameworks:** [plain]

## Summary
`Math.random` is not a cryptographic PRNG; its output is predictable. Use `crypto.randomBytes` or `crypto.randomUUID` for any value that must not be guessable.

## Do Not Write
```javascript
const token = Math.random().toString(36).slice(2);
```

## Instead Write
```javascript
const token = crypto.randomBytes(32).toString('hex');
```

## Detection
- opengrep: `slopguard.node.math-random-token`

## References
- https://cwe.mitre.org/data/definitions/330.html
