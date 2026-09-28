# AP-AUTH-004 — Session identifier not rotated on login and privilege change; no idle and absolute lifetime

**Category:** security | **Severity:** error | **CWE:** CWE-384
**Frameworks:** [plain]

## Summary
When a user logs in without the session identifier being regenerated, an attacker who planted a known session cookie before login gains full access after the victim enters credentials (session fixation). Regenerate the session ID immediately after authentication and again on any privilege change. Enforce an idle timeout of approximately 30 minutes and an absolute lifetime of approximately 8 hours regardless of activity.

## Do Not Write
```
app.post('/login', (req, res) => {
    req.session.userId = user.id;   // old session ID kept
    res.redirect('/dashboard');
});
```

## Instead Write
```
app.post('/login', (req, res) => {
    req.session.regenerate((err) => {
        if (err) return next(err);
        req.session.userId = user.id; // new ID after regenerate
        res.redirect('/dashboard');
    });
});
```

## References
- https://cwe.mitre.org/data/definitions/384.html
