"""Indexes for dashboard/report date scans and trade line unit rolls.

Revision ID: 012_trade_dashboard_indexes
Revises: 011_tp_line_unit_type
Create Date: 2026-05-01
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op


revision: str = "012_trade_dashboard_indexes"
down_revision: Union[str, None] = "011_tp_line_unit_type"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _index_names(bind, table: str) -> set[str]:
    insp = sa.inspect(bind)
    return {i["name"] for i in insp.get_indexes(table)}


def upgrade() -> None:
    bind = op.get_bind()
    ix_pur = _index_names(bind, "trade_purchases")
    if "ix_trade_purchases_business_id_purchase_date" not in ix_pur:
        op.create_index(
            "ix_trade_purchases_business_id_purchase_date",
            "trade_purchases",
            ["business_id", "purchase_date"],
            unique=False,
        )
    ix_lines = _index_names(bind, "trade_purchase_lines")
    if "ix_trade_purchase_lines_unit_type" not in ix_lines:
        op.create_index(
            "ix_trade_purchase_lines_unit_type",
            "trade_purchase_lines",
            ["unit_type"],
            unique=False,
        )


def downgrade() -> None:
    bind = op.get_bind()
    ix_pur = _index_names(bind, "trade_purchases")
    if "ix_trade_purchases_business_id_purchase_date" in ix_pur:
        op.drop_index(
            "ix_trade_purchases_business_id_purchase_date",
            table_name="trade_purchases",
        )
    ix_lines = _index_names(bind, "trade_purchase_lines")
    if "ix_trade_purchase_lines_unit_type" in ix_lines:
        op.drop_index(
            "ix_trade_purchase_lines_unit_type",
            table_name="trade_purchase_lines",
        )
