# AP-RS-MAINT-002 — Missing error context in the ? operator chain

**Category:** maintainability | **Severity:** warn
**Frameworks:** [plain]

## Summary
A bare `?` at the end of a function converts the underlying error to the return type but discards the context of where it occurred. Use `.context()`/`.with_context()` from `anyhow` or wrap with a domain-specific error variant to preserve call-site information.

## Do Not Write
```rust
fn load(path: &Path) -> Result<Config> {
    let text = std::fs::read_to_string(path)?;  // no context on failure
    Ok(serde_json::from_str(&text)?)
}
```

## Instead Write
```rust
fn load(path: &Path) -> Result<Config> {
    let text = std::fs::read_to_string(path)
        .with_context(|| format!("reading config at {}", path.display()))?;
    serde_json::from_str(&text).context("parsing config JSON")
}
```

