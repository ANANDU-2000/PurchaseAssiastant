-- Stock list, low stock, delivery, and movement feed performance indexes.

CREATE INDEX IF NOT EXISTS ix_catalog_items_biz_active_updated_desc
  ON catalog_items (business_id, deleted_at, last_stock_updated_at DESC NULLS LAST)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_catalog_items_biz_low_stock
  ON catalog_items (business_id, current_stock, reorder_level)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_trade_purchases_biz_delivery_status
  ON trade_purchases (business_id, delivery_status, updated_at DESC)
  WHERE status NOT IN ('deleted', 'cancelled');

CREATE INDEX IF NOT EXISTS ix_stock_movements_biz_item_created
  ON stock_movements (business_id, item_id, created_at DESC);
