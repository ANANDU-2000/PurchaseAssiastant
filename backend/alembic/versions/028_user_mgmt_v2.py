"""User management v2: is_blocked, admin role, activity types.

Revision ID: 028_user_mgmt_v2
Revises: 025_user_system_rebuild
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "028_user_mgmt_v2"
down_revision: Union[str, None] = "025_user_system_rebuild"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "028_user_mgmt_v2.sql"


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    if _SQL.is_file():
        op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    pass
