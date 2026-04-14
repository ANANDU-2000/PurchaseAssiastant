"""Guarded outbound WhatsApp text (rate limits + quiet hours). Shared by flow and transactional engine."""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.services.dialog360_send import send_text_message
from app.services.whatsapp_state import can_send_reply, mark_reply_sent

logger = logging.getLogger(__name__)


def _phone_tail(digits: str, n: int = 4) -> str:
    d = "".join(c for c in digits if c.isdigit())
    return d[-n:] if len(d) >= n else (d or "?")


BOT_MAX_REPLIES_BEFORE_WAITING = 3
BOT_MAX_PER_HOUR = 10
BOT_QUIET_HOURS_IST = (22, 7)  # 10pm–7am IST — no outbound replies


def in_quiet_hours_ist() -> bool:
    ist = datetime.now(timezone.utc) + timedelta(hours=5, minutes=30)
    h = ist.hour
    return h >= BOT_QUIET_HOURS_IST[0] or h < BOT_QUIET_HOURS_IST[1]


async def send_guarded_whatsapp(
    settings: Settings,
    db: AsyncSession,
    *,
    to_e164: str,
    body: str,
) -> dict[str, Any] | None:
    allowed, reason = await can_send_reply(
        settings,
        to_e164,
        max_per_hour=BOT_MAX_PER_HOUR,
        max_consecutive=BOT_MAX_REPLIES_BEFORE_WAITING,
    )
    if not allowed:
        logger.info("WhatsApp send blocked: %s", reason)
        return {"ok": False, "blocked": reason}
    res = await send_text_message(settings, db, to_e164=to_e164, body=body)
    await mark_reply_sent(settings, to_e164)
    tail = _phone_tail(to_e164)
    if isinstance(res, dict) and res.get("error"):
        logger.warning("whatsapp_outbound phone_tail=%s failed=%s", tail, str(res.get("error"))[:200])
    else:
        logger.info("whatsapp_outbound phone_tail=%s ok=1", tail)
    return res
