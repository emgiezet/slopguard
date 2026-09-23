# AP-TS-MAINT-001 — any type, non-null assertions, or unsafe casts on external data

**Category:** maintainability | **Severity:** warn | **CWE:** CWE-20
**Frameworks:** [plain]

## Summary
Widening types to `any` or forcing non-null with `!` defeats TypeScript's safety guarantees. Validate and narrow external data at the boundary using a schema library, then the rest of the code can rely on correct types without assertions.

## Do Not Write
```typescript
const user = JSON.parse(body) as User;      // unchecked cast
return user.profile!.name;                  // may panic at runtime
```

## Instead Write
```typescript
const user = UserSchema.parse(JSON.parse(body));  // throws on invalid shape
return user.profile?.name ?? 'anonymous';
```

## References
- https://cwe.mitre.org/data/definitions/20.html
