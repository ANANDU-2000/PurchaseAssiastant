"""Stock list and low-stock performance indexes.

Revision ID: 060_stock_list_performance_indexes
Revises: 059_staff_activity_action_types_v2
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "060_stock_list_performance_indexes"
down_revision: Union[str, None] = "059_staff_activity_action_types_v2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "060_stock_list_performance_indexes.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_stock_movements_biz_item_created;")
    op.execute("DROP INDEX IF EXISTS ix_trade_purchases_biz_delivery_status;")
    op.execute("DROP INDEX IF EXISTS ix_catalog_items_biz_low_stock;")
    op.execute("DROP INDEX IF EXISTS ix_catalog_items_biz_active_updated_desc;")
