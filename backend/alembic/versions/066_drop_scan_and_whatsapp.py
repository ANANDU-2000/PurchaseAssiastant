"""Drop scan tables and WhatsApp columns.

Revision ID: 066_drop_scan_and_whatsapp
Revises: 065_archive_legacy_entries_tables
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "066_drop_scan_and_whatsapp"
down_revision: Union[str, None] = "065_archive_legacy_entries_tables"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "066_drop_scan_and_whatsapp.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    pass
