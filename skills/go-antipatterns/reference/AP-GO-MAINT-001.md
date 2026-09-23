# AP-GO-MAINT-001 — Ignored errors or incorrect error wrapping

**Category:** maintainability | **Severity:** error | **CWE:** CWE-391
**Frameworks:** [plain]

## Summary
Assigning an error to `_` or comparing wrapped errors with `==` instead of `errors.Is`/`errors.As` leads to silent failures and incorrect error handling. Always handle errors and wrap with `%w` to preserve the chain.

## Do Not Write
val, _ := strconv.Atoi(s)
if err == sql.ErrNoRows { /* won't match wrapped errors */ }

## Instead Write
val, err := strconv.Atoi(s)
if err != nil { return fmt.Errorf("parse id: %w", err) }
if errors.Is(err, sql.ErrNoRows) { /* correct */ }

## Detection
- golangci-lint: `errorlint`

## References
- https://cwe.mitre.org/data/definitions/391.html
