"""Normalize catalog item unit profiles to KG/BAG/BOX/TIN/PC SSOT.

Revision ID: 061_catalog_unit_simplify
Revises: 060_stock_list_performance_indexes
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "061_catalog_unit_simplify"
down_revision: Union[str, None] = "060_stock_list_performance_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "061_catalog_unit_simplify.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    pass
