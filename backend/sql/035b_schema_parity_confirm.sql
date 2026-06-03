-- Schema parity confirm (idempotent). MCP audit 2026-05-24: 0 missing model columns.
-- Safe to re-run; ensures Master Fix v3 + StockEase ops columns exist.

-- 034_master_fix_v3_prod_parity
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS current_stock NUMERIC(12, 3) DEFAULT 0;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS reorder_level NUMERIC(12, 3) DEFAULT 0;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS rack_location VARCHAR(100);
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS last_stock_updated_at TIMESTAMPTZ;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS last_stock_updated_by VARCHAR(255);
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS barcode VARCHAR(64);

ALTER TABLE trade_purchases ADD COLUMN IF NOT EXISTS is_delivered BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS qty_in_stock_unit NUMERIC(12, 3);

-- 029_stockease_operations (columns; tables created in earlier migrations)
ALTER TABLE item_categories
  ADD COLUMN IF NOT EXISTS is_perishable BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE catalog_items
  ADD COLUMN IF NOT EXISTS eviction_days INTEGER,
  ADD COLUMN IF NOT EXISTS last_purchase_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS created_by_user_id UUID,
  ADD COLUMN IF NOT EXISTS updated_by_user_id UUID;

-- User/membership v2 fields
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE memberships ADD COLUMN IF NOT EXISTS permissions_json JSONB;

-- Stock audit extras
ALTER TABLE stock_audits ADD COLUMN IF NOT EXISTS business_id UUID;
ALTER TABLE stock_audit_items ADD COLUMN IF NOT EXISTS line_status VARCHAR(32);
ALTER TABLE stock_audit_items ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE stock_audit_items ADD COLUMN IF NOT EXISTS adjustment_type VARCHAR(32);
ALTER TABLE stock_audit_items ADD COLUMN IF NOT EXISTS reason TEXT;

ALTER TABLE trade_purchase_lines ADD COLUMN IF NOT EXISTS tax_mode VARCHAR(16);
