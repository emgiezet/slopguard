# AP-RS-SEC-003 — Dereferencing raw pointers in unsafe blocks without bounds check

**Category:** security | **Severity:** error
**Frameworks:** [plain]

## Summary
Dereferencing raw pointers bypasses Rust's borrow checker entirely. The pointer may be null, dangling, or point outside allocated memory. Every raw pointer dereference must be preceded by explicit bounds and validity checks.

## Do Not Write
```rust
unsafe {
    let val = *ptr;  // no null or bounds check
}
```

## Instead Write
```rust
// SAFETY: ptr is non-null and points to a valid T as guaranteed by the caller
unsafe {
    assert!(!ptr.is_null());
    let val = *ptr;
}
```

## Detection
- opengrep: `slopguard.rs.raw-pointer-deref`

