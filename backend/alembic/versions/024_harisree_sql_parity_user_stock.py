"""Harisree SQL parity: user management, stock columns, notifications, tax_mode, reorder_list.

Revision ID: 024_harisree_sql_parity
Revises: 023_catalog_business_active_partial
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "024_harisree_sql_parity"
down_revision: Union[str, None] = "023_catalog_business_active_partial"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL_DIR = Path(__file__).resolve().parents[2] / "sql"
_SQL_FILES = (
    "supabase_019_smart_unit_intelligence.sql",
    "021_stock_inventory.sql",
    "022_user_management.sql",
    "023_notifications.sql",
    "024_trade_line_tax_mode.sql",
    "025_reorder_list.sql",
    "026_stock_audits.sql",
    "supabase_020_ocr_learning.sql",
)


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    for name in _SQL_FILES:
        path = _SQL_DIR / name
        if not path.is_file():
            continue
        sql = path.read_text(encoding="utf-8")
        if name == "022_user_management.sql":
            sql += "\nUPDATE users SET is_active = true WHERE is_active IS NULL;\n"
        op.execute(sql)


def downgrade() -> None:
    # Idempotent forward-only parity migration for production Supabase.
    pass
