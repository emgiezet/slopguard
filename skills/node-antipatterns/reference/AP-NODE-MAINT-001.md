# AP-NODE-MAINT-001 — No unhandledRejection or uncaughtException strategy

**Category:** maintainability | **Severity:** warn | **CWE:** CWE-755
**Frameworks:** [plain]

## Summary
Without handlers for `unhandledRejection` and `uncaughtException`, a crashed async operation or unexpected throw can exit the process without any diagnostic context. Register handlers that log the error and shut down gracefully.

## Do Not Write
```javascript
// No process-level error handlers — process exits silently on async throw
```

## Instead Write
```javascript
process.on('unhandledRejection', (reason) => {
  logger.fatal({ err: reason }, 'Unhandled rejection');
  process.exit(1);
});
```

## References
- https://cwe.mitre.org/data/definitions/755.html
