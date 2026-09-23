# AP-PHP-PERF-005 — Heavy synchronous work inside a web request

**Category:** performance | **Severity:** warn
**Frameworks:** [laravel, symfony]

## Summary
Sending emails, calling external APIs, or processing files synchronously blocks the HTTP worker until the operation completes. Dispatch these to a background queue so the response is returned immediately.

## Do Not Write
```php
Mail::to($user)->send(new OrderConfirmation($order)); // blocks response
```

## Instead Write
```php
Mail::to($user)->queue(new OrderConfirmation($order));
```

