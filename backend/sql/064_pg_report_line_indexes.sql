-- Report line aggregation hot-path indexes (Postgres). Safe IF NOT EXISTS.

CREATE INDEX IF NOT EXISTS ix_catalog_items_biz_active
  ON catalog_items (business_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_trade_purchase_lines_purchase_id
  ON trade_purchase_lines (trade_purchase_id);

CREATE INDEX IF NOT EXISTS ix_trade_purchases_biz_purchase_date
  ON trade_purchases (business_id, purchase_date DESC)
  WHERE status NOT IN ('deleted', 'cancelled');
