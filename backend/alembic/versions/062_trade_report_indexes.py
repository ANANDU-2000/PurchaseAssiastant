"""Trade report and purchased-in-period query indexes.

Revision ID: 062_trade_report_indexes
Revises: 061_catalog_unit_simplify
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "062_trade_report_indexes"
down_revision: Union[str, None] = "061_catalog_unit_simplify"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "062_trade_report_indexes.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_staff_purchase_logs_biz_item_created;")
    op.execute("DROP INDEX IF EXISTS ix_trade_purchase_lines_catalog_item;")
    op.execute("DROP INDEX IF EXISTS ix_trade_purchase_lines_purchase_catalog;")
    op.execute("DROP INDEX IF EXISTS ix_trade_purchases_biz_date_status;")
