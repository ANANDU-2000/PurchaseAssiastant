-- Harisree v4: catalog stock columns + per-item adjustment log (distinct from stock_audits sessions).

ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS current_stock NUMERIC(12, 3) DEFAULT 0;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS reorder_level NUMERIC(12, 3) DEFAULT 0;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS rack_location VARCHAR(100);
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS last_stock_updated_at TIMESTAMPTZ;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS last_stock_updated_by VARCHAR(255);

CREATE TABLE IF NOT EXISTS stock_adjustment_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  item_id UUID NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
  old_qty NUMERIC(12, 3) NOT NULL DEFAULT 0,
  new_qty NUMERIC(12, 3) NOT NULL DEFAULT 0,
  adjustment_type VARCHAR(50) NOT NULL
    CHECK (adjustment_type IN ('purchase','manual','damaged','expired','correction','verification')),
  reason TEXT,
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  updated_by_name VARCHAR(255),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stock_adj_item_id ON stock_adjustment_log(item_id);
CREATE INDEX IF NOT EXISTS idx_stock_adj_updated_at ON stock_adjustment_log(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_adj_updated_by ON stock_adjustment_log(updated_by);
CREATE INDEX IF NOT EXISTS idx_stock_adj_business ON stock_adjustment_log(business_id, updated_at DESC);
