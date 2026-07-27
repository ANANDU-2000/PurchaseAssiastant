"""Purchase delivery dispatch_note, delivered_qty_committed, index.

Revision ID: 041_purchase_delivery_extras
Revises: 040_purchase_delivery_tracking
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "041_purchase_delivery_extras"
down_revision: Union[str, None] = "040_purchase_delivery_tracking"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "041_purchase_delivery_extras.sql"


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    if _SQL.is_file():
        op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    pass
