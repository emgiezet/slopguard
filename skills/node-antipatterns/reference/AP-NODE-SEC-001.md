# AP-NODE-SEC-001 — Prototype pollution via recursive merge or req.body property assignment

**Category:** security | **Severity:** blocker | **CWE:** CWE-1321
**Frameworks:** [express, plain]

## Summary
A recursive merge that copies all properties from a user-supplied object can set `__proto__` or `constructor.prototype`, corrupting the global object prototype. Use `Object.create(null)` for dictionaries, validate input schemas before merging, and use `Object.hasOwn` to guard property access.

## Do Not Write
```javascript
function merge(dst, src) {
  for (const k in src) dst[k] = src[k]; // pollutes if src has __proto__
}
merge(config, req.body);
```

## Instead Write
```javascript
const safe = schema.parse(req.body);     // throws on unexpected keys
Object.assign(config, safe);
```

## Detection
- opengrep: `slopguard.node.prototype-pollution-merge`

## References
- https://cwe.mitre.org/data/definitions/1321.html
