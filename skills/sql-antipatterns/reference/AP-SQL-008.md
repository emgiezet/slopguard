# AP-SQL-008 — UPDATE or DELETE without WHERE clause in migrations or scripts

**Category:** security | **Severity:** blocker
**Frameworks:** [plain]

## Summary
An `UPDATE` or `DELETE` with no `WHERE` clause modifies or removes every row in the table. Always include an explicit condition, and for batch operations use row-limited loops with a delay to avoid long-held locks.

## Do Not Write
```sql
DELETE FROM audit_logs;        -- deletes all rows
UPDATE users SET active = 0;   -- updates all rows
```

## Instead Write
```sql
DELETE FROM audit_logs WHERE created_at < NOW() - INTERVAL 90 DAY LIMIT 1000;
UPDATE users SET active = 0 WHERE last_login < NOW() - INTERVAL 365 DAY;
```

