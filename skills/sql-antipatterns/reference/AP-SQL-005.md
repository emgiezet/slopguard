# AP-SQL-005 — Changing a column type in place on a live table

**Category:** performance | **Severity:** error
**Frameworks:** [postgresql, mysql]

## Summary
An `ALTER COLUMN TYPE` that changes the storage representation requires a full table rewrite while holding an exclusive lock, causing downtime. Instead, add a new column with the target type, migrate the data, swap the application to the new column, then drop the old one.

## Do Not Write
```sql
ALTER TABLE users ALTER COLUMN phone TYPE VARCHAR(20);
```

## Instead Write
```sql
ALTER TABLE users ADD COLUMN phone_v2 VARCHAR(20);
UPDATE users SET phone_v2 = phone::VARCHAR(20);
-- application switch → then: ALTER TABLE users DROP COLUMN phone;
```

