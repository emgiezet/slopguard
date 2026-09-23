# AP-PY-SEC-006 — random module used for secrets or tokens

**Category:** security | **Severity:** error | **CWE:** CWE-330
**Frameworks:** [plain]

## Summary
The `random` module is designed for simulations and is predictable by design. For anything security-sensitive — tokens, nonces, passwords — use the `secrets` module which draws from the OS CSPRNG.

## Do Not Write
```python
token = hex(random.getrandbits(128))
```

## Instead Write
```python
import secrets
token = secrets.token_hex(32)
```

## Detection
- ruff: `S311`

## References
- https://cwe.mitre.org/data/definitions/330.html
