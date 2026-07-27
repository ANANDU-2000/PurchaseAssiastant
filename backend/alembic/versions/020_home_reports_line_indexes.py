"""Composite index for trade line reports grouped by item_name.

Revision ID: 020_home_reports_line_indexes
Revises: 019_smart_unit_intelligence
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "020_home_reports_line_indexes"
down_revision: Union[str, None] = "019_smart_unit_intelligence"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _index_names(bind, table: str) -> set[str]:
    insp = sa.inspect(bind)
    if not insp.has_table(table):
        return set()
    return {i["name"] for i in insp.get_indexes(table)}


def upgrade() -> None:
    bind = op.get_bind()
    ix = _index_names(bind, "trade_purchase_lines")
    name = "ix_trade_purchase_lines_tp_id_item_name"
    if name not in ix:
        op.create_index(
            name,
            "trade_purchase_lines",
            ["trade_purchase_id", "item_name"],
            unique=False,
            if_not_exists=True,
        )


def downgrade() -> None:
    bind = op.get_bind()
    ix = _index_names(bind, "trade_purchase_lines")
    if "ix_trade_purchase_lines_tp_id_item_name" in ix:
        op.drop_index(
            "ix_trade_purchase_lines_tp_id_item_name",
            table_name="trade_purchase_lines",
        )
