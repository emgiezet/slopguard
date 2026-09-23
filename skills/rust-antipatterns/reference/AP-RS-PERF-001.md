# AP-RS-PERF-001 — Integer arithmetic without overflow protection in library code

**Category:** security | **Severity:** warn | **CWE:** CWE-190
**Frameworks:** [plain]

## Summary
In release builds, integer overflow wraps silently in Rust (unlike debug builds which panic). In security-sensitive arithmetic — buffer sizes, offsets, counts — use the `checked_*`, `saturating_*`, or `wrapping_*` family of methods to handle overflow explicitly.

## Do Not Write
```rust
let total = count * item_size;   // wraps silently in release mode
let buf = vec![0u8; total];
```

## Instead Write
```rust
let total = count.checked_mul(item_size).ok_or(Error::Overflow)?;
let buf = vec![0u8; total];
```

## References
- https://cwe.mitre.org/data/definitions/190.html
