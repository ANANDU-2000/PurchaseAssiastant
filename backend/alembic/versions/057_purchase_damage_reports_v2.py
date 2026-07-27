"""Extend purchase_damage_reports (status, catalog_item_id, reason, photo)

Revision ID: 057_purchase_damage_reports_v2
Revises: 056_purchase_damage_reports
"""

from typing import Union

from alembic import op
import sqlalchemy as sa

revision: str = "057_purchase_damage_reports_v2"
down_revision: Union[str, None] = "056_purchase_damage_reports"
branch_labels = None
depends_on = None


def _has_column(table: str, column: str) -> bool:
    bind = op.get_bind()
    cols = [c["name"] for c in sa.inspect(bind).get_columns(table)]
    return column in cols


def upgrade() -> None:
    if not _has_column("purchase_damage_reports", "status"):
        op.add_column(
            "purchase_damage_reports",
            sa.Column("status", sa.String(length=32), nullable=False, server_default="pending"),
        )
    if not _has_column("purchase_damage_reports", "catalog_item_id"):
        op.add_column(
            "purchase_damage_reports",
            sa.Column("catalog_item_id", sa.Uuid(), nullable=True),
        )
    if not _has_column("purchase_damage_reports", "unit"):
        op.add_column(
            "purchase_damage_reports",
            sa.Column("unit", sa.String(length=32), nullable=True),
        )
    if not _has_column("purchase_damage_reports", "reason"):
        op.add_column(
            "purchase_damage_reports",
            sa.Column("reason", sa.String(length=64), nullable=True),
        )
    if not _has_column("purchase_damage_reports", "photo_url"):
        op.add_column(
            "purchase_damage_reports",
            sa.Column("photo_url", sa.Text(), nullable=True),
        )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_purchase_damage_reports_business_status "
        "ON purchase_damage_reports (business_id, status)"
    )


def downgrade() -> None:
    op.drop_index("ix_purchase_damage_reports_business_status", table_name="purchase_damage_reports")
    for col in ("photo_url", "reason", "unit", "catalog_item_id", "status"):
        if _has_column("purchase_damage_reports", col):
            op.drop_column("purchase_damage_reports", col)
