# AP-NODE-SEC-003 — File path built from request input without validation

**Category:** security | **Severity:** error | **CWE:** CWE-22
**Frameworks:** [express, plain]

## Summary
Building a file path from a query parameter or route segment without canonicalising and prefix-checking it enables directory traversal. Use `path.resolve` to get an absolute path and verify it starts with the expected base directory.

## Do Not Write
```javascript
const data = fs.readFileSync(`./uploads/${req.query.file}`);
```

## Instead Write
```javascript
const base = path.resolve('./uploads');
const target = path.resolve(base, req.query.file);
if (!target.startsWith(base + path.sep)) return res.status(400).end();
const data = fs.readFileSync(target);
```

## Detection
- eslint: `security/detect-non-literal-fs-filename`

## References
- https://cwe.mitre.org/data/definitions/22.html
