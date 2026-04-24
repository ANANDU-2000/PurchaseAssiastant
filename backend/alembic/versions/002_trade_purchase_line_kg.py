"""Add kg_per_unit, landing_cost_per_kg to trade_purchase_lines

Revision ID: 002_line_kg
Revises: 001_trade_purchase_core
Create Date: 2026-04-23
"""

from typing import Union

from alembic import op
import sqlalchemy as sa

revision: str = "002_line_kg"
down_revision: Union[str, None] = "001_trade_purchase_core"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("trade_purchase_lines", sa.Column("kg_per_unit", sa.Numeric(18, 4), nullable=True))
    op.add_column(
        "trade_purchase_lines", sa.Column("landing_cost_per_kg", sa.Numeric(18, 4), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("trade_purchase_lines", "landing_cost_per_kg")
    op.drop_column("trade_purchase_lines", "kg_per_unit")
