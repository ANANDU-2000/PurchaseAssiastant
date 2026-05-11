"""Add purchase scan trace audit table.

Revision ID: 018_purchase_scan_traces
Revises: 017_broker_image_url
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "018_purchase_scan_traces"
down_revision: Union[str, None] = "017_broker_image_url"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "purchase_scan_traces",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("business_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=True),
        sa.Column("scan_token", sa.String(length=64), nullable=True),
        sa.Column("provider", sa.String(length=64), nullable=True),
        sa.Column("model", sa.String(length=128), nullable=True),
        sa.Column("stage", sa.String(length=32), nullable=False, server_default="preview"),
        sa.Column("raw_response_json", sa.JSON(), nullable=True),
        sa.Column("normalized_response_json", sa.JSON(), nullable=True),
        sa.Column("warnings_json", sa.JSON(), nullable=True),
        sa.Column("meta_json", sa.JSON(), nullable=True),
        sa.Column("image_bytes_in", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("ocr_chars", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_purchase_scan_traces_business_id"),
        "purchase_scan_traces",
        ["business_id"],
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_purchase_scan_traces_user_id"),
        "purchase_scan_traces",
        ["user_id"],
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_purchase_scan_traces_scan_token"),
        "purchase_scan_traces",
        ["scan_token"],
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_purchase_scan_traces_provider"),
        "purchase_scan_traces",
        ["provider"],
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_purchase_scan_traces_stage"),
        "purchase_scan_traces",
        ["stage"],
        if_not_exists=True,
    )
    op.create_index(
        op.f("ix_purchase_scan_traces_created_at"),
        "purchase_scan_traces",
        ["created_at"],
        if_not_exists=True,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_purchase_scan_traces_created_at"), table_name="purchase_scan_traces")
    op.drop_index(op.f("ix_purchase_scan_traces_stage"), table_name="purchase_scan_traces")
    op.drop_index(op.f("ix_purchase_scan_traces_provider"), table_name="purchase_scan_traces")
    op.drop_index(op.f("ix_purchase_scan_traces_scan_token"), table_name="purchase_scan_traces")
    op.drop_index(op.f("ix_purchase_scan_traces_user_id"), table_name="purchase_scan_traces")
    op.drop_index(op.f("ix_purchase_scan_traces_business_id"), table_name="purchase_scan_traces")
    op.drop_table("purchase_scan_traces")
