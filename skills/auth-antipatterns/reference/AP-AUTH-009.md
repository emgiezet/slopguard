# AP-AUTH-009 — Account enumeration through different responses, status codes, or timing on login and reset

**Category:** security | **Severity:** error | **CWE:** CWE-204
**Frameworks:** [plain]

## Summary
Returning different error messages, HTTP status codes, or measurably different response times for a bad email versus a bad password reveals whether an account exists to an unauthenticated caller. Always complete the full password-verification step (using a dummy hash when the account is absent) and return the same message, status code, and approximate timing for every authentication failure. A small constant-time delay after failure eliminates residual timing differences.

## Do Not Write
```
user = db.find_user(email)
if user is None:
    return error(404, "No account found")   # reveals account existence
if not ph.verify(user.password_hash, password):
    return error(401, "Wrong password")     # different message reveals more
```

## Instead Write
```
DUMMY = "$argon2id$v=19$m=65536,t=2,p=2$fakesalt$fakehash"
user  = db.find_user(email)
ok    = ph.verify(user.password_hash if user else DUMMY, password)
if not user or not ok:
    return error(401, "Invalid credentials")  # identical response always
```

## References
- https://cwe.mitre.org/data/definitions/204.html
