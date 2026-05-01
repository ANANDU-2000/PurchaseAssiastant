"""Add item_code to trade_purchase_lines.

Revision ID: 005_item_code_tpline
Revises: 004_cloud_exp
"""

from __future__ import annotations

from typing import Union

import sqlalchemy as sa
from alembic import op

revision: str = "005_item_code_tpline"
down_revision: Union[str, None] = "004_cloud_exp"
branch_labels = None
depends_on = None


def _has_column(table: str, column: str) -> bool:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    return any(c["name"] == column for c in insp.get_columns(table))


def upgrade() -> None:
    if not _has_column("trade_purchase_lines", "item_code"):
        op.add_column(
            "trade_purchase_lines",
            sa.Column("item_code", sa.String(length=64), nullable=True),
        )


def downgrade() -> None:
    op.drop_column("trade_purchase_lines", "item_code")
