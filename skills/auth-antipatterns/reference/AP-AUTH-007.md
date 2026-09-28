# AP-AUTH-007 — Existing sessions and refresh tokens not invalidated after password reset or MFA change

**Category:** security | **Severity:** error | **CWE:** CWE-613
**Frameworks:** [plain]

## Summary
After a password reset or MFA method change, active sessions and refresh tokens issued before the change remain valid and can be used by an attacker who had obtained them. Invalidate every session except the one performing the reset and revoke all refresh tokens tied to the account at the same moment the credential changes. Incrementing a per-user session-version counter is the simplest server-side mechanism for bulk session invalidation.

## Do Not Write
```
func resetPassword(uid int, newHash string) error {
    // attacker sessions stay valid after the reset
    return db.Exec("UPDATE users SET pw_hash=? WHERE id=?", newHash, uid)
}
```

## Instead Write
```
func resetPassword(uid int, newHash string) error {
    if err := db.Exec(
        "UPDATE users SET pw_hash=?, session_version=session_version+1 WHERE id=?",
        newHash, uid,
    ); err != nil { return err }
    return db.Exec("DELETE FROM refresh_tokens WHERE user_id=?", uid)
}
```

## References
- https://cwe.mitre.org/data/definitions/613.html
