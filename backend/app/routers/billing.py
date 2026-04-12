"""Per-business Razorpay checkout: quote, create order, verify payment."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import require_membership, require_owner_membership
from app.models import BillingPayment, BusinessSubscription, Membership, User
from app.services.billing_entitlements import ensure_subscription_row, get_subscription
from app.services.platform_credentials import effective_razorpay_keys
from app.services.razorpay_service import create_order, verify_payment_signature
from app.services.usage_logging import log_usage

router = APIRouter(prefix="/v1/businesses/{business_id}/billing", tags=["billing"])


def _monthly_amount_paise(
    settings: Settings, plan_code: str, whatsapp_addon: bool, ai_addon: bool
) -> int:
    """Infra (cloud) base + plan delta + optional WhatsApp/AI combo (one add-on fee if either selected)."""
    total = settings.billing_cloud_infra_paise
    if plan_code == "pro":
        total += max(0, settings.plan_pro_price_inr - settings.plan_basic_price_inr)
    elif plan_code == "premium":
        total += max(0, settings.plan_premium_price_inr - settings.plan_basic_price_inr)
    if whatsapp_addon or ai_addon:
        total += settings.billing_whatsapp_ai_addon_paise
    return int(total)


class BillingQuoteOut(BaseModel):
    plan_code: str
    whatsapp_addon: bool
    ai_addon: bool
    amount_paise: int
    amount_inr: float
    currency: str = "INR"


class CreateOrderBody(BaseModel):
    plan_code: str = Field(default="basic", pattern="^(basic|pro|premium)$")
    whatsapp_addon: bool = False
    ai_addon: bool = False


class CreateOrderOut(BaseModel):
    order_id: str
    amount_paise: int
    currency: str
    key_id: str
    business_id: str
    idempotency_key: str


class VerifyBody(BaseModel):
    razorpay_order_id: str
    razorpay_payment_id: str
    razorpay_signature: str


@router.get("/status")
async def billing_status(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    del user
    sub = await get_subscription(db, business_id)
    kid, _, _ = await effective_razorpay_keys(settings, db)
    if not sub:
        return {
            "has_subscription_row": False,
            "billing_enforce": settings.billing_enforce,
            "razorpay_configured": bool(kid),
            "subscription": None,
        }
    return {
        "has_subscription_row": True,
        "billing_enforce": settings.billing_enforce,
        "razorpay_configured": bool(kid),
        "subscription": {
            "plan_code": sub.plan_code,
            "status": sub.status,
            "whatsapp_addon": sub.whatsapp_addon,
            "ai_addon": sub.ai_addon,
            "voice_addon": sub.voice_addon,
            "admin_exempt": sub.admin_exempt,
            "grace_until": sub.grace_until.isoformat() if sub.grace_until else None,
            "current_period_end": sub.current_period_end.isoformat() if sub.current_period_end else None,
            "monthly_base_paise": sub.monthly_base_paise,
            "monthly_addons_paise": sub.monthly_addons_paise,
        },
    }


@router.get("/quote", response_model=BillingQuoteOut)
async def billing_quote(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    settings: Annotated[Settings, Depends(get_settings)],
    plan_code: str = "basic",
    whatsapp_addon: bool = False,
    ai_addon: bool = False,
):
    del business_id, _m
    if plan_code not in ("basic", "pro", "premium"):
        plan_code = "basic"
    amt = _monthly_amount_paise(settings, plan_code, whatsapp_addon, ai_addon)
    return BillingQuoteOut(
        plan_code=plan_code,
        whatsapp_addon=whatsapp_addon,
        ai_addon=ai_addon,
        amount_paise=amt,
        amount_inr=round(amt / 100.0, 2),
    )


@router.post("/create-order", response_model=CreateOrderOut)
async def billing_create_order(
    business_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: CreateOrderBody,
):
    kid, secret, _ = await effective_razorpay_keys(settings, db)
    if not kid or not secret:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Razorpay is not configured on the server.",
        )
    amount = _monthly_amount_paise(settings, body.plan_code, body.whatsapp_addon, body.ai_addon)
    idem = f"biz-{business_id}-{uuid.uuid4().hex[:16]}"
    notes: dict[str, Any] = {
        "business_id": str(business_id),
        "plan_code": body.plan_code,
        "whatsapp_addon": body.whatsapp_addon,
        "ai_addon": body.ai_addon,
    }
    try:
        order = await create_order(
            settings=settings,
            db=db,
            amount_paise=amount,
            receipt=idem[:40],
            notes=notes,
        )
    except ValueError as e:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, detail=str(e)) from e

    oid = order.get("id")
    if not oid:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, detail="Invalid Razorpay response")

    pay = BillingPayment(
        business_id=business_id,
        razorpay_order_id=str(oid),
        amount_paise=amount,
        currency="INR",
        status="created",
        idempotency_key=idem,
        meta=notes,
    )
    db.add(pay)
    await db.commit()

    await log_usage(
        db,
        provider="razorpay",
        action="order_created",
        business_id=business_id,
        meta={"order_id": oid, "amount_paise": amount},
    )

    return CreateOrderOut(
        order_id=str(oid),
        amount_paise=amount,
        currency="INR",
        key_id=kid,
        business_id=str(business_id),
        idempotency_key=idem,
    )


@router.post("/verify")
async def billing_verify(
    business_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    body: VerifyBody,
):
    _, secret, _ = await effective_razorpay_keys(settings, db)
    if not secret:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, detail="Razorpay secret not configured")

    r = await db.execute(
        select(BillingPayment).where(
            BillingPayment.business_id == business_id,
            BillingPayment.razorpay_order_id == body.razorpay_order_id,
        )
    )
    pay = r.scalar_one_or_none()
    if not pay:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Order not found for this business")

    if pay.status == "paid":
        return {"ok": True, "already_verified": True, "business_id": str(business_id)}

    if not verify_payment_signature(
        body.razorpay_order_id, body.razorpay_payment_id, body.razorpay_signature, secret
    ):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid payment signature")

    now = datetime.now(timezone.utc)
    pay.status = "paid"
    pay.razorpay_payment_id = body.razorpay_payment_id
    pay.paid_at = now

    meta = pay.meta or {}
    sub = await ensure_subscription_row(db, business_id)
    sub.plan_code = str(meta.get("plan_code") or sub.plan_code)
    sub.whatsapp_addon = bool(meta.get("whatsapp_addon"))
    sub.ai_addon = bool(meta.get("ai_addon"))
    sub.status = "active"
    sub.monthly_base_paise = settings.billing_cloud_infra_paise
    sub.monthly_addons_paise = settings.billing_whatsapp_ai_addon_paise if (sub.whatsapp_addon or sub.ai_addon) else 0
    sub.current_period_start = now
    sub.current_period_end = now + timedelta(days=30)
    sub.updated_at = now

    await db.commit()

    await log_usage(
        db,
        provider="razorpay",
        action="payment_verified",
        business_id=business_id,
        meta={"payment_id": body.razorpay_payment_id, "order_id": body.razorpay_order_id},
    )

    return {"ok": True, "already_verified": False, "business_id": str(business_id)}
