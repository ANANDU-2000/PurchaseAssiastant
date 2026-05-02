"""Broker deal-default columns (payment, discount, rates, freight).

Revision ID: 014_broker_deal_defaults
Revises: 013_trade_line_indexes
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "014_broker_deal_defaults"
down_revision: Union[str, None] = "013_trade_line_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "brokers",
        sa.Column("default_payment_days", sa.Integer(), nullable=True),
    )
    op.add_column(
        "brokers",
        sa.Column("default_discount", sa.Numeric(5, 2), nullable=True),
    )
    op.add_column(
        "brokers",
        sa.Column("default_delivered_rate", sa.Numeric(12, 2), nullable=True),
    )
    op.add_column(
        "brokers",
        sa.Column("default_billty_rate", sa.Numeric(12, 2), nullable=True),
    )
    op.add_column(
        "brokers",
        sa.Column("freight_type", sa.String(16), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("brokers", "freight_type")
    op.drop_column("brokers", "default_billty_rate")
    op.drop_column("brokers", "default_delivered_rate")
    op.drop_column("brokers", "default_discount")
    op.drop_column("brokers", "default_payment_days")
