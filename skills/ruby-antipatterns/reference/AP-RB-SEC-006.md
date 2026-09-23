# AP-RB-SEC-006 — SecureRandom not used for security tokens

**Category:** security | **Severity:** error | **CWE:** CWE-330
**Frameworks:** [rails, plain]

## Summary
Using `rand`, `srand`, or time-based values for tokens or identifiers produces predictable output. Ruby's `SecureRandom` draws from the OS CSPRNG and is appropriate for tokens, nonces, and password reset links.

## Do Not Write
```ruby
token = rand(10 ** 20).to_s(36)
```

## Instead Write
```ruby
token = SecureRandom.hex(32)
```

## References
- https://cwe.mitre.org/data/definitions/330.html
