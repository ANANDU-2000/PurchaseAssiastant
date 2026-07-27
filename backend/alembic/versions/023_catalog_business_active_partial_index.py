"""Partial index for active catalog rows per business (list + compact endpoints).

Revision ID: 023_catalog_business_active_partial
Revises: 022_trade_purchase_list_status_date
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "023_catalog_business_active_partial"
down_revision: Union[str, None] = "022_trade_purchase_list_status_date"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _index_names(bind, table: str) -> set[str]:
    insp = sa.inspect(bind)
    if not insp.has_table(table):
        return set()
    return {i["name"] for i in insp.get_indexes(table)}


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    ix = _index_names(bind, "catalog_items")
    idx = "ix_catalog_items_business_active_lower_name"
    if idx not in ix:
        op.execute(
            sa.text(
                "CREATE INDEX ix_catalog_items_business_active_lower_name "
                "ON catalog_items (business_id, (lower(name))) "
                "WHERE deleted_at IS NULL"
            )
        )


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    ix = _index_names(bind, "catalog_items")
    idx = "ix_catalog_items_business_active_lower_name"
    if idx in ix:
        op.drop_index(idx, table_name="catalog_items")
