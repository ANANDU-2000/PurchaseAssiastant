-- Suggested indexes for trade report / catalog insight queries (Postgres).
-- Run manually after EXPLAIN ANALYZE on production-shaped data; use CONCURRENTLY on live DBs.
--
-- Typical filters: trade_purchases(business_id, purchase_date, status) + join trade_purchase_lines.

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_trade_purchases_biz_date_status
--   ON trade_purchases (business_id, purchase_date DESC, status);

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_trade_purchase_lines_purchase_catalog
--   ON trade_purchase_lines (trade_purchase_id, catalog_item_id);

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_trade_purchase_lines_catalog_item
--   ON trade_purchase_lines (catalog_item_id)
--   WHERE catalog_item_id IS NOT NULL;
