# AP-GO-PERF-002 — Unclosed response body or SQL rows, missing rows.Err() check

**Category:** performance | **Severity:** error | **CWE:** CWE-404
**Frameworks:** [plain]

## Summary
Failing to close an HTTP response body or database rows leaks connections and file descriptors. Always defer `Close()` immediately after confirming no error, and check `rows.Err()` after the iteration loop.

## Do Not Write
resp, err := client.Do(req)
// resp.Body never closed — connection leak

## Instead Write
resp, err := client.Do(req)
if err != nil { return err }
defer resp.Body.Close()
rows, err := db.QueryContext(ctx, "SELECT id FROM items")
if err != nil { return err }
defer rows.Close()
for rows.Next() { /* … */ }
return rows.Err()

## Detection
- golangci-lint: `bodyclose`
- golangci-lint: `sqlclosecheck`
- golangci-lint: `rowserrcheck`

## References
- https://cwe.mitre.org/data/definitions/404.html
