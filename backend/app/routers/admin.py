import hashlib
import hmac
from datetime import date, datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import AdminCaller, require_admin_caller
from app.models import Business, Entry, User
from app.services.feature_flags import FLAG_FIELD_TO_KEY, get_effective_flags, upsert_flag

router = APIRouter(prefix="/v1/admin", tags=["admin"])


def _api_usage_payload(settings: Settings) -> dict:
    return {
        "providers": [
            {"name": "openai", "calls_24h": None, "note": "Wire api_usage_logs when implemented"},
            {"name": "360dialog", "calls_24h": None, "note": "Wire webhook metrics when implemented"},
        ],
        "integrations_configured": {
            "dialog360": bool(settings.dialog360_api_key and settings.dialog360_phone_number_id),
            "openai": bool(settings.openai_api_key),
        },
    }


class AdminLoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=1, max_length=256)


def _password_matches(stored: str, given: str) -> bool:
    """Avoid timing leaks on length mismatch while keeping internal-admin simplicity."""
    return hmac.compare_digest(
        hashlib.sha256(stored.encode("utf-8")).digest(),
        hashlib.sha256(given.encode("utf-8")).digest(),
    )


@router.post("/login")
async def admin_login(body: AdminLoginRequest, settings: Annotated[Settings, Depends(get_settings)]):
    """Email + password → static admin API token (same as ADMIN_API_TOKEN). For internal admin_web only."""
    if not settings.admin_email or not settings.admin_password or not settings.admin_api_token:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin login not configured (set ADMIN_EMAIL, ADMIN_PASSWORD, ADMIN_API_TOKEN).",
        )
    if body.email.strip().lower() != settings.admin_email.strip().lower():
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    if not _password_matches(settings.admin_password, body.password):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    return {"access_token": settings.admin_api_token, "token_type": "bearer"}


@router.get("/stats")
async def admin_stats(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _caller
    u = await db.execute(select(func.count(User.id)))
    b = await db.execute(select(func.count(Business.id)))
    today = date.today()
    e_today = await db.execute(select(func.count(Entry.id)).where(Entry.entry_date == today))
    e_all = await db.execute(select(func.count(Entry.id)))
    return {
        "users": int(u.scalar() or 0),
        "businesses": int(b.scalar() or 0),
        "entries_today": int(e_today.scalar() or 0),
        "entries_total": int(e_all.scalar() or 0),
        "as_of": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/metrics")
async def admin_metrics(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Legacy alias — subset of `/stats`."""
    del _caller
    u = await db.execute(select(func.count(User.id)))
    b = await db.execute(select(func.count(Business.id)))
    today = date.today()
    e = await db.execute(select(func.count(Entry.id)).where(Entry.entry_date == today))
    return {
        "users": int(u.scalar() or 0),
        "businesses": int(b.scalar() or 0),
        "entries_today": int(e.scalar() or 0),
    }


@router.get("/users")
async def admin_users(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(200, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    del _caller
    total = await db.scalar(select(func.count(User.id)))
    r = await db.execute(select(User).order_by(User.created_at.desc()).limit(limit).offset(offset))
    users = r.scalars().all()
    ids = [u.id for u in users]
    counts: dict = {}
    if ids:
        cr = await db.execute(
            select(Entry.user_id, func.count(Entry.id)).where(Entry.user_id.in_(ids)).group_by(Entry.user_id)
        )
        for uid, c in cr.all():
            counts[uid] = int(c or 0)
    return {
        "items": [
            {
                "id": str(u.id),
                "email": u.email,
                "username": u.username,
                "name": u.name,
                "phone": u.phone,
                "is_super_admin": u.is_super_admin,
                "created_at": u.created_at.isoformat() if u.created_at else None,
                "has_password": bool(u.password_hash),
                "google_linked": bool(u.google_sub),
                "total_entries": counts.get(u.id, 0),
            }
            for u in users
        ],
        "total": int(total or 0),
        "limit": limit,
        "offset": offset,
    }


@router.get("/businesses")
async def admin_businesses(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _caller
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
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _caller
    return _api_usage_payload(settings)


@router.get("/api-usage-summary")
async def admin_api_usage_summary(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _caller
    ec = await db.execute(select(Entry.user_id, func.count(Entry.id)).group_by(Entry.user_id))
    entry_counts = {row[0]: int(row[1] or 0) for row in ec.all()}
    ur = await db.execute(select(User).order_by(User.created_at.desc()).limit(300))
    per_user = []
    for u in ur.scalars().all():
        n = entry_counts.get(u.id, 0)
        per_user.append(
            {
                "user_id": str(u.id),
                "email": u.email,
                "entries_total": n,
                "whatsapp_messages_24h": None,
                "ai_calls_24h": None,
                "voice_minutes_24h": None,
                "estimated_cost_inr": round(n * 0.25, 2),
            }
        )
    return {
        **_api_usage_payload(settings),
        "per_user": per_user,
        "note": "per_user costs are placeholders until usage logs exist",
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


class FeatureFlagsUpdate(BaseModel):
    enable_ai: bool | None = None
    enable_ocr: bool | None = None
    enable_voice: bool | None = None
    enable_realtime: bool | None = None
    whatsapp_bot: bool | None = None


@router.get("/feature-flags")
async def admin_feature_flags(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _caller
    return await get_effective_flags(db, settings)


@router.patch("/feature-flags")
async def admin_patch_feature_flags(
    body: FeatureFlagsUpdate,
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _caller
    data = body.model_dump(exclude_unset=True)
    for field, val in data.items():
        if val is None:
            continue
        key = FLAG_FIELD_TO_KEY.get(field)
        if key:
            await upsert_flag(db, key, bool(val))
    await db.commit()
    return await get_effective_flags(db, settings)


@router.get("/integrations")
async def admin_integrations(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _caller
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
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
):
    del _caller
    return {"items": [], "note": "Wire audit log table / external store when implemented"}
