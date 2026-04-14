"""Cached introspection for optional columns (older DBs vs current ORM models)."""

from __future__ import annotations

import logging

from sqlalchemy import inspect as sa_inspect
from sqlalchemy.ext.asyncio import AsyncSession

_catalog_has_type_id: bool | None = None
logger = logging.getLogger(__name__)


async def catalog_items_has_type_id_column(db: AsyncSession) -> bool:
    """True when catalog_items.type_id exists (avoids SELECT on missing column)."""
    global _catalog_has_type_id
    if _catalog_has_type_id is not None:
        return _catalog_has_type_id

    def _chk(sync_session) -> bool:
        conn = sync_session.connection()
        insp = sa_inspect(conn)
        if not insp.has_table("catalog_items"):
            return False
        cols = {c["name"] for c in insp.get_columns("catalog_items")}
        return "type_id" in cols

    try:
        _catalog_has_type_id = await db.run_sync(_chk)
    except Exception:  # noqa: BLE001
        # Fail closed for legacy schemas or restricted DB metadata visibility.
        logger.exception("catalog_items_has_type_id_column introspection failed; defaulting to False")
        _catalog_has_type_id = False
    return _catalog_has_type_id
