-- Run once on Render Postgres (harisree-db) when pre-deploy alembic is unavailable.
-- Then: UPDATE alembic_version SET version_num = '059_staff_activity_action_types_v2';

-- 057_purchase_damage_reports_v2
ALTER TABLE purchase_damage_reports ADD COLUMN IF NOT EXISTS status VARCHAR(32) NOT NULL DEFAULT 'pending';
ALTER TABLE purchase_damage_reports ADD COLUMN IF NOT EXISTS catalog_item_id UUID;
ALTER TABLE purchase_damage_reports ADD COLUMN IF NOT EXISTS unit VARCHAR(32);
ALTER TABLE purchase_damage_reports ADD COLUMN IF NOT EXISTS reason VARCHAR(64);
ALTER TABLE purchase_damage_reports ADD COLUMN IF NOT EXISTS photo_url TEXT;
CREATE INDEX IF NOT EXISTS ix_purchase_damage_reports_business_status ON purchase_damage_reports (business_id, status);

-- 058_barcode_lookup_indexes
CREATE INDEX IF NOT EXISTS idx_catalog_items_business_item_code
  ON catalog_items (business_id, item_code)
  WHERE deleted_at IS NULL AND item_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_catalog_items_business_barcode_lookup
  ON catalog_items (business_id, barcode)
  WHERE deleted_at IS NULL AND barcode IS NOT NULL;

-- 059_staff_activity_action_types_v2
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'staff_activity_log_action_type_check'
  ) THEN
    ALTER TABLE staff_activity_log DROP CONSTRAINT staff_activity_log_action_type_check;
  END IF;
EXCEPTION WHEN undefined_table THEN
  NULL;
END $$;

ALTER TABLE staff_activity_log ADD CONSTRAINT staff_activity_log_action_type_check
  CHECK (action_type IN (
    'SCAN', 'STOCK_UPDATE', 'STOCK_PHYSICAL_UPDATE', 'STOCK_CORRECTION_RECORDED',
    'STOCK_DAMAGE_RECORDED', 'STOCK_SALE_ADJUSTMENT', 'STOCK_QUICK_PURCHASE',
    'OPENING_STOCK_SET', 'PHYSICAL_STOCK_COUNT', 'ITEM_CREATE', 'ITEM_UPDATE',
    'PURCHASE_SAVE', 'PURCHASE_EDIT', 'PURCHASE_CREATE', 'PURCHASE_DISPATCHED',
    'PURCHASE_ARRIVED', 'PURCHASE_VERIFIED', 'PURCHASE_STOCK_COMMITTED',
    'PURCHASE_WHATSAPP_SENT', 'PURCHASE_WHATSAPP_FAILED', 'VERIFICATION', 'LOGIN',
    'LOGOUT', 'PASSWORD_RESET', 'USER_CREATE', 'USER_BLOCK', 'USER_DELETE',
    'BARCODE_PRINT', 'BARCODE_COUNT_VERIFY', 'REPORT_EXPORT', 'DELETE_ACTION',
    'CHECKLIST_COMPLETE', 'USAGE_LOG', 'STOCK_AUDIT_LINE', 'STOCK_AUDIT_COMPLETE'
  ));

UPDATE alembic_version SET version_num = '059_staff_activity_action_types_v2';
