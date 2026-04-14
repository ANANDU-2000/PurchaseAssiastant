"""Persist in-app assistant purchase-entry draft in Redis (optional; no-op if REDIS_URL unset)."""

from __future__ import annotations

import json
import logging
import uuid
from typing import Any

from app.config import Settings
from app.services.whatsapp_state import _redis_client

logger = logging.getLogger(__name__)

_PREFIX = "hexa:chat_draft:"
_TTL = 1800


def _key(user_id: uuid.UUID, business_id: uuid.UUID) -> str:
    return f"{_PREFIX}{user_id}:{business_id}"


async def load_chat_draft(
    settings: Settings, user_id: uuid.UUID, business_id: uuid.UUID
) -> dict[str, Any] | None:
    try:
        r = await _redis_client(settings)
        if r is None:
            return None
        raw = await r.get(_key(user_id, business_id))
        if not raw:
            return None
        data = json.loads(raw)
        return data if isinstance(data, dict) else None
    except Exception as e:  # noqa: BLE001
        logger.warning("chat draft load failed: %s", e)
        return None


async def save_chat_draft(
    settings: Settings,
    user_id: uuid.UUID,
    business_id: uuid.UUID,
    draft: dict[str, Any],
) -> None:
    try:
        r = await _redis_client(settings)
        if r is None:
            return
        await r.setex(_key(user_id, business_id), _TTL, json.dumps(draft, default=str))
    except Exception as e:  # noqa: BLE001
        logger.warning("chat draft save failed: %s", e)


async def clear_chat_draft(
    settings: Settings, user_id: uuid.UUID, business_id: uuid.UUID
) -> None:
    try:
        r = await _redis_client(settings)
        if r is None:
            return
        await r.delete(_key(user_id, business_id))
    except Exception as e:  # noqa: BLE001
        logger.warning("chat draft clear failed: %s", e)


async def merge_chat_draft(
    settings: Settings,
    user_id: uuid.UUID,
    business_id: uuid.UUID,
    patch: dict[str, Any],
) -> dict[str, Any]:
    """Merge keys into existing draft (or start empty). Persists to Redis when available."""
    cur = await load_chat_draft(settings, user_id, business_id) or {}
    cur.update(patch)
    await save_chat_draft(settings, user_id, business_id, cur)
    return cur
