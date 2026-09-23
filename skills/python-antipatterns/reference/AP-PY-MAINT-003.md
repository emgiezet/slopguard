# AP-PY-MAINT-003 — datetime.now() without timezone

**Category:** maintainability | **Severity:** warn
**Frameworks:** [plain]

## Summary
Calling `datetime.now()` without a timezone argument returns a naive datetime that silently behaves differently across systems and DST transitions. Always pass `tz=timezone.utc` or use `datetime.now(tz=UTC)`.

## Do Not Write
```python
created_at = datetime.now()
```

## Instead Write
```python
from datetime import timezone
created_at = datetime.now(tz=timezone.utc)
```

## Detection
- ruff: `DTZ005`

