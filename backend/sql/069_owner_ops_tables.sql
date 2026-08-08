-- Owner ops: backup_logs, provider_credentials, staff_tasks
CREATE TABLE IF NOT EXISTS backup_logs (
    id UUID PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES businesses(id),
    run_type VARCHAR(32) NOT NULL DEFAULT 'manual',
    status VARCHAR(32) NOT NULL DEFAULT 'success',
    file_path TEXT,
    size_bytes BIGINT,
    row_counts JSON,
    duration_ms INTEGER,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_backup_logs_business_id ON backup_logs(business_id);
CREATE INDEX IF NOT EXISTS ix_backup_logs_created_at ON backup_logs(created_at);

CREATE TABLE IF NOT EXISTS provider_credentials (
    id UUID PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES businesses(id),
    credential_type VARCHAR(64) NOT NULL,
    encrypted_value TEXT NOT NULL,
    last_4_chars VARCHAR(8) NOT NULL DEFAULT '',
    updated_by UUID,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (business_id, credential_type)
);
CREATE INDEX IF NOT EXISTS ix_provider_credentials_business_id ON provider_credentials(business_id);
CREATE INDEX IF NOT EXISTS ix_provider_credentials_type ON provider_credentials(credential_type);

CREATE TABLE IF NOT EXISTS staff_tasks (
    id UUID PRIMARY KEY,
    business_id UUID NOT NULL REFERENCES businesses(id),
    staff_id UUID NOT NULL REFERENCES users(id),
    task_type VARCHAR(64) NOT NULL DEFAULT 'general',
    reference_id VARCHAR(128),
    status VARCHAR(32) NOT NULL DEFAULT 'assigned',
    rejected BOOLEAN NOT NULL DEFAULT FALSE,
    correction_note TEXT,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    accepted_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_by UUID
);
CREATE INDEX IF NOT EXISTS ix_staff_tasks_business_id ON staff_tasks(business_id);
CREATE INDEX IF NOT EXISTS ix_staff_tasks_staff_id ON staff_tasks(staff_id);
CREATE INDEX IF NOT EXISTS ix_staff_tasks_status ON staff_tasks(status);
