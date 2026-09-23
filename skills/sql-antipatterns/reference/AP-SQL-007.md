# AP-SQL-007 — OFFSET-based pagination on large result sets

**Category:** performance | **Severity:** warn
**Frameworks:** [plain]

## Summary
Paginating with `OFFSET n` requires the database to scan and discard all preceding rows, becoming progressively slower on later pages. Use keyset (cursor) pagination instead — filter by the last-seen value of an indexed column.

## Do Not Write
```sql
SELECT id, name FROM products ORDER BY id LIMIT 20 OFFSET 10000;
```

## Instead Write
```sql
SELECT id, name FROM products WHERE id > ? ORDER BY id LIMIT 20;
```

