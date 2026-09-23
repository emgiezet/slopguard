# AP-PHP-SEC-007 — Loose comparison of secrets or hashes

**Category:** security | **Severity:** error | **CWE:** CWE-208
**Frameworks:** [laravel, symfony, plain]

## Summary
PHP's `==` operator does type coercion and is vulnerable to timing side-channels that allow hash comparison attacks. Always use `hash_equals()` when comparing secrets, tokens, or digests.

## Do Not Write
```php
if ($token == $expected) { /* proceed */ }
```

## Instead Write
```php
if (hash_equals($expected, $token)) { /* proceed */ }
```

## References
- https://cwe.mitre.org/data/definitions/208.html
