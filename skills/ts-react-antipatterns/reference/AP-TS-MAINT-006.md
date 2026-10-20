# AP-TS-MAINT-006 — Known value widened to `unknown` then asserted back

**Category:** maintainability | **Severity:** warn
**Frameworks:** [plain]

## Summary
Assigning a concrete, known value to `unknown` and then asserting it back to a specific type round-trips through the type system for no gain; the assertion is less safe than using the original type directly. Use the original type or narrow once at the boundary; do not manufacture uncertainty just to erase it with an assertion.

## Do Not Write
```typescript
const w: unknown = obj;              // no-known-value-widening
const result = w as { id: string };  // no-widen-then-assert
```

## Instead Write
```typescript
const result = obj; // obj's type is already known; no assertion needed
```

