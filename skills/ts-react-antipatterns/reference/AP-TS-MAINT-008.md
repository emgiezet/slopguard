# AP-TS-MAINT-008 — Reflect API bypasses TypeScript property-access and call-site checks

**Category:** maintainability | **Severity:** warn
**Frameworks:** [plain]

## Summary
Reflect.get and Reflect.apply operate on property names as strings and argument lists as arrays, bypassing the TypeScript type checker's property-access and call-site validation entirely. Use direct property access (obj.id) and typed function calls instead; the type system can then catch misspelled property names and wrong argument counts at compile time.

## Do Not Write
```typescript
const v = Reflect.get(obj, 'id');
const r = Reflect.apply(fn, null, [arg]);
```

## Instead Write
```typescript
const v = obj.id;
const r = fn(arg);
```

