# AP-GO-MAINT-002 — panic / log.Fatal / os.Exit in library code

**Category:** maintainability | **Severity:** error
**Frameworks:** [plain]

## Summary
Library code that calls `panic`, `log.Fatal`, or `os.Exit` takes control away from the caller and makes testing impossible. Return errors instead and let the application's `main` function decide how to handle them.

## Do Not Write
func LoadConfig(path string) Config {
    f, err := os.Open(path)
    if err != nil { log.Fatal(err) }
}

## Instead Write
func LoadConfig(path string) (Config, error) {
    f, err := os.Open(path)
    if err != nil { return Config{}, fmt.Errorf("open config: %w", err) }
}

## Detection
- golangci-lint: `revive`

