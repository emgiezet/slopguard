# AP-SQL-006 — MySQL ALTER on a large table without online DDL

**Category:** performance | **Severity:** warn
**Frameworks:** [mysql]

## Summary
A naive `ALTER TABLE` in MySQL copies the entire table, locking it for writes for the duration. Use `ALGORITHM=INPLACE, LOCK=NONE` for schema changes that support it, or use gh-ost / pt-online-schema-change for changes that don't.

## Do Not Write
```sql
ALTER TABLE products ADD COLUMN sku VARCHAR(64);
```

## Instead Write
```sql
ALTER TABLE products ADD COLUMN sku VARCHAR(64), ALGORITHM=INPLACE, LOCK=NONE;
```

