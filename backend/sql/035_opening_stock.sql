ALTER TABLE catalog_items
  ADD COLUMN IF NOT EXISTS opening_stock_qty NUMERIC(12,3),
  ADD COLUMN IF NOT EXISTS opening_stock_set_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS opening_stock_set_by VARCHAR(255),
  ADD COLUMN IF NOT EXISTS opening_stock_locked BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS ix_catalog_items_opening_missing
  ON catalog_items(business_id, opening_stock_set_at)
  WHERE deleted_at IS NULL;

