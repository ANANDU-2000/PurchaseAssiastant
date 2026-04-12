"""Razorpay webhook: idempotent payment.captured handling."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.models import BillingPayment, WebhookEventLog
from app.services.billing_entitlements import ensure_subscription_row
from app.services.platform_credentials import effective_razorpay_keys
from app.services.razorpay_service import parse_webhook_json, verify_webhook_signature
from app.services.usage_logging import log_usage

router = APIRouter(prefix="/v1/integrations/razorpay", tags=["integrations"])


@router.post("/webhook")
async def razorpay_webhook(
    request: Request,
    db: AsyncSession = Depends(get_db),
    settings: Settings = Depends(get_settings),
):
    raw = await request.body()
    sig = request.headers.get("X-Razorpay-Signature")
    _, _, wh_secret = await effective_razorpay_keys(settings, db)
    if wh_secret and not verify_webhook_signature(raw, wh_secret, sig):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid webhook signature")

    payload = parse_webhook_json(raw)
    event = payload.get("event") or ""
    eid = str(payload.get("id") or "").strip()
    if eid:
        existing = await db.execute(select(WebhookEventLog).where(WebhookEventLog.id == eid))
        if existing.scalar_one_or_none():
            return {"ok": True, "duplicate": True}

    ent = payload.get("payload") or {}
    payment_obj: dict = ent.get("payment") if isinstance(ent.get("payment"), dict) else ent
    if not isinstance(payment_obj, dict):
        payment_obj = {}

    order_id = payment_obj.get("order_id")
    pay_id = payment_obj.get("id")

    if event == "payment.captured" and order_id:
        r = await db.execute(select(BillingPayment).where(BillingPayment.razorpay_order_id == str(order_id)))
        pay = r.scalar_one_or_none()
        bid = None
        if pay and pay.status != "paid":
            now = datetime.now(timezone.utc)
            pay.status = "paid"
            if pay_id:
                pay.razorpay_payment_id = str(pay_id)
            pay.paid_at = now
            meta = pay.meta or {}
            sub = await ensure_subscription_row(db, pay.business_id)
            sub.plan_code = str(meta.get("plan_code") or sub.plan_code)
            sub.whatsapp_addon = bool(meta.get("whatsapp_addon"))
            sub.ai_addon = bool(meta.get("ai_addon"))
            sub.status = "active"
            sub.monthly_base_paise = settings.billing_cloud_infra_paise
            sub.monthly_addons_paise = (
                settings.billing_whatsapp_ai_addon_paise if (sub.whatsapp_addon or sub.ai_addon) else 0
            )
            sub.current_period_start = now
            sub.current_period_end = now + timedelta(days=30)
            sub.updated_at = now
            bid = pay.business_id
        elif pay:
            bid = pay.business_id

        if eid:
            db.add(WebhookEventLog(id=eid, provider="razorpay", payload_preview=str(order_id)[:120]))
        await db.commit()
        await log_usage(
            db,
            provider="razorpay",
            action="webhook_payment_captured",
            business_id=bid,
            meta={"order_id": str(order_id), "event": event},
        )
        return {"ok": True, "handled": True}

    if eid:
        db.add(WebhookEventLog(id=eid, provider="razorpay", payload_preview=str(event)[:120]))
        await db.commit()
    return {"ok": True, "handled": False, "event": event}
