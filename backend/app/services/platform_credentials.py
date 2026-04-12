"""Resolve API credentials: database overrides win over process environment (Settings)."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.models import PlatformIntegration

ROW_ID = 1


def _coalesce(db_val: str | None, env_val: str | None) -> str | None:
    if db_val is not None and str(db_val).strip() != "":
        return db_val
    return env_val


async def get_integration_row(db: AsyncSession) -> PlatformIntegration | None:
    r = await db.execute(select(PlatformIntegration).where(PlatformIntegration.id == ROW_ID))
    return r.scalar_one_or_none()


async def ensure_integration_row(db: AsyncSession) -> PlatformIntegration:
    row = await get_integration_row(db)
    if row is None:
        row = PlatformIntegration(id=ROW_ID)
        db.add(row)
        await db.commit()
        await db.refresh(row)
    return row


def mask_secret(s: str | None) -> str | None:
    if not s:
        return None
    t = s.strip()
    if len(t) <= 4:
        return "****"
    return f"…{t[-4:]}"


def source_label(db_val: str | None, env_val: str | None) -> str:
    if db_val is not None and str(db_val).strip() != "":
        return "database"
    if env_val is not None and str(env_val).strip() != "":
        return "environment"
    return "none"


async def effective_openai_key(settings: Settings, db: AsyncSession | None) -> str | None:
    if db is None:
        return settings.openai_api_key
    row = await get_integration_row(db)
    return _coalesce(row.openai_api_key if row else None, settings.openai_api_key)


async def effective_groq_key(settings: Settings, db: AsyncSession | None) -> str | None:
    row = await get_integration_row(db) if db else None
    return _coalesce(row.groq_api_key if row else None, settings.groq_api_key)


async def effective_google_ai_key(settings: Settings, db: AsyncSession | None) -> str | None:
    row = await get_integration_row(db) if db else None
    return _coalesce(row.google_ai_api_key if row else None, settings.google_ai_api_key)


async def effective_razorpay_keys(
    settings: Settings, db: AsyncSession | None,
) -> tuple[str | None, str | None, str | None]:
    """Returns (key_id, key_secret, webhook_secret)."""
    row = await get_integration_row(db) if db else None
    kid = _coalesce(row.razorpay_key_id if row else None, settings.razorpay_key_id)
    sec = _coalesce(row.razorpay_key_secret if row else None, settings.razorpay_key_secret)
    wh = _coalesce(row.razorpay_webhook_secret if row else None, settings.razorpay_webhook_secret)
    return kid, sec, wh


async def effective_dialog360(
    settings: Settings, db: AsyncSession | None
) -> tuple[str | None, str | None, str, str | None]:
    """Returns (api_key, phone_number_id, base_url, webhook_secret) for outbound + webhook verify."""
    row = await get_integration_row(db) if db else None
    api_key = _coalesce(row.dialog360_api_key if row else None, settings.dialog360_api_key)
    phone_id = _coalesce(row.dialog360_phone_number_id if row else None, settings.dialog360_phone_number_id)
    base = (row.dialog360_base_url if row and row.dialog360_base_url else None) or settings.dialog360_base_url
    wh = _coalesce(row.dialog360_webhook_secret if row else None, settings.dialog360_webhook_secret)
    return api_key, phone_id, base.rstrip("/"), wh
