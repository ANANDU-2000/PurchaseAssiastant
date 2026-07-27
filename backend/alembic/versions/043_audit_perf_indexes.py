"""Audit remediation: opening pending + purchase line FK indexes.

Revision ID: 043_audit_perf_indexes
Revises: 042_catalog_stock_list_sort_index
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "043_audit_perf_indexes"
down_revision: Union[str, None] = "042_catalog_stock_list_sort_index"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "043_audit_perf_indexes.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_trade_purchase_lines_catalog_item_id;")
    op.execute("DROP INDEX IF EXISTS ix_catalog_items_opening_pending;")
