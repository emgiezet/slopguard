# AP-CS-MAINT-001 — Catching generic Exception and swallowing it

**Category:** maintainability | **Severity:** error | **CWE:** CWE-390
**Frameworks:** [plain]

## Summary
An empty catch block for `Exception` silently discards all errors including ThreadAbortException and OutOfMemoryException. Catch the narrowest type you can handle, log with context, and rethrow or propagate.

## Do Not Write
```csharp
try { Process(); } catch (Exception) { }
```

## Instead Write
```csharp
try {
    Process();
} catch (IOException ex) {
    logger.LogError(ex, "IO failure during processing");
    throw;
}
```

## References
- https://cwe.mitre.org/data/definitions/390.html
