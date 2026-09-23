# AP-PHP-PERF-001 — N+1 — lazy-loading relations in loops or views

**Category:** performance | **Severity:** error
**Frameworks:** [laravel]

## Summary
Accessing a relation property inside a loop or Blade view triggers a separate database query per iteration. Eager-load relations with `->with()` or call `Model::shouldBeStrict()` in development to surface violations immediately.

## Do Not Write
```php
foreach (Order::all() as $order) {
    echo $order->customer->name; // query per iteration
}
```

## Instead Write
```php
foreach (Order::with('customer')->get() as $order) {
    echo $order->customer->name;
}
```

