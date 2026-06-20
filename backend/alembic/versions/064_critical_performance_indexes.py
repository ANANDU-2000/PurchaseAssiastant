"""Critical performance indexes for low-stock and purchase hot paths.

Revision ID: 064_critical_performance_indexes
Revises: 063_pg_hot_path_indexes
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "064_critical_performance_indexes"
down_revision: Union[str, None] = "063_pg_hot_path_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "064_critical_performance_indexes.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_stock_movements_item_created_desc;")
    op.execute("DROP INDEX IF EXISTS ix_staff_activity_user_biz_action_time;")
    op.execute("DROP INDEX IF EXISTS ix_trade_purchases_biz_delivery_open;")
    op.execute("DROP INDEX IF EXISTS ix_trade_purchases_biz_status_date;")
    op.execute("DROP INDEX IF EXISTS ix_catalog_items_low_stock_filter;")
