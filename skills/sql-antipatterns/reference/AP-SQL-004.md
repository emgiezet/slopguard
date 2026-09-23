# AP-SQL-004 — Foreign key column without an index

**Category:** performance | **Severity:** warn
**Frameworks:** [plain]

## Summary
A foreign key column without an index makes every JOIN and cascade DELETE that scans the referencing table a full sequential scan, which becomes catastrophic at scale. Add a covering index on every foreign key column at creation time.

## Do Not Write
```sql
ALTER TABLE order_items ADD COLUMN order_id BIGINT REFERENCES orders(id);
-- no index on order_id
```

## Instead Write
```sql
ALTER TABLE order_items ADD COLUMN order_id BIGINT REFERENCES orders(id);
CREATE INDEX CONCURRENTLY idx_order_items_order_id ON order_items (order_id);
```

## Detection
- opengrep: `slopguard.laravel.migration-fk-without-index`

