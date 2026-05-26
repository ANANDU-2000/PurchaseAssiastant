BEGIN;

CREATE TABLE IF NOT EXISTS stock_movements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
    movement_kind VARCHAR(50) NOT NULL,
    delta_qty NUMERIC(12,3) NOT NULL,
    qty_before NUMERIC(12,3) NOT NULL,
    qty_after NUMERIC(12,3) NOT NULL,
    stock_unit VARCHAR(32),
    reason VARCHAR(255),
    notes TEXT,
    source_type VARCHAR(50),
    source_id UUID,
    idempotency_key VARCHAR(120) NOT NULL,
    actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
    actor_name VARCHAR(255),
    metadata_json JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_stock_movements_business_idempotency UNIQUE (business_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS ix_stock_movements_business_item_created
    ON stock_movements (business_id, item_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_stock_movements_business_kind_created
    ON stock_movements (business_id, movement_kind, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_stock_movements_source
    ON stock_movements (business_id, source_type, source_id);

ALTER TABLE catalog_items
    ADD COLUMN IF NOT EXISTS stock_version INTEGER NOT NULL DEFAULT 0;

ALTER TABLE staff_purchase_logs
    ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS broker_id UUID REFERENCES brokers(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS broker_name VARCHAR(255),
    ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(120),
    ADD COLUMN IF NOT EXISTS stock_movement_id UUID REFERENCES stock_movements(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ix_staff_purchase_logs_supplier_id
    ON staff_purchase_logs (supplier_id);

CREATE INDEX IF NOT EXISTS ix_staff_purchase_logs_broker_id
    ON staff_purchase_logs (broker_id);

CREATE INDEX IF NOT EXISTS ix_staff_purchase_logs_stock_movement_id
    ON staff_purchase_logs (stock_movement_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_staff_purchase_logs_business_idempotency
    ON staff_purchase_logs (business_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;

COMMIT;
