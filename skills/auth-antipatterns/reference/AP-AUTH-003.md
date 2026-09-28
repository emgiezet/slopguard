# AP-AUTH-003 — Passwords stored with a fast or unsalted hash instead of argon2id, scrypt, or bcrypt

**Category:** security | **Severity:** blocker | **CWE:** CWE-916, CWE-759
**Frameworks:** [plain]

## Summary
MD5, SHA-1, and unsalted SHA-256 are fast hashes; a modern GPU can evaluate billions of candidates per second against a leaked database. Use argon2id (or bcrypt at cost≥12, or scrypt) with a per-password salt so cracking one hash cannot be parallelised across the whole database. The argon2-cffi and passlib libraries expose argon2id in Python; equivalent libraries are available for Go, Node.js, and PHP.

## Do Not Write
```
import hashlib
stored = hashlib.md5(password.encode()).hexdigest()  # fast, no salt
```

## Instead Write
```
from argon2 import PasswordHasher
ph     = PasswordHasher(time_cost=2, memory_cost=65536, parallelism=2)
stored = ph.hash(password)      # argon2id with salt and calibrated cost
```

## References
- https://cwe.mitre.org/data/definitions/916.html
- https://cwe.mitre.org/data/definitions/759.html
