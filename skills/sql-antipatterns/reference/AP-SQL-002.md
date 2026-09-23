# AP-SQL-002 — CREATE INDEX without CONCURRENTLY on a live PostgreSQL table

**Category:** performance | **Severity:** error
**Frameworks:** [postgresql]

## Summary
A regular `CREATE INDEX` in PostgreSQL acquires a full table lock for the duration of the build, blocking all reads and writes. Use `CREATE INDEX CONCURRENTLY` to build the index without a long-held lock. Run it outside a transaction block.

## Do Not Write
```sql
CREATE INDEX idx_orders_email ON orders (email);
```

## Instead Write
```sql
CREATE INDEX CONCURRENTLY idx_orders_email ON orders (email);
```

