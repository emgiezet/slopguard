# AP-NODE-MAINT-002 — Deprecated Node.js API usage (new Buffer, fs.exists)

**Category:** maintainability | **Severity:** error | **CWE:** CWE-477
**Frameworks:** [plain]

## Summary
The `new Buffer()` constructor is deprecated and insecure (it allocates uninitialized memory when called with a number). `fs.exists` was deprecated because its callback signature breaks Node.js error-first conventions. Use `Buffer.from`, `Buffer.alloc`, and `fs.access` instead.

## Do Not Write
```javascript
const buf = new Buffer(userInput);
fs.exists(path, (exists) => { /* … */ });
```

## Instead Write
```javascript
const buf = Buffer.from(userInput);
fs.access(path, fs.constants.F_OK, (err) => { /* … */ });
```

## Detection
- eslint: `n/no-deprecated-api`
- eslint: `security/detect-new-buffer`

## References
- https://cwe.mitre.org/data/definitions/477.html
