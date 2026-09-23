# AP-AGENT-006 — Hard-coded real credentials written to files

**Category:** agent | **Severity:** blocker | **CWE:** CWE-798

## Summary
Writing an actual credential value into source code "temporarily for testing" commits it to the file and potentially to version history. Use placeholder values in examples and load real values from environment variables at runtime.

## Do Not Write
DATABASE_URL=postgres://admin:realpassword@prod-db:5432/app

## Instead Write
DATABASE_URL=postgres://user:${DB_PASSWORD}@db:5432/app

## References
- https://cwe.mitre.org/data/definitions/798.html
