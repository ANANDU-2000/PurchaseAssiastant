"""Apply SQL 064_pg_report_line_indexes.

Revision ID: 064_pg_report_line_indexes
Revises: 063_pg_hot_path_indexes
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "064_pg_report_line_indexes"
down_revision: Union[str, None] = "063_pg_hot_path_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "064_pg_report_line_indexes.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_catalog_items_biz_active;")
    op.execute("DROP INDEX IF EXISTS ix_trade_purchase_lines_purchase_id;")
    op.execute("DROP INDEX IF EXISTS ix_trade_purchases_biz_purchase_date;")
