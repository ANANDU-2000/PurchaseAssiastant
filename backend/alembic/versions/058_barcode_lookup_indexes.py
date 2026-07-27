"""Barcode lookup performance indexes.

Revision ID: 058_barcode_lookup_indexes
Revises: 057_purchase_damage_reports_v2
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "058_barcode_lookup_indexes"
down_revision: Union[str, None] = "057_purchase_damage_reports_v2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "058_barcode_lookup_perf.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_catalog_items_business_barcode_lookup;")
    op.execute("DROP INDEX IF EXISTS idx_catalog_items_business_item_code;")
