# AP-PHP-MAINT-002 — env() called outside config files

**Category:** maintainability | **Severity:** error
**Frameworks:** [laravel]

## Summary
Calling `env()` directly in application code means the value is not available after `php artisan config:cache` is run. Always access environment values through `config()` and define them in a config file.

## Do Not Write
```php
$key = env('STRIPE_SECRET');
```

## Instead Write
```php
$key = config('services.stripe.secret');
```

