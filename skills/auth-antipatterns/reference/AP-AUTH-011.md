# AP-AUTH-011 — OTP/MFA codes with unlimited attempts, no single-use enforcement, or carried in URLs and logs

**Category:** security | **Severity:** error | **CWE:** CWE-307, CWE-287
**Frameworks:** [plain]

## Summary
OTP and MFA codes with unlimited verification attempts can be brute-forced in seconds when the code space is small (a 6-digit code has only one million possibilities). Codes must be single-use (consumed on first correct entry), expire after a short window (5 minutes is standard), be rate-limited to a small attempt count (5 is typical), and must never appear in URL query strings where they are captured by server logs, browser history, and Referer headers.

## Do Not Write
```
// unlimited attempts; code stays valid after use
if ($request->input('otp') === $user->otp_code) {
    $user->markMfaVerified();
}
```

## Instead Write
```
if ($user->otp_attempts >= 5 || $user->otp_expires_at < now()) {
    return response('OTP expired or locked', 429);
}
if (!hash_equals($user->otp_code, $request->input('otp'))) {
    $user->increment('otp_attempts');
    return response('Invalid OTP', 401);
}
$user->update(['otp_code' => null, 'otp_attempts' => 0]); // consumed
```

## References
- https://cwe.mitre.org/data/definitions/307.html
- https://cwe.mitre.org/data/definitions/287.html
