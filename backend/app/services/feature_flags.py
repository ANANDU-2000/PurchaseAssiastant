"""DB-backed feature flags with Settings fallbacks."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.models import FeatureFlag

KEY_AI = "ai_parsing"
KEY_OCR = "ocr"
KEY_VOICE = "voice"
KEY_REALTIME = "realtime"
KEY_WHATSAPP = "whatsapp_bot"


async def _enabled_or_default(db: AsyncSession, key: str, default: bool) -> bool:
    r = await db.execute(select(FeatureFlag.enabled).where(FeatureFlag.key == key))
    row = r.first()
    if row is None:
        return default
    return bool(row[0])


async def is_ai_parsing_enabled(db: AsyncSession, settings: Settings) -> bool:
    return await _enabled_or_default(db, KEY_AI, settings.enable_ai)


async def is_ocr_enabled(db: AsyncSession, settings: Settings) -> bool:
    return await _enabled_or_default(db, KEY_OCR, settings.enable_ocr)


async def is_voice_enabled(db: AsyncSession, settings: Settings) -> bool:
    return await _enabled_or_default(db, KEY_VOICE, settings.enable_voice)


async def is_realtime_enabled(db: AsyncSession, settings: Settings) -> bool:
    return await _enabled_or_default(db, KEY_REALTIME, settings.enable_realtime)


async def is_whatsapp_bot_enabled(db: AsyncSession, _settings: Settings) -> bool:
    """WhatsApp inbound bot defaults to on unless explicitly turned off in DB."""
    return await _enabled_or_default(db, KEY_WHATSAPP, True)


async def get_effective_flags(db: AsyncSession, settings: Settings) -> dict[str, bool]:
    return {
        "enable_ai": await is_ai_parsing_enabled(db, settings),
        "enable_ocr": await is_ocr_enabled(db, settings),
        "enable_voice": await is_voice_enabled(db, settings),
        "enable_realtime": await is_realtime_enabled(db, settings),
        "whatsapp_bot": await is_whatsapp_bot_enabled(db, settings),
    }


FLAG_FIELD_TO_KEY = {
    "enable_ai": KEY_AI,
    "enable_ocr": KEY_OCR,
    "enable_voice": KEY_VOICE,
    "enable_realtime": KEY_REALTIME,
    "whatsapp_bot": KEY_WHATSAPP,
}


async def upsert_flag(db: AsyncSession, key: str, enabled: bool) -> None:
    r = await db.execute(select(FeatureFlag).where(FeatureFlag.key == key))
    row = r.scalar_one_or_none()
    if row:
        row.enabled = enabled
    else:
        db.add(FeatureFlag(key=key, enabled=enabled))
