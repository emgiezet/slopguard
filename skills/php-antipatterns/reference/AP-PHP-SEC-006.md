# AP-PHP-SEC-006 — Weak password hashing or insecure random for tokens

**Category:** security | **Severity:** blocker | **CWE:** CWE-327, CWE-330
**Frameworks:** [laravel, symfony, plain]

## Summary
MD5 and SHA-1 are fast hashes unsuitable for passwords. `rand()`, `mt_rand()`, and `uniqid()` are not cryptographically secure and must not generate tokens or secrets. Use `Hash::make` / `password_hash` for passwords and `random_bytes` / `Str::random` for tokens.

## Do Not Write
```php
$token = md5($user->email . time());
$reset = uniqid('reset_', true);
```

## Instead Write
```php
$token = Str::random(64);
$reset = bin2hex(random_bytes(32));
```

## Detection
- opengrep: `slopguard.php.weak-password-hash`
- opengrep: `slopguard.php.insecure-random-token`

## References
- https://cwe.mitre.org/data/definitions/327.html
- https://cwe.mitre.org/data/definitions/330.html
