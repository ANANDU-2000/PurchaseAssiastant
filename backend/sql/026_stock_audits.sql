-- Stock audit sessions (distinct from stock_adjustment_log line edits).

CREATE TABLE IF NOT EXISTS stock_audits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  audit_date DATE NOT NULL DEFAULT CURRENT_DATE,
  auditor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'draft',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_stock_audits_auditor_id ON stock_audits (auditor_id);
CREATE INDEX IF NOT EXISTS ix_stock_audits_audit_date ON stock_audits (audit_date DESC);

CREATE TABLE IF NOT EXISTS stock_audit_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  audit_id UUID NOT NULL REFERENCES stock_audits(id) ON DELETE CASCADE,
  item_id UUID NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
  system_qty NUMERIC(10, 2) NOT NULL,
  counted_qty NUMERIC(10, 2) NOT NULL,
  difference_qty NUMERIC(10, 2) NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_stock_audit_items_audit_id ON stock_audit_items (audit_id);
CREATE INDEX IF NOT EXISTS ix_stock_audit_items_item_id ON stock_audit_items (item_id);
