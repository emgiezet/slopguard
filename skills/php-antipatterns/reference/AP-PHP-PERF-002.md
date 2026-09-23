# AP-PHP-PERF-002 — Model::all() or unbounded get() on large tables

**Category:** performance | **Severity:** warn | **CWE:** CWE-400
**Frameworks:** [laravel]

## Summary
Loading every row of a growing table into memory causes unbounded memory use and slow responses. Use pagination, `chunkById`, `lazyById`, or `cursor` for large result sets.

## Do Not Write
```php
$products = Product::all(); // loads millions of rows
```

## Instead Write
```php
Product::chunkById(500, function ($chunk) { /* process */ });
```

## Detection
- opengrep: `slopguard.php.laravel.unbounded-all`

## References
- https://cwe.mitre.org/data/definitions/400.html
