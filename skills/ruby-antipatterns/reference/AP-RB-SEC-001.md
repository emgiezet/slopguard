# AP-RB-SEC-001 — eval, send, or constantize with user-supplied input

**Category:** security | **Severity:** blocker | **CWE:** CWE-95
**Frameworks:** [rails, plain]

## Summary
Calling `eval`, `send`, `public_send`, or `constantize` with a user-supplied string executes arbitrary Ruby code or dispatches to arbitrary methods. Use an explicit allowlist of permitted method names or class names.

## Do Not Write
```ruby
klass = params[:type].constantize
klass.send(params[:action])
```

## Instead Write
```ruby
ALLOWED = { 'export' => ExportJob, 'import' => ImportJob }.freeze
klass = ALLOWED.fetch(params[:type]) { raise ArgumentError }
```

## Detection
- opengrep: `slopguard.ruby.eval-user-input`

## References
- https://cwe.mitre.org/data/definitions/95.html
