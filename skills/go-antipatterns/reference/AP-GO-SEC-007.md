# AP-GO-SEC-007 — Hard-coded secrets in source code

**Category:** security | **Severity:** blocker | **CWE:** CWE-798
**Frameworks:** [plain]

## Summary
Embedding credentials, API keys, or tokens directly in source code exposes them to anyone with repository access and leaks them into version history. Load secrets from environment variables or a secret manager at runtime.

## Do Not Write
const apiKey = "sk-live-abc123xyz789"

## Instead Write
apiKey := os.Getenv("API_KEY")
if apiKey == "" { log.Fatal("API_KEY not set") }

## Detection
- golangci-lint: `gosec:G101`
- betterleaks: `generic-api-key`

## References
- https://cwe.mitre.org/data/definitions/798.html
