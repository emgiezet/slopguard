# AP-NODE-SEC-009 — jwt.verify without explicit algorithms list

**Category:** security | **Severity:** blocker | **CWE:** CWE-347
**Frameworks:** [express, plain]

## Summary
Omitting the `algorithms` array from `jwt.verify` lets an attacker switch the token header to `"alg": "none"` and bypass signature verification entirely. Always pass an explicit list of accepted algorithms.

## Do Not Write
```javascript
const payload = jwt.verify(token, secret);
```

## Instead Write
```javascript
const payload = jwt.verify(token, secret, { algorithms: ['HS256'] });
```

## Detection
- opengrep: `slopguard.node.jwt-verify-without-algorithms`

## References
- https://cwe.mitre.org/data/definitions/347.html
