# AP-RS-MAINT-001 — Serde deserialization without deny_unknown_fields or bound

**Category:** security | **Severity:** warn
**Frameworks:** [plain]

## Summary
Without `#[serde(deny_unknown_fields)]`, extra keys in JSON silently pass through, which can cause confusion about what was actually parsed and may bypass schema-level validation. Without `#[serde(bound = "...")]`, the compiler generates overly broad `T: Deserialize` bounds that can be satisfied by unintended types.

## Do Not Write
```rust
#[derive(Deserialize)]
struct Config { host: String, port: u16 }  // unknown fields accepted silently
```

## Instead Write
```rust
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Config { host: String, port: u16 }
```

