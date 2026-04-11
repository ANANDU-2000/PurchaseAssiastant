from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import require_super_admin
from app.config import Settings, get_settings
from app.models import Business, Entry, User

router = APIRouter(prefix="/v1/admin", tags=["admin"])


@router.get("/metrics")
async def admin_metrics(
    _admin: Annotated[User, Depends(require_super_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _admin
    u = await db.execute(select(func.count(User.id)))
    b = await db.execute(select(func.count(Business.id)))
    today = date.today()
    e = await db.execute(select(func.count(Entry.id)).where(Entry.entry_date == today))
    return {
        "users": int(u.scalar() or 0),
        "businesses": int(b.scalar() or 0),
        "entries_today": int(e.scalar() or 0),
    }


@router.get("/businesses")
async def admin_businesses(
    _admin: Annotated[User, Depends(require_super_admin)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _admin
    r = await db.execute(select(Business.id, Business.name, Business.created_at))
    rows = r.all()
    return {
        "items": [
            {"id": str(row[0]), "name": row[1], "created_at": row[2].isoformat() if row[2] else None}
            for row in rows
        ]
    }


@router.get("/api-usage")
async def admin_api_usage(
    _admin: Annotated[User, Depends(require_super_admin)],
):
    del _admin
    return {
        "providers": [
            {"name": "openai", "calls_24h": None, "note": "Wire api_usage_logs when implemented"},
            {"name": "360dialog", "calls_24h": None, "note": "Wire webhook metrics when implemented"},
        ]
    }


@router.get("/feature-flags")
async def admin_feature_flags(
    _admin: Annotated[User, Depends(require_super_admin)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _admin
    return {
        "enable_ai": settings.enable_ai,
        "enable_ocr": settings.enable_ocr,
        "enable_voice": settings.enable_voice,
        "enable_realtime": settings.enable_realtime,
    }


@router.get("/integrations")
async def admin_integrations(
    _admin: Annotated[User, Depends(require_super_admin)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _admin
    return {
        "dialog360": {
            "configured": bool(settings.dialog360_api_key and settings.dialog360_phone_number_id),
            "base_url": settings.dialog360_base_url,
        },
        "openai": {"configured": bool(settings.openai_api_key)},
        "ocr": {"configured": bool(settings.ocr_api_key), "provider": settings.ocr_provider},
        "stt": {"configured": bool(settings.stt_api_key), "provider": settings.stt_provider},
        "s3": {"configured": bool(settings.s3_bucket and settings.s3_access_key)},
        "razorpay": {"configured": bool(settings.razorpay_key_id)},
        "sentry": {"configured": bool(settings.sentry_dsn)},
        "redis": {"configured": bool(settings.redis_url)},
    }


@router.get("/audit-logs")
async def admin_audit_logs(
    _admin: Annotated[User, Depends(require_super_admin)],
):
    del _admin
    return {"items": [], "note": "Wire audit log table / external store when implemented"}