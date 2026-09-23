# AP-PY-SEC-005 — TLS verification disabled with verify=False

**Category:** security | **Severity:** blocker | **CWE:** CWE-295
**Frameworks:** [plain]

## Summary
Setting `verify=False` disables certificate validation, exposing connections to man-in-the-middle attacks. Always leave verification enabled; supply a CA bundle path when dealing with internal PKI.

## Do Not Write
```python
resp = requests.get(url, verify=False)
```

## Instead Write
```python
resp = requests.get(url, verify="/etc/ssl/certs/ca-certificates.crt")
```

## Detection
- ruff: `S501`

## References
- https://cwe.mitre.org/data/definitions/295.html
