-- ruleid: slopguard.migration.not-null-without-default
ALTER TABLE orders ADD COLUMN processed_at TIMESTAMP NOT NULL;

-- ruleid: slopguard.migration.not-null-without-default
ALTER TABLE products ADD COLUMN sku VARCHAR(64) NOT NULL;

-- This locks the table for the full duration of backfill on large tables.
