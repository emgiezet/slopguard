# AP-TS-MAINT-004 — Non-exhaustive switch on union type

**Category:** maintainability | **Severity:** error
**Frameworks:** [plain]

## Summary
A `switch` statement that does not cover all members of a union type silently ignores new variants added to the type. Add a `default` branch that asserts `never` so TypeScript catches unhandled cases at compile time.

## Do Not Write
```typescript
function label(s: 'ok' | 'err' | 'pending') {
  switch (s) { case 'ok': return 'OK'; case 'err': return 'Error'; }
}
```

## Instead Write
```typescript
function label(s: 'ok' | 'err' | 'pending'): string {
  switch (s) {
    case 'ok': return 'OK'; case 'err': return 'Error';
    case 'pending': return 'Pending';
    default: { const _: never = s; return _; }
  }
}
```

