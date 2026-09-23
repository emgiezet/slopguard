# AP-PY-SEC-003 — pickle.loads or yaml.load on external data

**Category:** security | **Severity:** blocker | **CWE:** CWE-502
**Frameworks:** [plain]

## Summary
Both `pickle.loads` and `yaml.load` (with the default Loader) execute arbitrary Python code when deserializing attacker-controlled data. Use `json` for data exchange or `yaml.safe_load` for YAML.

## Do Not Write
```python
obj = pickle.loads(request.data)
cfg = yaml.load(stream)            # uses FullLoader by default
```

## Instead Write
```python
data = json.loads(request.data)
cfg = yaml.safe_load(stream)
```

## Detection
- ruff: `S301`
- ruff: `S506`

## References
- https://cwe.mitre.org/data/definitions/502.html
