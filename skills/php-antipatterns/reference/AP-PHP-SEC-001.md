# AP-PHP-SEC-001 — SQL built by string interpolation or concatenation

**Category:** security | **Severity:** blocker | **CWE:** CWE-89
**Frameworks:** [laravel, symfony, plain]

## Summary
Building SQL by embedding variables directly into the query string lets attackers manipulate query logic. Always use parameterized queries or the query builder's binding methods.

## Do Not Write
```php
$results = DB::select("SELECT * FROM users WHERE email = '$email'");
```

## Instead Write
```php
$results = DB::select('SELECT * FROM users WHERE email = ?', [$email]);
```

## Detection
- psalm: `TaintedSql`
- opengrep: `slopguard.php.laravel.raw-sql-interpolation`

## References
- https://cwe.mitre.org/data/definitions/89.html
- https://cheatsheetseries.owasp.org/cheatsheets/Query_Parameterization_Cheat_Sheet.html
