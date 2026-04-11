"""Conversation state for WhatsApp — Redis JSON blobs keyed by phone."""

from __future__ import annotations

import json
import logging
from typing import Any

from app.config import Settings

logger = logging.getLogger(__name__)

PREFIX = "hexa:wa:state:"


async def get_state(settings: Settings, phone: str) -> dict[str, Any] | None:
    if not settings.redis_url:
        return None
    try:
        import redis.asyncio as redis

        r = redis.from_url(settings.redis_url, decode_responses=True)
        raw = await r.get(f"{PREFIX}{phone}")
        if not raw:
            return None
        return json.loads(raw)
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp state read failed: %s", e)
        return None


async def set_state(settings: Settings, phone: str, data: dict[str, Any], ttl_seconds: int = 86400) -> None:
    if not settings.redis_url:
        return
    try:
        import redis.asyncio as redis

        r = redis.from_url(settings.redis_url, decode_responses=True)
        await r.setex(f"{PREFIX}{phone}", ttl_seconds, json.dumps(data))
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp state write failed: %s", e)


async def idempotent_message(settings: Settings, message_id: str | None, ttl_seconds: int = 86400 * 7) -> bool:
    """
    Returns True if this message_id should be processed (first time).
    False if duplicate or Redis unavailable (duplicate path returns True to avoid double-send when no Redis — caller may still risk duplicates).
    """
    if not message_id or not settings.redis_url:
        return True
    try:
        import redis.asyncio as redis

        r = redis.from_url(settings.redis_url, decode_responses=True)
        key = f"{PREFIX}idemp:{message_id}"
        ok = await r.set(key, "1", nx=True, ex=ttl_seconds)
        return bool(ok)
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp idempotency failed: %s", e)
        return True
