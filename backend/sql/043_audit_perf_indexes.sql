-- Opening stock setup: pending items by business
CREATE INDEX IF NOT EXISTS ix_catalog_items_opening_pending
  ON catalog_items (business_id)
  WHERE deleted_at IS NULL AND opening_stock_set_at IS NULL;

-- Purchase line lookups by catalog item (reports / item intel)
CREATE INDEX IF NOT EXISTS ix_trade_purchase_lines_catalog_item_id
  ON trade_purchase_lines (catalog_item_id)
  WHERE catalog_item_id IS NOT NULL;
