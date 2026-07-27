CREATE TABLE IF NOT EXISTS staff_purchase_logs (
  id UUID PRIMARY KEY,
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  item_id UUID NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
  item_name VARCHAR(512) NOT NULL,
  qty NUMERIC(12,3) NOT NULL,
  unit VARCHAR(32) NULL,
  amount NUMERIC(12,2) NULL,
  supplier_name VARCHAR(255) NULL,
  notes TEXT NULL,
  created_by UUID NULL REFERENCES users(id) ON DELETE SET NULL,
  created_by_name VARCHAR(255) NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_staff_purchase_logs_business_created
  ON staff_purchase_logs(business_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_staff_purchase_logs_item_created
  ON staff_purchase_logs(item_id, created_at DESC);

ALTER TABLE staff_purchase_logs ENABLE ROW LEVEL SECURITY;

