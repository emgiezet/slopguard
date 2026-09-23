# AP-RS-SEC-005 — str::from_utf8_unchecked on unvalidated byte slices

**Category:** security | **Severity:** error | **CWE:** CWE-125
**Frameworks:** [plain]

## Summary
"`str::from_utf8_unchecked` skips the UTF-8 validity check and returns a `&str` from any byte slice, including invalid UTF-8. Subsequent string operations that assume UTF-8 may read beyond intended boundaries or produce incorrect output. Use `str::from_utf8` and propagate the error."

## Do Not Write
```rust
let s = unsafe { std::str::from_utf8_unchecked(&bytes) };
```

## Instead Write
```rust
let s = std::str::from_utf8(&bytes)?;
```

## Detection
- opengrep: `slopguard.rs.from-utf8-unchecked`

## References
- https://cwe.mitre.org/data/definitions/125.html
