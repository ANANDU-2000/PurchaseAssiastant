"""Apply SQL 065_api_storm_hotpath_indexes.

Revision ID: 065_api_storm_hotpath_indexes
Revises: 064_pg_report_line_indexes
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "065_api_storm_hotpath_indexes"
down_revision: Union[str, None] = "064_pg_report_line_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "065_api_storm_hotpath_indexes.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_catalog_items_biz_opening_missing;")
    op.execute("DROP INDEX IF EXISTS ix_notifications_biz_user_unread;")
    op.execute("DROP INDEX IF EXISTS ix_catalog_items_biz_stock_list;")
