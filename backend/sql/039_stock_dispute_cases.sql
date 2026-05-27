-- Open stock dispute cases (warehouse mismatch / count disagreements)
CREATE TABLE IF NOT EXISTS stock_dispute_cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
    status VARCHAR(32) NOT NULL DEFAULT 'open',
    reason TEXT,
    notes TEXT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ,
    resolved_by UUID REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS ix_stock_dispute_cases_business_status
    ON stock_dispute_cases (business_id, status);

CREATE INDEX IF NOT EXISTS ix_stock_dispute_cases_item
    ON stock_dispute_cases (business_id, item_id);
