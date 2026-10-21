# AP-TS-MAINT-001 — any type, non-null assertions, or unsafe casts on external data

**Category:** maintainability | **Severity:** warn | **CWE:** CWE-20
**Frameworks:** [plain]

## Summary
Widening types to `any` or forcing non-null with `!` defeats TypeScript's safety guarantees. The double cast `x as unknown as T` is the same defeat in one expression — it exists only to silence the error a direct cast would raise, and a value that was already typed by a schema or a typed function loses nothing but the detour. Validate and narrow external data at the boundary using a schema library, then the rest of the code can rely on correct types without assertions.

## Do Not Write
```typescript
const user = JSON.parse(body) as User;      // unchecked cast
return user.profile!.name;                  // may panic at runtime
const account = accountSchema.parse(input);
const generic: Record<string, unknown> = account;
return generic as unknown as Account;       // validated → widened → asserted back
```

## Instead Write
```typescript
const user = UserSchema.parse(JSON.parse(body));  // throws on invalid shape
return user.profile?.name ?? 'anonymous';
return accountSchema.parse(input);                // the parse already returns Account
```

## Detection
- opengrep: `slopguard.ts.double-cast`

## References
- https://cwe.mitre.org/data/definitions/20.html
