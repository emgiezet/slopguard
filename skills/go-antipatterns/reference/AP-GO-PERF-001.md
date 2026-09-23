# AP-GO-PERF-001 — HTTP client without timeout or context

**Category:** performance | **Severity:** error | **CWE:** CWE-400
**Frameworks:** [plain]

## Summary
Using `http.Get` or a bare `&http.Client{}` with no timeout means a slow or unresponsive server blocks the goroutine indefinitely. Always use `http.NewRequestWithContext` and a client with `Timeout` set.

## Do Not Write
resp, err := http.Get("https://api.example.com/data")

## Instead Write
ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
defer cancel()
req, _ := http.NewRequestWithContext(ctx, "GET", "https://api.example.com/data", nil)
resp, err := client.Do(req)

## Detection
- golangci-lint: `noctx`
- opengrep: `slopguard.go.http-client-without-timeout`

## References
- https://cwe.mitre.org/data/definitions/400.html
