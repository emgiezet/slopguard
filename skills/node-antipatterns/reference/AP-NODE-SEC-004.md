# AP-NODE-SEC-004 — ReDoS — nested quantifiers or RegExp from user input

**Category:** security | **Severity:** blocker | **CWE:** CWE-1333
**Frameworks:** [plain]

## Summary
Regular expressions with nested quantifiers and ambiguous paths cause catastrophic backtracking when matched against crafted input, blocking the event loop. Audit patterns for super-linear worst-case complexity and never pass user input as a regular expression literal without sanitising it first.

## Do Not Write
```javascript
const re = new RegExp(req.query.pattern);   // arbitrary regex from user
str.match(/(\w+)+/);                         // exponential backtracking
```

## Instead Write
```javascript
if (!/^[a-z0-9_-]+$/i.test(req.query.pattern)) return res.status(400).end();
const re = new RegExp(req.query.pattern);
```

## Detection
- eslint: `regexp/no-super-linear-backtracking`
- eslint: `security/detect-unsafe-regex`

## References
- https://cwe.mitre.org/data/definitions/1333.html
