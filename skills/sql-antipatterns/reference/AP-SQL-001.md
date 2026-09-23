# AP-SQL-001 — SELECT * in application code

**Category:** performance | **Severity:** warn
**Frameworks:** [plain]

## Summary
Using `SELECT *` transfers all columns regardless of which ones the application actually uses, wastes network bandwidth, and breaks application code when columns are added or removed. Always name the columns you need.

## Do Not Write
```sql
SELECT * FROM orders WHERE customer_id = ?;
```

## Instead Write
```sql
SELECT id, total, status, created_at FROM orders WHERE customer_id = ?;
```

