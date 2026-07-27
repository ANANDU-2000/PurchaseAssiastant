-- Notification alert v2: priority, category, routes, relations, metadata
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS priority VARCHAR(16) NOT NULL DEFAULT 'medium';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS category VARCHAR(32) NOT NULL DEFAULT 'system';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS action_route VARCHAR(256);
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS triggered_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS related_item_id UUID;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS related_purchase_id UUID;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS related_supplier_id UUID;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS metadata JSONB;

CREATE INDEX IF NOT EXISTS ix_notifications_business_unread
  ON notifications (business_id, user_id, read_at)
  WHERE read_at IS NULL;

CREATE INDEX IF NOT EXISTS ix_notifications_business_category
  ON notifications (business_id, user_id, category, created_at DESC);
