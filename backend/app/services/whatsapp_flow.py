"""Inbound WhatsApp message handling: transactional engine, Redis state, entitlements."""

from __future__ import annotations

import uuid
from typing import Any

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.models import Membership, User
from app.services.billing_entitlements import assert_whatsapp_entitled
from app.services.feature_flags import is_whatsapp_bot_enabled
from app.services.whatsapp_notify import in_quiet_hours_ist, send_guarded_whatsapp
from app.services.whatsapp_state import reset_consecutive_replies
from app.services.whatsapp_transaction_engine import handle_transactional_message


def _digits(p: str) -> str:
    return "".join(c for c in p if c.isdigit())


async def find_user_by_chat_phone(db: AsyncSession, phone_from_provider: str) -> User | None:
    """Match WhatsApp `from` to a User.phone (digits / +prefix tolerant)."""
    d = _digits(phone_from_provider)
    if not d:
        return None
    r = await db.execute(select(User))
    for u in r.scalars().all():
        ud = _digits(u.phone)
        if ud == d or (len(d) >= 10 and ud.endswith(d[-10:])):
            return u
    return None


async def primary_business_id(db: AsyncSession, user_id: uuid.UUID) -> uuid.UUID | None:
    q = await db.execute(
        select(Membership.business_id)
        .where(Membership.user_id == user_id)
        .order_by(Membership.created_at.asc())
        .limit(1)
    )
    row = q.first()
    return row[0] if row else None


async def handle_inbound_nontext(
    *,
    settings: Settings,
    db: AsyncSession,
    phone_from: str,
    kind: str,
    message_id: str | None,
) -> dict[str, Any]:
    """
    Voice / image / PDF — no auto-save. When STT/OCR are wired, feed transcript into the same
    transactional engine as text (preview + YES required).
    """
    del message_id
    to_digits = _digits(phone_from)
    if in_quiet_hours_ist():
        return {"ok": True, "handled": False, "reason": "quiet_hours"}

    await reset_consecutive_replies(settings, to_digits)

    user = await find_user_by_chat_phone(db, phone_from)
    if user is None:
        await send_guarded_whatsapp(
            settings,
            db,
            to_e164=to_digits,
            body="This WhatsApp number is not linked to a Harisree account. Sign in with the same phone in the app first.",
        )
        return {"ok": True, "handled": True, "reason": "unknown_user"}

    biz = await primary_business_id(db, user.id)
    if biz is None:
        await send_guarded_whatsapp(
            settings,
            db,
            to_e164=to_digits,
            body="No business workspace found. Open the Harisree app to finish setup.",
        )
        return {"ok": True, "handled": True, "reason": "no_business"}

    try:
        await assert_whatsapp_entitled(db, biz, settings)
    except HTTPException as e:
        await send_guarded_whatsapp(
            settings,
            db,
            to_e164=to_digits,
            body=str(e.detail),
        )
        return {"ok": True, "handled": True, "reason": "whatsapp_billing"}

    if not await is_whatsapp_bot_enabled(db, settings):
        await send_guarded_whatsapp(
            settings,
            db,
            to_e164=to_digits,
            body="Harisree WhatsApp automation is turned off for this server. Use the mobile app or ask your admin to re-enable the bot.",
        )
        return {"ok": True, "handled": True, "reason": "whatsapp_bot_disabled"}

    labels = {
        "audio": "Voice notes",
        "image": "Photos",
        "document": "PDFs / documents",
        "video": "Videos",
        "sticker": "Stickers",
    }
    label = labels.get(kind, "This attachment type")

    await send_guarded_whatsapp(
        settings,
        db,
        to_e164=to_digits,
        body=(
            f"{label} are not auto-saved (preview + YES required for every purchase).\n\n"
            "Send a *text* draft:\n"
            "item: …\n"
            "qty: …\n"
            "unit: kg|box|piece\n"
            "buy: …\n"
            "land: …\n"
            "date: YYYY-MM-DD (optional)\n\n"
            "Or open the Harisree app → Add purchase.\n"
            "_When voice/image tools are enabled for your workspace, they will use the same confirm flow._"
        ),
    )
    return {"ok": True, "handled": True, "nontext": kind}


async def handle_inbound_text(
    *,
    settings: Settings,
    db: AsyncSession,
    phone_from: str,
    text: str | None,
    message_id: str | None,
) -> dict[str, Any]:
    """Main handler after signature verification and JSON parse."""
    del message_id
    to_digits = _digits(phone_from)
    if not text:
        return {"ok": True, "handled": False, "reason": "no_text"}

    if in_quiet_hours_ist():
        return {"ok": True, "handled": False, "reason": "quiet_hours"}

    await reset_consecutive_replies(settings, to_digits)

    user = await find_user_by_chat_phone(db, phone_from)
    if user is None:
        await send_guarded_whatsapp(
            settings,
            db,
            to_e164=to_digits,
            body="This WhatsApp number is not linked to a Harisree account. Sign in with the same phone in the app first.",
        )
        return {"ok": True, "handled": True, "reason": "unknown_user"}

    biz = await primary_business_id(db, user.id)
    if biz is None:
        await send_guarded_whatsapp(
            settings,
            db,
            to_e164=to_digits,
            body="No business workspace found. Open the Harisree app to finish setup.",
        )
        return {"ok": True, "handled": True, "reason": "no_business"}

    try:
        await assert_whatsapp_entitled(db, biz, settings)
    except HTTPException as e:
        await send_guarded_whatsapp(
            settings,
            db,
            to_e164=to_digits,
            body=str(e.detail),
        )
        return {"ok": True, "handled": True, "reason": "whatsapp_billing"}

    if not await is_whatsapp_bot_enabled(db, settings):
        await send_guarded_whatsapp(
            settings,
            db,
            to_e164=to_digits,
            body="Harisree WhatsApp automation is turned off for this server. Use the mobile app or ask your admin to re-enable the bot.",
        )
        return {"ok": True, "handled": True, "reason": "whatsapp_bot_disabled"}

    return await handle_transactional_message(
        settings=settings,
        db=db,
        phone_digits=to_digits,
        text=text,
        user=user,
        business_id=biz,
    )


# Back-compat for tests — prefer `parse_multiline_entry_create_request` in new code.
def _parse_entry_text(text: str):
    from app.services.whatsapp_legacy_entry_parse import parse_multiline_entry_create_request

    return parse_multiline_entry_create_request(text)
