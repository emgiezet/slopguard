# AP-GO-SEC-001 — SQL built by string formatting or concatenation

**Category:** security | **Severity:** blocker | **CWE:** CWE-89
**Frameworks:** [plain, gorm, sqlx]

## Summary
Using `fmt.Sprintf` or `+` to assemble SQL statements allows injection of arbitrary SQL through user-controlled values. Use placeholder parameters (`$1`, `?`) consistently.

## Do Not Write
rows, _ := db.Query("SELECT * FROM users WHERE email = '" + email + "'")

## Instead Write
rows, err := db.QueryContext(ctx, "SELECT * FROM users WHERE email = $1", email)

## Detection
- golangci-lint: `gosec:G201`
- golangci-lint: `gosec:G202`

## References
- https://cwe.mitre.org/data/definitions/89.html
