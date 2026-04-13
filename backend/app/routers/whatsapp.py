import hashlib
import hmac
import json
import logging
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.services.platform_credentials import effective_dialog360
from app.services.webhook_rate_limit import allow as webhook_rate_allow
from app.services.whatsapp_flow import handle_inbound_text
from app.services.whatsapp_state import idempotent_message

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/webhooks", tags=["whatsapp"])


def _verify_signature(raw_body: bytes, secret: str, header_value: str | None) -> bool:
    if not header_value:
        return False
    expected = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
    got = header_value.strip()
    if got.lower().startswith("sha256="):
        got = got.split("=", 1)[1].strip()
    return hmac.compare_digest(expected, got)


def _extract_messages(payload: dict[str, Any]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for ent in payload.get("entry") or []:
        for ch in ent.get("changes") or []:
            val = ch.get("value") or {}
            for m in val.get("messages") or []:
                out.append(m)
    return out


@router.post("/whatsapp/360dialog")
async def whatsapp_webhook(
    request: Request,
    settings: Settings = Depends(get_settings),
    db: AsyncSession = Depends(get_db),
):
    """
    360dialog / WhatsApp Cloud webhook.
    When DIALOG360_WEBHOOK_SECRET is set, requires X-Webhook-Signature (or X-Signature)
    to equal HMAC-SHA256(raw_body, secret) as lowercase hex.
    """
    raw = await request.body()
    _, _, _, wh_secret = await effective_dialog360(settings, db)
    if wh_secret:
        sig = request.headers.get("X-Webhook-Signature") or request.headers.get("X-Signature")
        if not _verify_signature(raw, wh_secret, sig):
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid webhook signature")

    try:
        payload = json.loads(raw.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        payload = {}

    if not isinstance(payload, dict):
        return {"ok": True, "handled": False}

    # Hub challenge for verification GET is not handled here (360dialog uses POST for events)
    messages = _extract_messages(payload)
    results: list[dict[str, Any]] = []

    for msg in messages:
        if msg.get("type") != "text":
            continue
        phone = msg.get("from")
        mid = msg.get("id")
        body = (msg.get("text") or {}).get("body")
        if not phone:
            continue

        first = await idempotent_message(settings, mid)
        if not first:
            results.append({"duplicate": True, "id": mid})
            continue

        try:
            res = await handle_inbound_text(
                settings=settings,
                db=db,
                phone_from=str(phone),
                text=str(body) if body is not None else None,
                message_id=str(mid) if mid else None,
            )
            results.append(res)
        except Exception as e:  # noqa: BLE001
            logger.exception("WhatsApp handle failed: %s", e)
            results.append({"ok": False, "error": str(e)})

    return {"ok": True, "processed": len(results), "results": results}


@router.post("/whatsapp/authkey")
async def whatsapp_authkey_webhook(
    request: Request,
    settings: Settings = Depends(get_settings),
    db: AsyncSession = Depends(get_db),
):
    """
    Authkey.io (or compatible) inbound JSON. Expected keys: `mobile`, `message` (text).
    Optional: `id` for idempotency. Rate-limited per phone (in-process; use Redis in multi-worker).
    """
    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001
        payload = {}
    if not isinstance(payload, dict):
        return {"ok": False, "error": "invalid_json"}

    phone = str(payload.get("mobile") or payload.get("from") or "").strip()
    body = payload.get("message") or payload.get("text") or payload.get("body")
    mid = payload.get("id") or payload.get("message_id")

    if not phone:
        return {"ok": False, "error": "missing_mobile"}

    if not webhook_rate_allow(f"authkey:{phone}", max_per_hour=120):
        return {"ok": False, "error": "rate_limited"}

    if mid:
        first = await idempotent_message(settings, str(mid))
        if not first:
            return {"ok": True, "duplicate": True}

    try:
        res = await handle_inbound_text(
            settings=settings,
            db=db,
            phone_from=phone,
            text=str(body) if body is not None else None,
            message_id=str(mid) if mid else None,
        )
        return {"ok": True, "result": res}
    except Exception as e:  # noqa: BLE001
        logger.exception("Authkey webhook handle failed: %s", e)
        return {"ok": False, "error": str(e)}
