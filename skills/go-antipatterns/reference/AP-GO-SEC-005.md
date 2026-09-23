# AP-GO-SEC-005 — TLS verification disabled with InsecureSkipVerify

**Category:** security | **Severity:** blocker | **CWE:** CWE-295
**Frameworks:** [plain]

## Summary
Setting `InsecureSkipVerify: true` means the server certificate is never validated. An attacker in a privileged network position can intercept all traffic. Provide a proper `RootCAs` pool instead.

## Do Not Write
tr := &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}

## Instead Write
pool, _ := x509.SystemCertPool()
tr := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool}}

## Detection
- golangci-lint: `gosec:G402`

## References
- https://cwe.mitre.org/data/definitions/295.html
