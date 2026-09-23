# AP-PY-MAINT-001 — Bare except or swallowing all exceptions

**Category:** maintainability | **Severity:** error | **CWE:** CWE-396
**Frameworks:** [plain]

## Summary
A bare `except:` or `except Exception: pass` silently discards errors including keyboard interrupts and system exits. Catch the narrowest exception type you expect and log or re-raise anything else.

## Do Not Write
```python
try:
    process()
except:
    pass
```

## Instead Write
```python
try:
    process()
except ValueError as exc:
    logger.error("invalid value: %s", exc)
    raise
```

## Detection
- ruff: `E722`
- ruff: `BLE001`

## References
- https://cwe.mitre.org/data/definitions/396.html
