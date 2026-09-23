# AP-PHP-SEC-002 — unserialize on externally controlled data

**Category:** security | **Severity:** blocker | **CWE:** CWE-502
**Frameworks:** [laravel, symfony, plain]

## Summary
PHP object deserialization executes magic methods on the restored object graph. Attackers can craft payloads that exploit existing classes to run arbitrary code. Use JSON or restrict allowed classes.

## Do Not Write
```php
$obj = unserialize($request->input('payload'));
```

## Instead Write
```php
$data = json_decode($request->input('payload'), true);
```

## Detection
- psalm: `TaintedUnserialize`

## References
- https://cwe.mitre.org/data/definitions/502.html
