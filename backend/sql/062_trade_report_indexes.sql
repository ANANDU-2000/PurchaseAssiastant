-- Trade report / stock period query indexes (Postgres).
CREATE INDEX IF NOT EXISTS ix_trade_purchases_biz_date_status
  ON trade_purchases (business_id, purchase_date DESC, status);

CREATE INDEX IF NOT EXISTS ix_trade_purchase_lines_purchase_catalog
  ON trade_purchase_lines (trade_purchase_id, catalog_item_id);

CREATE INDEX IF NOT EXISTS ix_trade_purchase_lines_catalog_item
  ON trade_purchase_lines (catalog_item_id)
  WHERE catalog_item_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_staff_purchase_logs_biz_item_created
  ON staff_purchase_logs (business_id, item_id, created_at DESC);
