# AP-CS-MAINT-002 — String concatenation in a loop

**Category:** performance | **Severity:** warn
**Frameworks:** [plain]

## Summary
Concatenating strings with `+` inside a loop creates O(n²) allocations because each iteration allocates a new string. Use `StringBuilder` for loop-based construction or `string.Join` / LINQ `Aggregate` for combining collections.

## Do Not Write
```csharp
string result = "";
foreach (var item in items) { result += item + ", "; }
```

## Instead Write
```csharp
var sb = new StringBuilder();
foreach (var item in items) { sb.Append(item).Append(", "); }
string result = sb.ToString();
```

