-- StockEase operations: perishable/eviction, daily usage, staff checklist

ALTER TABLE item_categories
  ADD COLUMN IF NOT EXISTS is_perishable BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE catalog_items
  ADD COLUMN IF NOT EXISTS eviction_days INTEGER,
  ADD COLUMN IF NOT EXISTS last_purchase_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS daily_usage_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  item_id UUID NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
  usage_date DATE NOT NULL,
  opening_qty NUMERIC(12, 3) NOT NULL DEFAULT 0,
  purchased_qty NUMERIC(12, 3) NOT NULL DEFAULT 0,
  used_qty NUMERIC(12, 3) NOT NULL DEFAULT 0,
  closing_qty NUMERIC(12, 3) NOT NULL DEFAULT 0,
  logged_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (business_id, item_id, usage_date)
);

CREATE INDEX IF NOT EXISTS ix_daily_usage_logs_business_date
  ON daily_usage_logs (business_id, usage_date);

CREATE TABLE IF NOT EXISTS staff_checklist_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID REFERENCES businesses(id) ON DELETE CASCADE,
  slot VARCHAR(16) NOT NULL,
  task_key VARCHAR(64) NOT NULL,
  label VARCHAR(255) NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  UNIQUE (business_id, slot, task_key)
);

CREATE TABLE IF NOT EXISTS staff_checklist_completions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  checklist_date DATE NOT NULL,
  slot VARCHAR(16) NOT NULL,
  task_key VARCHAR(64) NOT NULL,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes TEXT,
  UNIQUE (business_id, user_id, checklist_date, slot, task_key)
);

CREATE INDEX IF NOT EXISTS ix_staff_checklist_completions_biz_date
  ON staff_checklist_completions (business_id, checklist_date);
