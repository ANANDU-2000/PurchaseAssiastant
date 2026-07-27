"""Add idempotency_key to stock_physical_counts."""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "068_physical_count_idempotency_key"
down_revision: Union[str, None] = "067_user_token_version"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "068_physical_count_idempotency_key.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_stock_physical_count_idempotency;")
    op.execute("ALTER TABLE stock_physical_counts DROP COLUMN IF EXISTS idempotency_key;")
