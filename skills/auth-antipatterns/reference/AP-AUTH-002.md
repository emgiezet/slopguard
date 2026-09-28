# AP-AUTH-002 — Password-reset or verification tokens stored in plaintext, reusable, or without expiry

**Category:** security | **Severity:** blocker | **CWE:** CWE-640, CWE-312
**Frameworks:** [plain]

## Summary
Password-reset and email-verification tokens stored in plaintext can be extracted by anyone with database read access and replayed indefinitely. Store only the SHA-256 digest of the token, mark it as consumed on first correct use, and expire it after at most 15 minutes. Deliver the raw token to the user out-of-band and do not retain it.

## Do Not Write
```
token = str(uuid.uuid4())                       # plaintext, reusable
db.execute("UPDATE users SET reset_token=? WHERE id=?", [token, uid])
```

## Instead Write
```
raw    = secrets.token_urlsafe(32)
digest = hashlib.sha256(raw.encode()).hexdigest()
expiry = datetime.utcnow() + timedelta(minutes=15)
db.execute(
    "UPDATE users SET token_hash=?, used=0, expires=? WHERE id=?",
    [digest, expiry, uid],
)
send_email(raw)                                 # store hash, send raw
```

## References
- https://cwe.mitre.org/data/definitions/640.html
- https://cwe.mitre.org/data/definitions/312.html
