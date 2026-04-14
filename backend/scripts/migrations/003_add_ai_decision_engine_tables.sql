-- AI decision engine tables
-- Safe to run multiple times.

CREATE TABLE IF NOT EXISTS assistant_sessions (
    id UUID PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES businesses(id),
    user_id UUID NOT NULL REFERENCES users(id),
    flow VARCHAR(64),
    state_json JSON,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_assistant_sessions_business ON assistant_sessions (business_id);
CREATE INDEX IF NOT EXISTS idx_assistant_sessions_user ON assistant_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_assistant_sessions_updated ON assistant_sessions (updated_at);

CREATE TABLE IF NOT EXISTS assistant_decisions (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES assistant_sessions(id),
    action VARCHAR(64) NOT NULL,
    payload_json JSON NOT NULL,
    validation_json JSON,
    status VARCHAR(32) NOT NULL DEFAULT 'draft',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_assistant_decisions_session ON assistant_decisions (session_id);
CREATE INDEX IF NOT EXISTS idx_assistant_decisions_action ON assistant_decisions (action);
CREATE INDEX IF NOT EXISTS idx_assistant_decisions_status ON assistant_decisions (status);

CREATE TABLE IF NOT EXISTS catalog_aliases (
    id UUID PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES businesses(id),
    alias_type VARCHAR(16) NOT NULL,
    ref_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    normalized_name VARCHAR(255) NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_catalog_aliases_business ON catalog_aliases (business_id);
CREATE INDEX IF NOT EXISTS idx_catalog_aliases_type ON catalog_aliases (alias_type);
CREATE INDEX IF NOT EXISTS idx_catalog_aliases_norm ON catalog_aliases (normalized_name);
CREATE INDEX IF NOT EXISTS idx_catalog_aliases_ref ON catalog_aliases (ref_id);
