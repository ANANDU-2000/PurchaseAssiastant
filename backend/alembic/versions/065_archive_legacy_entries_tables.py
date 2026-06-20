"""Archive legacy entries tables (router removed; data kept).

Revision ID: 065_archive_legacy_entries_tables
Revises: 064_critical_performance_indexes
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence, Union

from alembic import op

revision: str = "065_archive_legacy_entries_tables"
down_revision: Union[str, None] = "064_critical_performance_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_SQL = Path(__file__).resolve().parents[2] / "sql" / "065_archive_legacy_entries_tables.sql"


def upgrade() -> None:
    op.execute(_SQL.read_text(encoding="utf-8"))


def downgrade() -> None:
    op.execute(
        """
        DO $$
        BEGIN
          IF to_regclass('public._archived_entries') IS NOT NULL
             AND to_regclass('public.entries') IS NULL THEN
            ALTER TABLE _archived_entries RENAME TO entries;
          END IF;
        END $$;
        """
    )
    op.execute(
        """
        DO $$
        BEGIN
          IF to_regclass('public._archived_entry_line_items') IS NOT NULL
             AND to_regclass('public.entry_line_items') IS NULL THEN
            ALTER TABLE _archived_entry_line_items RENAME TO entry_line_items;
          END IF;
        END $$;
        """
    )
