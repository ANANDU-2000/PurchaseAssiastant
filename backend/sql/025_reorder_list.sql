-- Reorder list: staff flag items for owner to reorder (Harisree v4 POLISH-6).

CREATE TABLE IF NOT EXISTS reorder_list (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES catalog_items(id) ON DELETE CASCADE,
    added_by UUID REFERENCES users(id) ON DELETE SET NULL,
    added_by_name VARCHAR(255),
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_reorder_list_business_item_pending
    ON reorder_list (business_id, item_id)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS ix_reorder_list_business_status
    ON reorder_list (business_id, status, created_at DESC);
