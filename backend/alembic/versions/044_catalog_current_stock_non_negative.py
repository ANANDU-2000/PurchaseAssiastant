"""Catalog items: non-negative current_stock CHECK constraint.

Revision ID: 044_catalog_current_stock_non_negative
Revises: 043_audit_perf_indexes
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "044_catalog_current_stock_non_negative"
down_revision: Union[str, None] = "043_audit_perf_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "044_catalog_current_stock_non_negative.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute(
        "ALTER TABLE catalog_items DROP CONSTRAINT IF EXISTS chk_current_stock_non_negative;"
    )
