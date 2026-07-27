-- Stock list ORDER BY last_stock_updated_at DESC (active rows per business).
CREATE INDEX IF NOT EXISTS ix_catalog_items_business_active_updated
  ON catalog_items (business_id, last_stock_updated_at DESC)
  WHERE deleted_at IS NULL;
