# AP-PHP-SEC-009 — TLS verification disabled in HTTP client

**Category:** security | **Severity:** blocker | **CWE:** CWE-295
**Frameworks:** [laravel, symfony, plain]

## Summary
Setting `verify => false` or `CURLOPT_SSL_VERIFYPEER => false` disables certificate validation and exposes the connection to man-in-the-middle attacks. Supply a valid CA bundle instead.

## Do Not Write
```php
Http::withOptions(['verify' => false])->get($url);
```

## Instead Write
```php
Http::withOptions(['verify' => '/etc/ssl/certs/ca-certificates.crt'])->get($url);
```

## References
- https://cwe.mitre.org/data/definitions/295.html
