# AP-AUTH-006 — E-mail or password changed without re-authentication and without notifying the previous address

**Category:** security | **Severity:** blocker | **CWE:** CWE-620, CWE-287
**Frameworks:** [plain]

## Summary
Allowing users to change their email address or password without first re-entering their current credential lets an attacker with an unattended session silently take over the account. Verify the current credential before applying the change, then notify the previous address so the legitimate owner can detect and reverse it. Both steps together close the account-takeover path through session hijacking.

## Do Not Write
```
def change_password(user_id, new_pw):
    user = User.get(user_id)
    user.update(password_hash=ph.hash(new_pw))  # no re-auth, no notice
```

## Instead Write
```
def change_password(user_id, current_pw, new_pw):
    user = User.get(user_id)
    if not ph.verify(user.password_hash, current_pw):
        raise AuthError("re-authentication required")
    user.update(password_hash=ph.hash(new_pw))
    mail(user.email, subject="Your password was changed")
```

## References
- https://cwe.mitre.org/data/definitions/620.html
- https://cwe.mitre.org/data/definitions/287.html
