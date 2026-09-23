# AP-PHP-MAINT-003 — Missing strict_types or untyped parameters in new code

**Category:** maintainability | **Severity:** warn
**Frameworks:** [laravel, symfony, plain]

## Summary
Without `declare(strict_types=1)` PHP silently coerces types and masks bugs. All new files should declare strict types; all new functions and methods should have typed parameters and return types.

## Do Not Write
```php
function process($data) { return $data['total'] * 1.2; }
```

## Instead Write
```php
declare(strict_types=1);
function process(array $data): float { return $data['total'] * 1.2; }
```

## Detection
- phpstan: `missingType.parameter`

