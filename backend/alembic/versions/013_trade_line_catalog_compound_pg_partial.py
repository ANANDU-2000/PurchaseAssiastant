"""Compound line lookup index + Postgres partial index for reports list scope.

Revision ID: 013_trade_line_indexes
Revises: 012_trade_dashboard_indexes
Create Date: 2026-05-01

"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "013_trade_line_indexes"
down_revision: Union[str, None] = "012_trade_dashboard_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _index_names(bind, table: str) -> set[str]:
    insp = sa.inspect(bind)
    return {i["name"] for i in insp.get_indexes(table)}


def upgrade() -> None:
    bind = op.get_bind()
    ix_lines = _index_names(bind, "trade_purchase_lines")
    if "ix_tpl_catalog_item_trade_purchase" not in ix_lines:
        op.create_index(
            "ix_tpl_catalog_item_trade_purchase",
            "trade_purchase_lines",
            ["catalog_item_id", "trade_purchase_id"],
            unique=False,
        )
    if bind.dialect.name == "postgresql":
        ix_pur = _index_names(bind, "trade_purchases")
        idx_name = "ix_trade_purchases_business_date_reports_live"
        if idx_name not in ix_pur:
            op.execute(
                sa.text(
                    "CREATE INDEX ix_trade_purchases_business_date_reports_live "
                    "ON trade_purchases (business_id, purchase_date DESC NULLS LAST) "
                    "WHERE status NOT IN ('deleted', 'cancelled')"
                )
            )


def downgrade() -> None:
    bind = op.get_bind()
    ix_lines = _index_names(bind, "trade_purchase_lines")
    if "ix_tpl_catalog_item_trade_purchase" in ix_lines:
        op.drop_index("ix_tpl_catalog_item_trade_purchase", table_name="trade_purchase_lines")
    if bind.dialect.name == "postgresql":
        ix_pur = _index_names(bind, "trade_purchases")
        idx_name = "ix_trade_purchases_business_date_reports_live"
        if idx_name in ix_pur:
            op.execute(
                sa.text("DROP INDEX IF EXISTS ix_trade_purchases_business_date_reports_live")
            )
