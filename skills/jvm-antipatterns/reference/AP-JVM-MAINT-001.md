# AP-JVM-MAINT-001 — Catching Exception or Throwable and swallowing it

**Category:** maintainability | **Severity:** error | **CWE:** CWE-390
**Frameworks:** [plain]

## Summary
A catch block for `Exception` or `Throwable` with an empty body or a bare log discards the error completely. Catch the specific exception type you expect, log with full context, and either recover or rethrow to propagate the failure.

## Do Not Write
```java
try { riskyOperation(); } catch (Exception e) { /* ignored */ }
```

## Instead Write
```java
try {
    riskyOperation();
} catch (IOException e) {
    log.error("Operation failed: {}", e.getMessage(), e);
    throw new ServiceException("operation failed", e);
}
```

## References
- https://cwe.mitre.org/data/definitions/390.html
