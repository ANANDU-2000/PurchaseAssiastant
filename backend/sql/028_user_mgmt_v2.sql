-- User management v2: block flag, admin role, expanded activity types

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_staff_activity_business_user
  ON staff_activity_log (business_id, user_id, created_at DESC);

-- Allow admin membership role (drop/recreate check if present)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'memberships_role_check'
  ) THEN
    ALTER TABLE memberships DROP CONSTRAINT memberships_role_check;
  END IF;
EXCEPTION WHEN undefined_table THEN
  NULL;
END $$;

ALTER TABLE memberships ADD CONSTRAINT memberships_role_check
  CHECK (role IN ('owner', 'admin', 'manager', 'staff'));

-- Expand staff activity action types
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
    'SCAN', 'STOCK_UPDATE', 'ITEM_CREATE', 'ITEM_UPDATE', 'PURCHASE_SAVE',
    'PURCHASE_EDIT', 'VERIFICATION', 'LOGIN', 'LOGOUT', 'PASSWORD_RESET',
    'USER_CREATE', 'USER_BLOCK', 'USER_DELETE', 'BARCODE_PRINT', 'REPORT_EXPORT',
    'DELETE_ACTION'
  ));
