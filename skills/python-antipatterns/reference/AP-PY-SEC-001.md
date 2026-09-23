# AP-PY-SEC-001 — SQL built with f-strings, % formatting, or .format()

**Category:** security | **Severity:** blocker | **CWE:** CWE-89
**Frameworks:** [django, sqlalchemy, plain]

## Summary
Embedding Python variables directly into SQL strings opens the query to injection attacks. Always pass parameters as a second argument to the execute method or use the ORM's query builder.

## Do Not Write
```python
cursor.execute(f"SELECT * FROM users WHERE email = '{email}'")
```

## Instead Write
```python
cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
```

## Detection
- ruff: `S608`
- opengrep: `slopguard.py.django-raw-sql-format`
- opengrep: `slopguard.py.sqlalchemy-text-fstring`

## References
- https://cwe.mitre.org/data/definitions/89.html
