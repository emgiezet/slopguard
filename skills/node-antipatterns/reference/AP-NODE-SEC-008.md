# AP-NODE-SEC-008 — Dynamic require or import from user-controlled path

**Category:** security | **Severity:** blocker | **CWE:** CWE-829
**Frameworks:** [plain]

## Summary
Calling `require(userInput)` or dynamic `import(userInput)` loads arbitrary modules from the file system or from `node_modules`. Use a static map of allowed module names instead of dynamic resolution.

## Do Not Write
```javascript
const plugin = require(req.query.plugin);
```

## Instead Write
```javascript
const plugins = { pdf: require('./plugins/pdf'), csv: require('./plugins/csv') };
const plugin = plugins[req.query.plugin] ?? (() => { throw new Error('unknown'); });
```

## Detection
- eslint: `security/detect-non-literal-require`

## References
- https://cwe.mitre.org/data/definitions/829.html
