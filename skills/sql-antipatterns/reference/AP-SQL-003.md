# AP-SQL-003 — ADD COLUMN NOT NULL without a default on a large live table

**Category:** performance | **Severity:** error
**Frameworks:** [postgresql, mysql]

## Summary
Adding a NOT NULL column without a default on a large table requires rewriting every row while holding an access exclusive lock, causing downtime. The safe migration pattern is: add nullable → backfill → add NOT VALID constraint → validate.

## Do Not Write
```sql
ALTER TABLE orders ADD COLUMN processed BOOLEAN NOT NULL DEFAULT FALSE;
-- rewrites all rows; locks table
```

## Instead Write
```sql
ALTER TABLE orders ADD COLUMN processed BOOLEAN;
UPDATE orders SET processed = FALSE WHERE processed IS NULL;
ALTER TABLE orders ADD CONSTRAINT orders_processed_nn CHECK (processed IS NOT NULL) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT orders_processed_nn;
```

