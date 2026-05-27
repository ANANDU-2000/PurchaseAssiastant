"""Stock dispute cases for low-stock operations.

Revision ID: 039_stock_dispute_cases
Revises: 038_notification_alert_v2
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "039_stock_dispute_cases"
down_revision: Union[str, None] = "038_notification_alert_v2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "039_stock_dispute_cases.sql"


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    if _SQL.is_file():
        op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    pass
