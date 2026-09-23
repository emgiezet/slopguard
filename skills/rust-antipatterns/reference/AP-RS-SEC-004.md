# AP-RS-SEC-004 — mem::transmute without explicit safety justification

**Category:** security | **Severity:** error
**Frameworks:** [plain]

## Summary
"`mem::transmute` reinterprets the raw bytes of a value as a different type with no validation, easily producing invalid values (e.g. transmuting an integer to an enum skips discriminant checks). Use safe conversions; when transmute is the only option, document the layout guarantee in a SAFETY comment."

## Do Not Write
```rust
let x: u64 = 0;
let y: f64 = unsafe { mem::transmute(x) }; // no SAFETY comment
```

## Instead Write
```rust
let x: u64 = 0;
// SAFETY: every bit pattern is a valid f64
let y: f64 = unsafe { mem::transmute(x) };
```

## Detection
- opengrep: `slopguard.rs.mem-transmute`

