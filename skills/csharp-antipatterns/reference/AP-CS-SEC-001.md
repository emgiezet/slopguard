# AP-CS-SEC-001 — SQL built by string interpolation into SqlCommand

**Category:** security | **Severity:** blocker | **CWE:** CWE-89
**Frameworks:** [plain, aspnetcore, entityframework]

## Summary
Embedding a C# interpolated string or concatenated value into a `SqlCommand.CommandText` allows attackers to alter the query structure. Use `SqlCommand` parameters or a parameterized ORM query.

## Do Not Write
```csharp
cmd.CommandText = $"SELECT * FROM Users WHERE Email = '{email}'";
```

## Instead Write
```csharp
cmd.CommandText = "SELECT * FROM Users WHERE Email = @email";
cmd.Parameters.AddWithValue("@email", email);
```

## Detection
- opengrep: `slopguard.cs.sql-string-interpolation`

## References
- https://cwe.mitre.org/data/definitions/89.html
