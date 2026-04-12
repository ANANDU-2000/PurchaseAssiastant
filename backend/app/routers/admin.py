import hashlib
import hmac
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import AdminCaller, require_admin_caller
from app.models import (
    AdminAuditLog,
    ApiUsageLog,
    BillingPayment,
    Business,
    BusinessSubscription,
    Entry,
    PlatformIntegration,
    PlatformMonthlyExpense,
    User,
)
from app.services.feature_flags import FLAG_FIELD_TO_KEY, get_effective_flags, upsert_flag
from app.services.platform_credentials import (
    effective_dialog360,
    effective_openai_key,
    effective_razorpay_keys,
    ensure_integration_row,
    get_integration_row,
    mask_secret,
    source_label,
)
from app.services.admin_audit import audit as admin_audit_log

router = APIRouter(prefix="/v1/admin", tags=["admin"])


async def _api_usage_payload(settings: Settings, db: AsyncSession) -> dict:
    d360_key, d360_phone, _, _ = await effective_dialog360(settings, db)
    oai = await effective_openai_key(settings, db)
    since = datetime.now(timezone.utc) - timedelta(hours=24)
    br = await db.execute(
        select(ApiUsageLog.provider, func.count(ApiUsageLog.id))
        .where(ApiUsageLog.created_at >= since)
        .group_by(ApiUsageLog.provider)
    )
    by_provider = {row[0]: int(row[1] or 0) for row in br.all()}
    total_24h = sum(by_provider.values())
    return {
        "providers": [
            {"name": k, "calls_24h": v, "note": "api_usage_logs"}
            for k, v in sorted(by_provider.items(), key=lambda x: -x[1])
        ],
        "calls_24h_total": total_24h,
        "integrations_configured": {
            "dialog360": bool(d360_key and d360_phone),
            "openai": bool(oai),
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
async def admin_login(settings: Annotated[Settings, Depends(get_settings)], body: AdminLoginRequest):
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
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _caller
    return await _api_usage_payload(settings, db)


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
        **(await _api_usage_payload(settings, db)),
        "per_user": per_user,
        "note": "Provider totals use api_usage_logs; per_user entry costs remain heuristic",
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
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: FeatureFlagsUpdate,
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
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del _caller
    d360_key, d360_phone, d360_base, _ = await effective_dialog360(settings, db)
    oai = await effective_openai_key(settings, db)
    return {
        "dialog360": {
            "configured": bool(d360_key and d360_phone),
            "base_url": d360_base,
        },
        "openai": {"configured": bool(oai)},
        "ocr": {"configured": bool(settings.ocr_api_key), "provider": settings.ocr_provider},
        "stt": {"configured": bool(settings.stt_api_key), "provider": settings.stt_provider},
        "s3": {"configured": bool(settings.s3_bucket and settings.s3_access_key)},
        "razorpay": {
            "configured": bool((await effective_razorpay_keys(settings, db))[0]),
        },
        "sentry": {"configured": bool(settings.sentry_dsn)},
        "redis": {"configured": bool(settings.redis_url)},
    }


@router.get("/audit-logs")
async def admin_audit_logs(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(100, ge=1, le=500),
):
    del _caller
    r = await db.execute(select(AdminAuditLog).order_by(AdminAuditLog.created_at.desc()).limit(limit))
    rows = r.scalars().all()
    return {
        "items": [
            {
                "id": str(x.id),
                "actor": x.actor,
                "action": x.action,
                "resource_type": x.resource_type,
                "resource_id": x.resource_id,
                "details": x.details,
                "note": x.note,
                "created_at": x.created_at.isoformat() if x.created_at else None,
            }
            for x in rows
        ],
        "total_returned": len(rows),
    }


class PlatformIntegrationUpdate(BaseModel):
    """Empty string for a field clears the database override (environment / .env is used again)."""

    openai_api_key: str | None = None
    google_ai_api_key: str | None = None
    groq_api_key: str | None = None
    dialog360_api_key: str | None = None
    dialog360_phone_number_id: str | None = None
    dialog360_base_url: str | None = None
    dialog360_webhook_secret: str | None = None
    razorpay_key_id: str | None = None
    razorpay_key_secret: str | None = None
    razorpay_webhook_secret: str | None = None


def _field_sources(row: PlatformIntegration | None, settings: Settings) -> dict[str, dict[str, str | bool]]:
    """Masked tails + whether DB overrides env."""

    def one(db_val: str | None, env_val: str | None, name: str) -> dict[str, str | bool]:
        return {
            "masked": mask_secret(db_val) if db_val else None,
            "source": source_label(db_val, env_val),
            "has_database_value": bool(db_val and str(db_val).strip()),
            "field": name,
        }

    return {
        "openai_api_key": one(row.openai_api_key if row else None, settings.openai_api_key, "openai_api_key"),
        "google_ai_api_key": one(row.google_ai_api_key if row else None, settings.google_ai_api_key, "google_ai_api_key"),
        "groq_api_key": one(row.groq_api_key if row else None, settings.groq_api_key, "groq_api_key"),
        "dialog360_api_key": one(row.dialog360_api_key if row else None, settings.dialog360_api_key, "dialog360_api_key"),
        "dialog360_phone_number_id": one(
            row.dialog360_phone_number_id if row else None,
            settings.dialog360_phone_number_id,
            "dialog360_phone_number_id",
        ),
        "dialog360_base_url": one(row.dialog360_base_url if row else None, settings.dialog360_base_url, "dialog360_base_url"),
        "dialog360_webhook_secret": one(
            row.dialog360_webhook_secret if row else None,
            settings.dialog360_webhook_secret,
            "dialog360_webhook_secret",
        ),
        "razorpay_key_id": one(row.razorpay_key_id if row else None, settings.razorpay_key_id, "razorpay_key_id"),
        "razorpay_key_secret": one(
            row.razorpay_key_secret if row else None, settings.razorpay_key_secret, "razorpay_key_secret"
        ),
        "razorpay_webhook_secret": one(
            row.razorpay_webhook_secret if row else None,
            settings.razorpay_webhook_secret,
            "razorpay_webhook_secret",
        ),
    }


@router.get("/platform-integration")
async def admin_get_platform_integration(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    """Secrets stored in `platform_integration` row id=1 — overrides process env without redeploy."""
    del _caller
    row = await get_integration_row(db)
    d360_key, d360_phone, _, _ = await effective_dialog360(settings, db)
    oai = await effective_openai_key(settings, db)
    rzp_id, _, _ = await effective_razorpay_keys(settings, db)
    mode = "none"
    if rzp_id:
        if rzp_id.startswith("rzp_test"):
            mode = "test"
        elif rzp_id.startswith("rzp_live"):
            mode = "live"
        else:
            mode = "unknown"
    return {
        "effective": {
            "openai_configured": bool(oai),
            "dialog360_configured": bool(d360_key and d360_phone),
            "razorpay_configured": bool(rzp_id),
            "razorpay_mode": mode,
        },
        "fields": _field_sources(row, settings),
        "note": "Use PUT with new values. Send empty string to clear DB override for that field.",
    }


@router.put("/platform-integration")
async def admin_put_platform_integration(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: PlatformIntegrationUpdate,
):
    actor = "machine" if _caller.machine else (str(_caller.user.id) if _caller.user else "unknown")
    row = await ensure_integration_row(db)
    data = body.model_dump(exclude_unset=True)
    allowed = {f for f in PlatformIntegrationUpdate.model_fields}
    for key, value in data.items():
        if key not in allowed or not hasattr(row, key):
            continue
        if value == "":
            setattr(row, key, None)
        else:
            setattr(row, key, value)
    row.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(row)
    await admin_audit_log(
        db,
        actor=actor,
        action="platform_integration_update",
        resource_type="platform_integration",
        resource_id="1",
        details={"updated_keys": list(data.keys())},
    )
    return {"ok": True, "updated_keys": list(data.keys())}


class AdminEnvUpdateRequest(BaseModel):
    """Deprecated — use PUT /platform-integration."""

    updates: dict[str, str] = Field(default_factory=dict)


@router.post("/env-update")
async def admin_env_update(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    body: AdminEnvUpdateRequest,
):
    del _caller, body
    return {
        "ok": True,
        "deprecated": True,
        "note": "Use PUT /v1/admin/platform-integration to persist API keys in the database (effective immediately; no redeploy).",
    }


class SubscriptionPatchBody(BaseModel):
    admin_exempt: bool | None = None
    exempt_reason: str | None = None
    status: str | None = None
    whatsapp_addon: bool | None = None
    ai_addon: bool | None = None


class ExpenseCreateBody(BaseModel):
    month: date
    label: str = Field(min_length=1, max_length=255)
    amount_inr_paise: int = Field(ge=0)
    category: str = Field(default="infra", max_length=64)
    notes: str | None = None


@router.get("/billing/subscriptions")
async def admin_billing_subscriptions(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _caller
    r = await db.execute(
        select(BusinessSubscription, Business.name)
        .join(Business, Business.id == BusinessSubscription.business_id)
        .order_by(BusinessSubscription.updated_at.desc())
    )
    out = []
    for sub, bname in r.all():
        out.append(
            {
                "business_id": str(sub.business_id),
                "business_name": bname,
                "plan_code": sub.plan_code,
                "status": sub.status,
                "whatsapp_addon": sub.whatsapp_addon,
                "ai_addon": sub.ai_addon,
                "admin_exempt": sub.admin_exempt,
                "exempt_reason": sub.exempt_reason,
                "grace_until": sub.grace_until.isoformat() if sub.grace_until else None,
                "current_period_end": sub.current_period_end.isoformat() if sub.current_period_end else None,
                "monthly_base_paise": sub.monthly_base_paise,
                "monthly_addons_paise": sub.monthly_addons_paise,
            }
        )
    return {"items": out, "total": len(out)}


@router.patch("/billing/businesses/{business_id}/subscription")
async def admin_patch_business_subscription(
    business_id: uuid.UUID,
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: SubscriptionPatchBody,
):
    actor = "machine" if _caller.machine else (str(_caller.user.id) if _caller.user else "unknown")
    r = await db.execute(select(BusinessSubscription).where(BusinessSubscription.business_id == business_id))
    sub = r.scalar_one_or_none()
    if not sub:
        sub = BusinessSubscription(business_id=business_id, status="active", plan_code="basic")
        db.add(sub)
    data = body.model_dump(exclude_unset=True)
    allowed_status = {"active", "trialing", "past_due", "suspended", "exempt"}
    if data.get("status") is not None and data["status"] not in allowed_status:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid status")
    for k, v in data.items():
        if v is not None and hasattr(sub, k):
            setattr(sub, k, v)
    sub.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(sub)
    await admin_audit_log(
        db,
        actor=actor,
        action="subscription_patch",
        resource_type="business",
        resource_id=str(business_id),
        details=data,
    )
    return {"ok": True, "business_id": str(business_id)}


@router.get("/billing/payments")
async def admin_billing_payments(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(100, ge=1, le=500),
):
    del _caller
    r = await db.execute(select(BillingPayment).order_by(BillingPayment.created_at.desc()).limit(limit))
    rows = r.scalars().all()
    return {
        "items": [
            {
                "id": str(p.id),
                "business_id": str(p.business_id),
                "razorpay_order_id": p.razorpay_order_id,
                "razorpay_payment_id": p.razorpay_payment_id,
                "amount_paise": p.amount_paise,
                "status": p.status,
                "created_at": p.created_at.isoformat() if p.created_at else None,
                "paid_at": p.paid_at.isoformat() if p.paid_at else None,
            }
            for p in rows
        ]
    }


@router.get("/billing/integrity")
async def admin_billing_integrity(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _caller
    r = await db.execute(
        select(func.count(BillingPayment.id)).where(
            BillingPayment.status == "created",
            BillingPayment.created_at < datetime.now(timezone.utc) - timedelta(days=2),
        )
    )
    stale_orders = int(r.scalar() or 0)
    return {
        "stale_unpaid_orders_older_than_2d": stale_orders,
        "note": "Investigate abandoned checkouts or webhook gaps.",
    }


@router.post("/billing/expenses")
async def admin_post_expense(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: ExpenseCreateBody,
):
    actor = "machine" if _caller.machine else (str(_caller.user.id) if _caller.user else "unknown")
    exp = PlatformMonthlyExpense(
        month=body.month,
        label=body.label,
        amount_inr_paise=body.amount_inr_paise,
        category=body.category,
        notes=body.notes,
    )
    db.add(exp)
    await db.commit()
    await db.refresh(exp)
    await admin_audit_log(
        db,
        actor=actor,
        action="expense_create",
        resource_type="platform_monthly_expense",
        resource_id=str(exp.id),
        details={"label": body.label, "amount_inr_paise": body.amount_inr_paise},
    )
    return {"ok": True, "id": str(exp.id)}


@router.get("/billing/expenses")
async def admin_list_expenses(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _caller
    r = await db.execute(select(PlatformMonthlyExpense).order_by(PlatformMonthlyExpense.month.desc()))
    rows = r.scalars().all()
    return {
        "items": [
            {
                "id": str(x.id),
                "month": x.month.isoformat(),
                "label": x.label,
                "amount_inr_paise": x.amount_inr_paise,
                "category": x.category,
                "notes": x.notes,
            }
            for x in rows
        ]
    }


@router.get("/billing/usage-logs")
async def admin_billing_usage_logs(
    _caller: Annotated[AdminCaller, Depends(require_admin_caller)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(200, ge=1, le=1000),
):
    del _caller
    r = await db.execute(select(ApiUsageLog).order_by(ApiUsageLog.created_at.desc()).limit(limit))
    rows = r.scalars().all()
    return {
        "items": [
            {
                "id": str(x.id),
                "business_id": str(x.business_id) if x.business_id else None,
                "provider": x.provider,
                "action": x.action,
                "units": x.units,
                "created_at": x.created_at.isoformat() if x.created_at else None,
            }
            for x in rows
        ]
    }


@router.get("/whatsapp-stats")
async def admin_whatsapp_stats(_caller: Annotated[AdminCaller, Depends(require_admin_caller)]):
    del _caller
    return {
        "messages_24h": None,
        "delivery_rate": None,
        "note": "Wire 360dialog or WhatsApp Business metrics when available.",
    }
