"""Owner ops tables: backup_logs, provider_credentials, staff_tasks."""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "069_owner_ops_tables"
down_revision: Union[str, None] = "068_physical_count_idempotency_key"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "backup_logs",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("business_id", sa.Uuid(), sa.ForeignKey("businesses.id"), nullable=False),
        sa.Column("run_type", sa.String(32), nullable=False, server_default="manual"),
        sa.Column("status", sa.String(32), nullable=False, server_default="success"),
        sa.Column("file_path", sa.Text(), nullable=True),
        sa.Column("size_bytes", sa.BigInteger(), nullable=True),
        sa.Column("row_counts", sa.JSON(), nullable=True),
        sa.Column("duration_ms", sa.Integer(), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_backup_logs_business_id", "backup_logs", ["business_id"])
    op.create_index("ix_backup_logs_created_at", "backup_logs", ["created_at"])

    op.create_table(
        "provider_credentials",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("business_id", sa.Uuid(), sa.ForeignKey("businesses.id"), nullable=False),
        sa.Column("credential_type", sa.String(64), nullable=False),
        sa.Column("encrypted_value", sa.Text(), nullable=False),
        sa.Column("last_4_chars", sa.String(8), nullable=False, server_default=""),
        sa.Column("updated_by", sa.Uuid(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("business_id", "credential_type", name="uq_provider_cred_biz_type"),
    )
    op.create_index(
        "ix_provider_credentials_business_id", "provider_credentials", ["business_id"]
    )
    op.create_index(
        "ix_provider_credentials_type", "provider_credentials", ["credential_type"]
    )

    op.create_table(
        "staff_tasks",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("business_id", sa.Uuid(), sa.ForeignKey("businesses.id"), nullable=False),
        sa.Column("staff_id", sa.Uuid(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("task_type", sa.String(64), nullable=False, server_default="general"),
        sa.Column("reference_id", sa.String(128), nullable=True),
        sa.Column("status", sa.String(32), nullable=False, server_default="assigned"),
        sa.Column("rejected", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("correction_note", sa.Text(), nullable=True),
        sa.Column("assigned_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_by", sa.Uuid(), nullable=True),
    )
    op.create_index("ix_staff_tasks_business_id", "staff_tasks", ["business_id"])
    op.create_index("ix_staff_tasks_staff_id", "staff_tasks", ["staff_id"])
    op.create_index("ix_staff_tasks_status", "staff_tasks", ["status"])


def downgrade() -> None:
    op.drop_table("staff_tasks")
    op.drop_table("provider_credentials")
    op.drop_table("backup_logs")
