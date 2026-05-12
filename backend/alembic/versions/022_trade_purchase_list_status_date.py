"""Composite index for purchase history list filters (business + status + date).

Revision ID: 022_trade_purchase_list_status_date
Revises: 021_trade_purchase_delivery
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "022_trade_purchase_list_status_date"
down_revision: Union[str, None] = "021_trade_purchase_delivery"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _index_names(bind, table: str) -> set[str]:
    insp = sa.inspect(bind)
    if not insp.has_table(table):
        return set()
    return {i["name"] for i in insp.get_indexes(table)}


def upgrade() -> None:
    bind = op.get_bind()
    ix = _index_names(bind, "trade_purchases")
    name = "ix_trade_purchases_business_status_purchase_date"
    if name not in ix:
        op.create_index(
            name,
            "trade_purchases",
            ["business_id", "status", "purchase_date"],
            unique=False,
            if_not_exists=True,
        )


def downgrade() -> None:
    bind = op.get_bind()
    ix = _index_names(bind, "trade_purchases")
    if "ix_trade_purchases_business_status_purchase_date" in ix:
        op.drop_index(
            "ix_trade_purchases_business_status_purchase_date",
            table_name="trade_purchases",
        )
