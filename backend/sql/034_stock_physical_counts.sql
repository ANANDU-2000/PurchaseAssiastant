CREATE TABLE IF NOT EXISTS stock_physical_counts (
  id UUID PRIMARY KEY,
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  item_id UUID NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
  system_qty NUMERIC(12,3) NOT NULL,
  counted_qty NUMERIC(12,3) NOT NULL,
  difference_qty NUMERIC(12,3) NOT NULL,
  purchased_qty NUMERIC(12,3) NULL,
  stock_unit VARCHAR(32) NULL,
  period_start DATE NULL,
  period_end DATE NULL,
  notes TEXT NULL,
  counted_by UUID NULL REFERENCES users(id) ON DELETE SET NULL,
  counted_by_name VARCHAR(255) NULL,
  counted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_stock_physical_counts_business_item_counted
  ON stock_physical_counts(business_id, item_id, counted_at DESC);

CREATE INDEX IF NOT EXISTS ix_stock_physical_counts_counted_at
  ON stock_physical_counts(counted_at DESC);

ALTER TABLE stock_physical_counts ENABLE ROW LEVEL SECURITY;

