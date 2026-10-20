# AP-TS-MAINT-005 — Fabricated type evidence — chained assertion or uncommented cast

**Category:** maintainability | **Severity:** warn
**Frameworks:** [plain]

## Summary
Chaining type assertions (`(x as A) as B`) fabricates type evidence the type checker cannot verify; so does a bare `value as Foo` with no comment explaining why the cast is safe. Both patterns smuggle incorrect types past the compiler without a runtime check. Use `// SAFETY: <reason>` above each assertion to document why it holds; never chain two assertions together.

## Do Not Write
```typescript
const x = (y as unknown) as Foo;   // chained — no-chained-type-assertions
const id = value as UserId;         // no comment — require-safety-comment-for-type-assertion
```

## Instead Write
```typescript
// SAFETY: value is always a positive integer returned by the auth service
const id = value as UserId;
```

