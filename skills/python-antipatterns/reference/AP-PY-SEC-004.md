# AP-PY-SEC-004 — requests or httpx call without timeout

**Category:** security | **Severity:** error | **CWE:** CWE-400
**Frameworks:** [plain]

## Summary
An HTTP call without a timeout can block the thread indefinitely when the server is slow or unresponsive. Always supply an explicit `timeout=` parameter.

## Do Not Write
```python
resp = requests.get("https://api.example.com/data")
```

## Instead Write
```python
resp = requests.get("https://api.example.com/data", timeout=10)
```

## Detection
- ruff: `S113`

## References
- https://cwe.mitre.org/data/definitions/400.html
