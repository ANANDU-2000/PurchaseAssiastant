-- Add idempotency_key to stock_physical_counts for cold-start write deduplication.

DO $$
BEGIN
  IF to_regclass('public.stock_physical_counts') IS NOT NULL THEN
    ALTER TABLE stock_physical_counts
      ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(120);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_physical_count_idempotency
  ON stock_physical_counts (business_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
