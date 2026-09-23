# AP-PHP-MAINT-004 — Empty catch block or swallowing Throwable without handling

**Category:** maintainability | **Severity:** error | **CWE:** CWE-390
**Frameworks:** [laravel, symfony, plain]

## Summary
A catch block that does nothing silently discards the error. Catch the narrowest exception type, log it with context, and either recover or rethrow so the caller knows something went wrong.

## Do Not Write
```php
try { $this->send($payload); } catch (\Throwable $e) { }
```

## Instead Write
```php
try {
    $this->send($payload);
} catch (ConnectionException $e) {
    Log::error('Send failed', ['error' => $e->getMessage()]);
    throw $e;
}
```

## References
- https://cwe.mitre.org/data/definitions/390.html
