# AP-CS-SEC-004 — Weak RNG — new Random() for security-sensitive values

**Category:** security | **Severity:** blocker | **CWE:** CWE-338
**Frameworks:** [plain]

## Summary
`System.Random` is deterministic and predictable. For tokens, session identifiers, and cryptographic nonces, use `RandomNumberGenerator.GetBytes` (or `RandomNumberGenerator.GetHexString` in .NET 8+).

## Do Not Write
```csharp
var token = new Random().Next().ToString("x8");
```

## Instead Write
```csharp
var bytes = RandomNumberGenerator.GetBytes(32);
var token = Convert.ToHexString(bytes).ToLower();
```

## References
- https://cwe.mitre.org/data/definitions/338.html
