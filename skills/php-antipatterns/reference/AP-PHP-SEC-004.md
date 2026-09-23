# AP-PHP-SEC-004 — Unescaped Blade output with {!! !!}

**Category:** security | **Severity:** blocker | **CWE:** CWE-79
**Frameworks:** [laravel]

## Summary
The `{!! !!}` syntax skips HTML escaping. If the value originates from user input, this allows stored or reflected XSS. Use `{{ }}` for user-supplied content and a dedicated HTML sanitizer for rich text.

## Do Not Write
```php
<p>{!! $user->bio !!}</p>
```

## Instead Write
```php
<p>{{ $user->bio }}</p>
```

## Detection
- opengrep: `slopguard.php.laravel.blade-unescaped-output`

## References
- https://cwe.mitre.org/data/definitions/79.html
