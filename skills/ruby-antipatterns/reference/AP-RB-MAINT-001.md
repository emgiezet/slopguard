# AP-RB-MAINT-001 — rescue Exception instead of specific error type

**Category:** maintainability | **Severity:** error | **CWE:** CWE-396
**Frameworks:** [rails, plain]

## Summary
Rescuing `Exception` catches everything including `SignalException::Interrupt` and `SystemExit`, interfering with normal Ruby process lifecycle. Rescue `StandardError` at the widest appropriate scope and specific subtypes wherever possible.

## Do Not Write
```ruby
begin
  risky_operation
rescue Exception => e
  # swallows Ctrl+C and SystemExit
end
```

## Instead Write
```ruby
begin
  risky_operation
rescue NetworkError => e
  logger.error("Network failure: #{e.message}")
  raise
end
```

## References
- https://cwe.mitre.org/data/definitions/396.html
