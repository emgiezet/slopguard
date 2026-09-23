# AP-PHP-SEC-005 — Mass assignment from raw request data

**Category:** security | **Severity:** error | **CWE:** CWE-915
**Frameworks:** [laravel]

## Summary
Passing `$request->all()` directly to `create()` or `fill()` lets clients write to any column including roles, admin flags, and foreign keys. Use `$request->validated()` with `$fillable` set.

## Do Not Write
```php
$user = User::create($request->all());
```

## Instead Write
```php
$user = User::create($request->validated());
```

## Detection
- opengrep: `slopguard.php.laravel.mass-assignment-request-all`

## References
- https://cwe.mitre.org/data/definitions/915.html
