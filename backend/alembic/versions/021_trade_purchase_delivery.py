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


def upgrade() -> None:
    op.add_column(
        "trade_purchases",
        sa.Column("is_delivered", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column("trade_purchases", sa.Column("delivered_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("trade_purchases", sa.Column("delivery_notes", sa.Text(), nullable=True))
    op.alter_column("trade_purchases", "is_delivered", server_default=None)


def downgrade() -> None:
    op.drop_column("trade_purchases", "delivery_notes")
    op.drop_column("trade_purchases", "delivered_at")
    op.drop_column("trade_purchases", "is_delivered")
