# AP-PY-SEC-007 — eval or exec on externally controlled data

**Category:** security | **Severity:** blocker | **CWE:** CWE-95
**Frameworks:** [plain]

## Summary
Calling `eval()` or `exec()` with user-supplied strings executes arbitrary Python code in the current process. Replace dynamic evaluation with a static dispatch map or a proper parser.

## Do Not Write
```python
result = eval(request.form['expression'])
```

## Instead Write
```python
ops = {'+': operator.add, '-': operator.sub}
result = ops[request.form['op']](a, b)
```

## Detection
- ruff: `S307`
- ruff: `S102`

## References
- https://cwe.mitre.org/data/definitions/95.html
