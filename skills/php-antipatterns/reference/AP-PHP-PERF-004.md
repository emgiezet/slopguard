# AP-PHP-PERF-004 — get()->count() or get()->first() instead of SQL aggregate

**Category:** performance | **Severity:** warn
**Frameworks:** [laravel]

## Summary
Calling `->get()` hydrates the full result set before counting or taking the first item, transferring far more data than needed. Use `->count()` or `->first()` directly to let the database do the work.

## Do Not Write
```php
$count = Order::where('status', 'pending')->get()->count();
```

## Instead Write
```php
$count = Order::where('status', 'pending')->count();
```

