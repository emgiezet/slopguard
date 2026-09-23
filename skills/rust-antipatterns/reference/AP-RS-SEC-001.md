# AP-RS-SEC-001 — unsafe block without a safety comment

**Category:** security | **Severity:** error
**Frameworks:** [plain]

## Summary
An `unsafe` block bypasses Rust's memory-safety guarantees. Every `unsafe` block must be accompanied by a `// SAFETY:` comment that explains the invariants that make it sound — who is responsible for upholding those invariants and why.

## Do Not Write
```rust
unsafe {
    let ptr = data.as_ptr().add(offset);
    *ptr
}
```

## Instead Write
```rust
// SAFETY: offset is validated to be within [0, data.len()) before this call
unsafe {
    let ptr = data.as_ptr().add(offset);
    *ptr
}
```

## Detection
- opengrep: `slopguard.rs.unsafe-block`

