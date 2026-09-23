# AP-CS-SEC-002 — BinaryFormatter or NetDataContractSerializer deserialization

**Category:** security | **Severity:** blocker | **CWE:** CWE-502
**Frameworks:** [plain]

## Summary
Both `BinaryFormatter` and `NetDataContractSerializer` are vulnerable to deserialization gadget attacks when deserialising attacker-controlled data. Microsoft deprecated `BinaryFormatter` in .NET 5 and removed it in .NET 9. Use `System.Text.Json` or `MessagePack` with an explicit type allowlist.

## Do Not Write
```csharp
var formatter = new BinaryFormatter();
var obj = formatter.Deserialize(stream);
```

## Instead Write
```csharp
var obj = JsonSerializer.Deserialize<MyType>(stream);
```

## Detection
- opengrep: `slopguard.cs.binary-formatter`

## References
- https://cwe.mitre.org/data/definitions/502.html
