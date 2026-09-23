# AP-PHP-SEC-008 — File path derived from request input

**Category:** security | **Severity:** blocker | **CWE:** CWE-22
**Frameworks:** [laravel, symfony, plain]

## Summary
Using a request parameter directly as a file path lets attackers traverse directories and read sensitive files. Use a server-side allowlist or map identifiers to physical paths.

## Do Not Write
```php
return Storage::get($request->input('path'));
```

## Instead Write
```php
$allowed = ['report' => 'reports/monthly.pdf'];
return Storage::get($allowed[$request->input('type')] ?? abort(400));
```

## Detection
- psalm: `TaintedFile`

## References
- https://cwe.mitre.org/data/definitions/22.html
