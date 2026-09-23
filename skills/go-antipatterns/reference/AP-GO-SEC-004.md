# AP-GO-SEC-004 — math/rand used for tokens or cryptographic material

**Category:** security | **Severity:** blocker | **CWE:** CWE-338
**Frameworks:** [plain]

## Summary
The `math/rand` package is a pseudo-random number generator seeded deterministically; its output can be predicted. Use `crypto/rand` when generating tokens, nonces, or any security-sensitive values.

## Do Not Write
token := fmt.Sprintf("%d", rand.Int63())

## Instead Write
b := make([]byte, 32)
if _, err := rand.Read(b); err != nil { return err }
token := hex.EncodeToString(b) // crypto/rand.Read

## Detection
- golangci-lint: `gosec:G404`

## References
- https://cwe.mitre.org/data/definitions/338.html
