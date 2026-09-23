# AP-RS-SEC-002 — unwrap or expect in library code without error context

**Category:** maintainability | **Severity:** warn
**Frameworks:** [plain]

## Summary
Calling `.unwrap()` or `.expect("message")` in library functions panics on `None` or `Err`, taking control away from the caller and making error handling impossible for the consumer. Return `Result` or `Option` and propagate errors with `?`.

## Do Not Write
```rust
pub fn parse_config(s: &str) -> Config {
    serde_json::from_str(s).unwrap()  // panics the caller's thread
}
```

## Instead Write
```rust
pub fn parse_config(s: &str) -> Result<Config, serde_json::Error> {
    serde_json::from_str(s)
}
```

## Detection
- opengrep: `slopguard.rs.unwrap-in-library`

