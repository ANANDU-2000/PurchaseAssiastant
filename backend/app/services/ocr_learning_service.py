"""Persist user scan corrections for future matcher hints (Phase 3).

Tables: see ``backend/sql/supabase_020_ocr_learning.sql``. Wire from confirm/update
flows once DB models and RLS policies are approved.
"""

from __future__ import annotations

import uuid
from typing import Any


async def record_item_alias_hint(
    *,
    business_id: uuid.UUID,
    raw_text: str,
    catalog_item_id: uuid.UUID,
    db: Any | None = None,
) -> None:
    """Upsert-style alias (no-op until DB session wired)."""
    del business_id, raw_text, catalog_item_id, db


async def record_correction_event(
    *,
    business_id: uuid.UUID,
    user_id: uuid.UUID | None,
    field: str,
    raw_value: str | None,
    corrected_to: str | None,
    catalog_item_id: uuid.UUID | None = None,
    supplier_id: uuid.UUID | None = None,
    db: Any | None = None,
) -> None:
    """Audit trail for manual scan fixes (no-op until DB session wired)."""
    del business_id, user_id, field, raw_value, corrected_to, catalog_item_id, supplier_id, db
