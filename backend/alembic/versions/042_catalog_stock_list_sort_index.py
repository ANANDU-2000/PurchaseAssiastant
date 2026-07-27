"""Index for stock list sort by last_stock_updated_at.

Revision ID: 042_catalog_stock_list_sort_index
Revises: 041_purchase_delivery_extras
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "042_catalog_stock_list_sort_index"
down_revision: Union[str, None] = "041_purchase_delivery_extras"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "042_catalog_stock_list_sort_index.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute(
        "DROP INDEX IF EXISTS ix_catalog_items_business_active_updated;"
    )
