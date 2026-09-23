# AP-NODE-SEC-002 — child_process.exec with template literal or string concatenation

**Category:** security | **Severity:** blocker | **CWE:** CWE-78
**Frameworks:** [plain]

## Summary
Passing a shell command string with embedded user data to `exec` or `execSync` allows shell metacharacter injection. Use `execFile` or `spawn` with an explicit argv array so no shell is invoked.

## Do Not Write
```javascript
exec(`convert ${req.query.file} output.png`);
```

## Instead Write
```javascript
execFile('convert', [req.query.file, 'output.png'], callback);
```

## Detection
- eslint: `security/detect-child-process`
- opengrep: `slopguard.node.exec-template-literal`

## References
- https://cwe.mitre.org/data/definitions/78.html
