"""Purchase delivery_status pipeline columns.

Revision ID: 040_purchase_delivery_tracking
Revises: 039_stock_dispute_cases
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "040_purchase_delivery_tracking"
down_revision: Union[str, None] = "039_stock_dispute_cases"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "040_purchase_delivery_tracking.sql"


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    if _SQL.is_file():
        op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    pass
