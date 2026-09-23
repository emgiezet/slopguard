-- ok: slopguard.migration.not-null-without-default
-- Strategy 1: nullable first, backfill, then constraint
ALTER TABLE orders ADD COLUMN processed_at TIMESTAMP;
UPDATE orders SET processed_at = created_at WHERE processed_at IS NULL;
ALTER TABLE orders ALTER COLUMN processed_at SET NOT NULL;

-- ok: slopguard.migration.not-null-without-default
-- Strategy 2: provide a DEFAULT (PostgreSQL 11+ handles constant defaults online)
ALTER TABLE products ADD COLUMN sku VARCHAR(64) NOT NULL DEFAULT '';
