-- Extend purchase_damage_reports for item link, reason, status workflow, photo
ALTER TABLE purchase_damage_reports ADD COLUMN IF NOT EXISTS catalog_item_id UUID NULL;
ALTER TABLE purchase_damage_reports ADD COLUMN IF NOT EXISTS unit VARCHAR(32) NULL;
ALTER TABLE purchase_damage_reports ADD COLUMN IF NOT EXISTS reason VARCHAR(64) NULL;
ALTER TABLE purchase_damage_reports ADD COLUMN IF NOT EXISTS status VARCHAR(32) NOT NULL DEFAULT 'pending';
ALTER TABLE purchase_damage_reports ADD COLUMN IF NOT EXISTS photo_url TEXT NULL;

CREATE INDEX IF NOT EXISTS ix_purchase_damage_reports_business_status
    ON purchase_damage_reports (business_id, status);
