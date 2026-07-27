-- API storm hot-path indexes (Postgres). Safe IF NOT EXISTS.

CREATE INDEX IF NOT EXISTS ix_catalog_items_biz_opening_missing
  ON catalog_items (business_id)
  WHERE deleted_at IS NULL AND opening_stock_set_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_notifications_biz_user_unread
  ON notifications (business_id, user_id, created_at DESC)
  WHERE read_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_catalog_items_biz_stock_list
  ON catalog_items (business_id, name)
  WHERE deleted_at IS NULL;
