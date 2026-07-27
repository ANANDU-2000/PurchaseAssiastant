-- Purchase damage / short-delivery reports (staff → owner notify)
CREATE TABLE IF NOT EXISTS purchase_damage_reports (
    id UUID PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    purchase_id UUID NOT NULL REFERENCES trade_purchases(id) ON DELETE CASCADE,
    item_name VARCHAR(500) NOT NULL,
    qty_damaged NUMERIC(18, 4) NOT NULL,
    damage_type VARCHAR(32) NOT NULL,
    notes TEXT,
    reported_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ix_purchase_damage_reports_purchase_id
    ON purchase_damage_reports (purchase_id);
CREATE INDEX IF NOT EXISTS ix_purchase_damage_reports_business_id
    ON purchase_damage_reports (business_id);
