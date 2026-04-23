"""Conversation state / idempotency / reply limits for WhatsApp via Redis."""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

from app.config import Settings
from app.services.whatsapp_state_v2 import WhatsAppEntityDraft

logger = logging.getLogger(__name__)

PREFIX = "hexa:wa:state:"


async def _redis_client(settings: Settings):
    if not settings.redis_url:
        return None
    try:
        import redis.asyncio as redis

        return redis.from_url(settings.redis_url, decode_responses=True)
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp Redis init failed: %s", e)
        return None


async def get_state(settings: Settings, phone: str) -> dict[str, Any] | None:
    try:
        r = await _redis_client(settings)
        if r is None:
            return None
        raw = await r.get(f"{PREFIX}{phone}")
        if not raw:
            return None
        return json.loads(raw)
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp state read failed: %s", e)
        return None


async def set_state(settings: Settings, phone: str, data: dict[str, Any], ttl_seconds: int = 86400) -> None:
    try:
        r = await _redis_client(settings)
        if r is None:
            return
        await r.setex(f"{PREFIX}{phone}", ttl_seconds, json.dumps(data))
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp state write failed: %s", e)


async def idempotent_message(settings: Settings, message_id: str | None, ttl_seconds: int = 86400 * 7) -> bool:
    """
    Returns True if this message_id should be processed (first time).
    False if duplicate or Redis unavailable (duplicate path returns True to avoid double-send when no Redis — caller may still risk duplicates).
    """
    if not message_id:
        return True
    try:
        r = await _redis_client(settings)
        if r is None:
            return True
        key = f"{PREFIX}idemp:{message_id}"
        ok = await r.set(key, "1", nx=True, ex=ttl_seconds)
        return bool(ok)
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp idempotency failed: %s", e)
        return True


def _hour_bucket_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d%H")


async def reset_consecutive_replies(settings: Settings, phone: str) -> None:
    try:
        r = await _redis_client(settings)
        if r is None:
            return
        await r.delete(f"{PREFIX}reply:consecutive:{phone}")
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp reset consecutive replies failed: %s", e)


async def can_send_reply(
    settings: Settings,
    phone: str,
    *,
    max_per_hour: int,
    max_consecutive: int,
) -> tuple[bool, str | None]:
    try:
        r = await _redis_client(settings)
        if r is None:
            return True, None
        hour_key = f"{PREFIX}reply:hour:{_hour_bucket_utc()}:{phone}"
        consecutive_key = f"{PREFIX}reply:consecutive:{phone}"
        hourly = int(await r.get(hour_key) or 0)
        consecutive = int(await r.get(consecutive_key) or 0)
        if hourly >= max_per_hour:
            return False, "hourly_limit"
        if consecutive >= max_consecutive:
            return False, "consecutive_limit"
        return True, None
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp reply budget check failed: %s", e)
        return True, None


async def mark_reply_sent(settings: Settings, phone: str) -> None:
    try:
        r = await _redis_client(settings)
        if r is None:
            return
        hour_key = f"{PREFIX}reply:hour:{_hour_bucket_utc()}:{phone}"
        consecutive_key = f"{PREFIX}reply:consecutive:{phone}"
        await r.incr(hour_key)
        await r.expire(hour_key, 7200)
        await r.incr(consecutive_key)
        await r.expire(consecutive_key, 86400)
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp mark reply sent failed: %s", e)


# --- Multi-turn purchase draft (key:value follow-ups; requires REDIS_URL) ---
_DRAFT_CREATE = f"{PREFIX}draft_create:"


async def set_pending_create_fields(
    settings: Settings, phone: str, fields: dict[str, Any], ttl_seconds: int = 1800
) -> None:
    """Remember partial create_entry ``data`` so the user can send more key:value lines."""
    try:
        r = await _redis_client(settings)
        if r is None:
            return
        await r.setex(f"{_DRAFT_CREATE}{phone}", ttl_seconds, json.dumps(fields))
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp draft write failed: %s", e)


async def get_pending_create_fields(settings: Settings, phone: str) -> dict[str, Any] | None:
    try:
        r = await _redis_client(settings)
        if r is None:
            return None
        raw = await r.get(f"{_DRAFT_CREATE}{phone}")
        if not raw:
            return None
        out = json.loads(raw)
        return out if isinstance(out, dict) else None
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp draft read failed: %s", e)
        return None


async def clear_pending_create_fields(settings: Settings, phone: str) -> None:
    try:
        r = await _redis_client(settings)
        if r is None:
            return
        await r.delete(f"{_DRAFT_CREATE}{phone}")
    except Exception as e:  # noqa: BLE001
        logger.warning("WhatsApp draft clear failed: %s", e)
