# AP-PHP-SEC-003 — Shell command built from request input

**Category:** security | **Severity:** blocker | **CWE:** CWE-78
**Frameworks:** [laravel, symfony, plain]

## Summary
Interpolating user input into shell commands lets attackers run arbitrary OS commands. Use Symfony Process with an argument array so the shell never interprets special characters.

## Do Not Write
```php
exec("convert " . $request->input('file') . " output.png");
```

## Instead Write
```php
(new Process(['convert', $request->input('file'), 'output.png']))->mustRun();
```

## Detection
- psalm: `TaintedShell`

## References
- https://cwe.mitre.org/data/definitions/78.html
