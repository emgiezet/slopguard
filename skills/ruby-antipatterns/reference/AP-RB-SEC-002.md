# AP-RB-SEC-002 — YAML.load without SafeLoader / Psych safe_load

**Category:** security | **Severity:** blocker | **CWE:** CWE-502
**Frameworks:** [rails, plain]

## Summary
Ruby's `YAML.load` uses the Psych full-trust parser by default, allowing the `!ruby/object` tag to instantiate arbitrary Ruby objects. This enables deserialization gadget attacks. Always use `YAML.safe_load` which restricts types to primitive Ruby objects.

## Do Not Write
```ruby
config = YAML.load(params[:config])
```

## Instead Write
```ruby
config = YAML.safe_load(params[:config])
```

## References
- https://cwe.mitre.org/data/definitions/502.html
