# AP-PY-SEC-008 — Hard-coded passwords or API keys in source code

**Category:** security | **Severity:** blocker | **CWE:** CWE-798
**Frameworks:** [plain]

## Summary
Storing credentials directly in source code exposes them to anyone with repository access and leaks them into version control history. Load secrets from environment variables or a dedicated secret manager.

## Do Not Write
```python
DB_PASSWORD = "hunter2"
STRIPE_KEY = "sk_live_abc123"
```

## Instead Write
```python
DB_PASSWORD = os.environ["DB_PASSWORD"]
STRIPE_KEY = os.environ["STRIPE_KEY"]
```

## Detection
- ruff: `S105`
- ruff: `S106`
- betterleaks: `generic-api-key`

## References
- https://cwe.mitre.org/data/definitions/798.html
