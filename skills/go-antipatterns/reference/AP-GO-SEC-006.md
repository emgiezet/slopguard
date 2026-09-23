# AP-GO-SEC-006 — File path from user input without validation

**Category:** security | **Severity:** blocker | **CWE:** CWE-22
**Frameworks:** [plain]

## Summary
Opening a file at a path derived from user input without cleaning and prefix-checking it allows directory traversal. Use `filepath.Clean` followed by a `strings.HasPrefix` check against the allowed base directory; in Go 1.24+ prefer `os.Root`.

## Do Not Write
data, _ := os.ReadFile("/uploads/" + req.FormValue("file"))

## Instead Write
clean := filepath.Clean(filepath.Join("/uploads", req.FormValue("file")))
if !strings.HasPrefix(clean, "/uploads/") { http.Error(w, "forbidden", 403); return }
data, err := os.ReadFile(clean)

## Detection
- golangci-lint: `gosec:G304`
- golangci-lint: `gosec:G305`

## References
- https://cwe.mitre.org/data/definitions/22.html
