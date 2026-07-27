-- In-app notifications (per user, per business). Optional hourly low-stock job inserts rows here.

CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind VARCHAR(64) NOT NULL DEFAULT 'general',
  title VARCHAR(500) NOT NULL,
  body TEXT,
  payload JSONB,
  read_at TIMESTAMPTZ,
  dedupe_key VARCHAR(220),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON notifications(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_business_created
  ON notifications(business_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_dedupe
  ON notifications(business_id, dedupe_key)
  WHERE dedupe_key IS NOT NULL;
