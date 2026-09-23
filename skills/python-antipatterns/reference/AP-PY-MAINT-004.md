# AP-PY-MAINT-004 — print statements in application code or assert as production validation

**Category:** maintainability | **Severity:** warn | **CWE:** CWE-617
**Frameworks:** [plain]

## Summary
Debug `print()` calls left in application code clutter logs and may leak sensitive data. `assert` is stripped when Python is run with optimisations (`-O`), so it must not gate production logic.

## Do Not Write
```python
print(f"user id: {user.id}")
assert token is not None, "token required"
```

## Instead Write
```python
logger.debug("user id: %s", user.id)
if token is None:
    raise ValueError("token required")
```

## Detection
- ruff: `T201`
- ruff: `S101`

## References
- https://cwe.mitre.org/data/definitions/617.html
