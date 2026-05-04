"""Trade purchase header: commission mode + flat money/rate.

Revision ID: 015_trade_purchase_commission_mode
Revises: 014_broker_deal_defaults
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "015_trade_purchase_commission_mode"
down_revision: Union[str, None] = "014_broker_deal_defaults"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "trade_purchases",
        sa.Column("commission_mode", sa.String(length=24), nullable=True),
    )
    op.add_column(
        "trade_purchases",
        sa.Column("commission_money", sa.Numeric(precision=14, scale=4), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("trade_purchases", "commission_money")
    op.drop_column("trade_purchases", "commission_mode")
