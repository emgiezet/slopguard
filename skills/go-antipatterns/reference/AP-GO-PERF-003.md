# AP-GO-PERF-003 — Unbounded goroutine-per-item spawning or goroutine leak

**Category:** performance | **Severity:** error | **CWE:** CWE-400
**Frameworks:** [plain]

## Summary
Spawning one goroutine per item in an unbounded loop can exhaust memory and scheduler capacity when the input is large or arrives faster than the goroutines complete. Use `errgroup` with `SetLimit` or a worker-pool pattern with context cancellation.

## Do Not Write
for _, item := range items {
    go process(item) // no limit, no error handling
}

## Instead Write
g, ctx := errgroup.WithContext(ctx)
g.SetLimit(runtime.NumCPU())
for _, item := range items {
    item := item
    g.Go(func() error { return process(ctx, item) })
}
return g.Wait()

## Detection
- opengrep: `slopguard.go.goroutine-per-item-unbounded`

## References
- https://cwe.mitre.org/data/definitions/400.html
