# AP-AUTH-008 — No rate limit or lockout on login, OTP verification, and password-reset endpoints

**Category:** security | **Severity:** error | **CWE:** CWE-307
**Frameworks:** [plain]

## Summary
Login, OTP verification, and password-reset endpoints that accept unlimited requests allow credential stuffing and brute-force attacks at the full speed of the attacker's network. Apply per-IP and per-account rate limits (5 attempts per minute is a conservative baseline) and temporarily lock the account after 10 consecutive failures. Return HTTP 429 with a Retry-After header so legitimate users know when to retry.

## Do Not Write
```
func loginHandler(w http.ResponseWriter, r *http.Request) {
    // no rate check — accepts unlimited guesses
    user, ok := authenticate(r.FormValue("email"), r.FormValue("password"))
    if !ok { http.Error(w, "invalid credentials", 401); return }
    startSession(w, user)
}
```

## Instead Write
```
func loginHandler(w http.ResponseWriter, r *http.Request) {
    if limiter.Exceeded(realIP(r), 5, time.Minute) {
        http.Error(w, "too many requests", 429); return
    }
    user, ok := authenticate(r.FormValue("email"), r.FormValue("password"))
    if !ok { limiter.Record(realIP(r)); http.Error(w, "invalid credentials", 401); return }
    startSession(w, user)
}
```

## References
- https://cwe.mitre.org/data/definitions/307.html
