"""Per-business subscription checks for optional add-ons (WhatsApp, AI)."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from fastapi import HTTPException, status

from app.models import BusinessSubscription


async def get_subscription(db: AsyncSession, business_id) -> BusinessSubscription | None:
    r = await db.execute(select(BusinessSubscription).where(BusinessSubscription.business_id == business_id))
    return r.scalar_one_or_none()


def _now() -> datetime:
    return datetime.now(timezone.utc)


def subscription_allows_core_access(sub: BusinessSubscription | None, settings: Settings) -> bool:
    """If billing not enforced, always allow. No row = grandfather active."""
    if not settings.billing_enforce:
        return True
    if sub is None:
        return True
    if sub.admin_exempt or sub.status == "exempt":
        return True
    if sub.status in ("active", "trialing"):
        return True
    if sub.status == "past_due":
        if sub.grace_until and sub.grace_until > _now():
            return True
        return False
    if sub.status == "suspended":
        return False
    return True


def subscription_allows_whatsapp(sub: BusinessSubscription | None, settings: Settings) -> bool:
    """WhatsApp bot requires add-on when billing_enforce (unless exempt / grandfather)."""
    if not settings.billing_enforce:
        return True
    if sub is None:
        return True
    if sub.admin_exempt or sub.status == "exempt":
        return True
    if not subscription_allows_core_access(sub, settings):
        return False
    return bool(sub.whatsapp_addon)


def subscription_allows_ai(sub: BusinessSubscription | None, settings: Settings) -> bool:
    """AI routes require add-on when billing_enforce (unless exempt / grandfather)."""
    if not settings.billing_enforce:
        return True
    if sub is None:
        return True
    if sub.admin_exempt or sub.status == "exempt":
        return True
    if not subscription_allows_core_access(sub, settings):
        return False
    return bool(sub.ai_addon)


async def ensure_subscription_row(db: AsyncSession, business_id) -> BusinessSubscription:
    row = await get_subscription(db, business_id)
    if row:
        return row
    row = BusinessSubscription(business_id=business_id, status="active", plan_code="basic")
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row


async def assert_ai_entitled(db: AsyncSession, business_id, settings: Settings) -> None:
    sub = await get_subscription(db, business_id)
    if not subscription_allows_ai(sub, settings):
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            detail="AI add-on is not active for this workspace — open Subscription or contact admin.",
        )


async def assert_whatsapp_entitled(db: AsyncSession, business_id, settings: Settings) -> None:
    sub = await get_subscription(db, business_id)
    if not subscription_allows_whatsapp(sub, settings):
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            detail="WhatsApp add-on is not active — pay the bundle or contact admin.",
        )
