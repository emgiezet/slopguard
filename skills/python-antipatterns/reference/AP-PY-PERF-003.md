# AP-PY-PERF-003 — Building lists manually in loops instead of comprehensions

**Category:** performance | **Severity:** warn
**Frameworks:** [plain]

## Summary
Appending to a list inside a `for` loop is slower than a list comprehension and less readable. Prefer comprehensions or built-ins like `map` and `filter`.

## Do Not Write
```python
result = []
for x in items:
    result.append(x * 2)
```

## Instead Write
```python
result = [x * 2 for x in items]
```

## Detection
- ruff: `PERF401`

