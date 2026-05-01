"""Add external payment metadata to cloud_payment_history.

Revision ID: 006_cloud_pay_meta
Revises: 005_item_code_tpline
"""

from __future__ import annotations

from typing import Union

import sqlalchemy as sa
from alembic import op

revision: str = "006_cloud_pay_meta"
down_revision: Union[str, None] = "005_item_code_tpline"
branch_labels = None
depends_on = None


def _has_column(table: str, column: str) -> bool:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    return any(c["name"] == column for c in insp.get_columns(table))


def upgrade() -> None:
    if not _has_column("cloud_payment_history", "external_payment_id"):
        op.add_column(
            "cloud_payment_history",
            sa.Column("external_payment_id", sa.String(length=256), nullable=True),
        )
    if not _has_column("cloud_payment_history", "payment_provider"):
        op.add_column(
            "cloud_payment_history",
            sa.Column("payment_provider", sa.String(length=64), nullable=True),
        )


def downgrade() -> None:
    op.drop_column("cloud_payment_history", "payment_provider")
    op.drop_column("cloud_payment_history", "external_payment_id")
