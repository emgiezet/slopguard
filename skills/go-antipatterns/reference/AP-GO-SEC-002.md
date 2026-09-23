# AP-GO-SEC-002 — Shell command with shell=true or user-supplied string

**Category:** security | **Severity:** blocker | **CWE:** CWE-78
**Frameworks:** [plain]

## Summary
Passing a user-controlled string to `exec.Command("sh", "-c", input)` allows shell metacharacter injection. Pass each argument as a separate string so the OS invokes the binary directly without a shell.

## Do Not Write
cmd := exec.Command("sh", "-c", "convert "+userFile+" output.png")

## Instead Write
cmd := exec.Command("convert", userFile, "output.png")

## Detection
- golangci-lint: `gosec:G204`

## References
- https://cwe.mitre.org/data/definitions/78.html
