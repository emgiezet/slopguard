# AP-TS-MAINT-003 — "@ts-ignore without description"

**Category:** maintainability | **Severity:** error
**Frameworks:** [plain]

## Summary
Bare `@ts-ignore` silences errors without recording why they cannot be fixed. Use `@ts-expect-error` instead; it fails when the error is gone (so you know to remove it) and requires a description of at least 10 characters.

## Do Not Write
```typescript
// @ts-ignore
const val = legacyLib.compute(x);
```

## Instead Write
```typescript
// @ts-expect-error // reason: legacyLib types not updated for v3 API
const val = legacyLib.compute(x);
```

