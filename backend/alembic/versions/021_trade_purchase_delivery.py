"""Warehouse delivery tracking on trade_purchases.

Revision ID: 021_trade_purchase_delivery
Revises: 020_home_reports_line_indexes
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "021_trade_purchase_delivery"
down_revision: Union[str, None] = "020_home_reports_line_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_column(table: str, column: str) -> bool:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    return any(c["name"] == column for c in insp.get_columns(table))


def upgrade() -> None:
    if not _has_column("trade_purchases", "is_delivered"):
        op.add_column(
            "trade_purchases",
            sa.Column("is_delivered", sa.Boolean(), nullable=False, server_default="false"),
        )
    if not _has_column("trade_purchases", "delivered_at"):
        op.add_column(
            "trade_purchases",
            sa.Column("delivered_at", sa.DateTime(timezone=True), nullable=True),
        )
    if not _has_column("trade_purchases", "delivery_notes"):
        op.add_column("trade_purchases", sa.Column("delivery_notes", sa.Text(), nullable=True))
    bind = op.get_bind()
    # SQLite cannot reliably ALTER COLUMN ... DROP DEFAULT across versions.
    if bind.dialect.name != "sqlite":
        op.alter_column("trade_purchases", "is_delivered", server_default=None)


def downgrade() -> None:
    op.drop_column("trade_purchases", "delivery_notes")
    op.drop_column("trade_purchases", "delivered_at")
    op.drop_column("trade_purchases", "is_delivered")
