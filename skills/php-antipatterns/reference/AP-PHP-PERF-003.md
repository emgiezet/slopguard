# AP-PHP-PERF-003 — Database query inside a loop

**Category:** performance | **Severity:** error
**Frameworks:** [laravel]

## Summary
Issuing a query inside a `foreach` multiplies database round-trips by the collection size. Collect all needed IDs first, then fetch with a single `whereIn` query.

## Do Not Write
```php
foreach ($ids as $id) {
    $item = Item::find($id);
}
```

## Instead Write
```php
$items = Item::whereIn('id', $ids)->get()->keyBy('id');
```

## Detection
- opengrep: `slopguard.php.laravel.query-in-loop`

