# AP-TS-MAINT-002 — Unhandled or floating Promises

**Category:** maintainability | **Severity:** error | **CWE:** CWE-755
**Frameworks:** [plain]

## Summary
A Promise that is not awaited, returned, or `.catch()`-ed discards errors silently. Always chain `.catch()`, use `await`, or prefix with the `void` keyword if intentionally fire-and-forget (with an accompanying comment explaining why).

## Do Not Write
```typescript
async function save() { db.update(record); } // floating Promise
```

## Instead Write
```typescript
async function save() { await db.update(record); }
```

## References
- https://cwe.mitre.org/data/definitions/755.html
