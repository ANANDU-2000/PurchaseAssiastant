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
from app.services.webhook_rate_limit import allow_whatsapp_inbound
from app.services.whatsapp_flow import handle_inbound_nontext, handle_inbound_text
from app.services.whatsapp_state import idempotent_message

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1/webhooks", tags=["whatsapp"])


def _authkey_inbound_phone(payload: dict[str, Any]) -> str:
    return str(
        payload.get("mobile")
        or payload.get("Mobile")
        or payload.get("from")
        or payload.get("From")
        or ""
    ).strip()


def _authkey_inbound_message_text(payload: dict[str, Any]) -> Any | None:
    """Authkey may use `msg` (matches outbound) or query-string params per their webhook UI."""
    return (
        payload.get("message")
        or payload.get("Message")
        or payload.get("text")
        or payload.get("body")
        or payload.get("msg")
        or payload.get("content")
    )


def _phone_tail(phone: str, n: int = 4) -> str:
    d = "".join(c for c in phone if c.isdigit())
    if len(d) >= n:
        return d[-n:]
    return d if d else "?"


def _log_authkey_result(phone: str, payload: dict[str, Any]) -> None:
    """Structured INFO log for operations (phone = last 4 digits only)."""
    suf = _phone_tail(phone)
    if payload.get("duplicate"):
        logger.info("whatsapp_authkey phone_tail=%s duplicate=true", suf)
        return
    err = payload.get("error")
    if err:
        logger.info("whatsapp_authkey phone_tail=%s error=%s", suf, err)
        return
    inner = payload.get("result")
    if not isinstance(inner, dict):
        logger.info("whatsapp_authkey phone_tail=%s ok=%s", suf, payload.get("ok"))
        return
    handled = inner.get("handled")
    reason = inner.get("reason")
    tags = [k for k in ("query", "preview", "saved", "out_of_scope", "low_confidence", "missing") if inner.get(k)]
    tag_s = ",".join(tags) if tags else "-"
    logger.info(
        "whatsapp_authkey phone_tail=%s handled=%s reason=%s tags=%s",
        suf,
        handled,
        reason or "-",
        tag_s,
    )


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
        phone = msg.get("from")
        mid = msg.get("id")
        mtype = str(msg.get("type") or "text").strip().lower()
        if not phone:
            continue

        first = await idempotent_message(settings, mid)
        if not first:
            results.append({"duplicate": True, "id": mid})
            continue

        try:
            if mtype == "text":
                body = (msg.get("text") or {}).get("body")
                res = await handle_inbound_text(
                    settings=settings,
                    db=db,
                    phone_from=str(phone),
                    text=str(body) if body is not None else None,
                    message_id=str(mid) if mid else None,
                )
            elif mtype in ("audio", "image", "document", "video", "sticker"):
                res = await handle_inbound_nontext(
                    settings=settings,
                    db=db,
                    phone_from=str(phone),
                    kind=mtype,
                    message_id=str(mid) if mid else None,
                )
            else:
                res = {"ok": True, "handled": False, "reason": f"unsupported_type:{mtype}"}
            results.append(res)
        except Exception as e:  # noqa: BLE001
            logger.exception("WhatsApp handle failed: %s", e)
            results.append({"ok": False, "error": "internal_error"})

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

    Configure in Authkey dashboard: POST to `https://<API_HOST>/v1/webhooks/whatsapp/authkey`.
    Verify deployment with GET `/health` on the same host.

    Optional: set `AUTHKEY_WEBHOOK_SECRET` on the API and send the same value in header
    `X-Authkey-Webhook-Secret` (or `X-Webhook-Secret`) from Authkey if supported.
    """
    wh_secret = (settings.authkey_webhook_secret or "").strip()
    if wh_secret:
        got = request.headers.get("X-Authkey-Webhook-Secret") or request.headers.get(
            "X-Webhook-Secret"
        )
        if got != wh_secret:
            logger.warning("whatsapp_authkey rejected: invalid webhook secret")
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid webhook secret")

    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001
        payload = {}
    if not isinstance(payload, dict):
        logger.info("whatsapp_authkey phone_tail=? error=invalid_json")
        return {"ok": False, "error": "invalid_json"}

    q = request.query_params
    merged: dict[str, Any] = {**payload}
    # Authkey may append Mobile / message fields as query parameters (see dashboard hint).
    for key in ("mobile", "Mobile", "from", "From", "message", "Message", "msg", "text", "body", "id", "message_id"):
        if key in q and (merged.get(key) in (None, "")):
            merged[key] = q.get(key)

    phone = _authkey_inbound_phone(merged)
    body = _authkey_inbound_message_text(merged)
    mid = merged.get("id") or merged.get("message_id") or q.get("id") or q.get("Log_ID") or q.get("log_id")

    if not phone:
        logger.info("whatsapp_authkey phone_tail=? error=missing_mobile")
        return {"ok": False, "error": "missing_mobile"}

    if body is None or (isinstance(body, str) and not str(body).strip()):
        logger.info(
            "whatsapp_authkey phone_tail=%s warn=empty_message_json_keys=%s",
            _phone_tail(phone),
            sorted({str(k) for k in merged.keys()})[:20],
        )

    if not allow_whatsapp_inbound(
        f"authkey:{phone}",
        max_per_minute=settings.webhook_max_per_minute,
        max_per_hour=settings.webhook_max_per_hour,
    ):
        logger.info("whatsapp_authkey phone_tail=%s error=rate_limited", _phone_tail(phone))
        return {"ok": False, "error": "rate_limited"}

    if mid:
        first = await idempotent_message(settings, str(mid))
        if not first:
            out: dict[str, Any] = {"ok": True, "duplicate": True}
            _log_authkey_result(phone, out)
            return out

    try:
        res = await handle_inbound_text(
            settings=settings,
            db=db,
            phone_from=phone,
            text=str(body) if body is not None else None,
            message_id=str(mid) if mid else None,
        )
        out = {"ok": True, "result": res}
        _log_authkey_result(phone, out)
        return out
    except Exception as e:  # noqa: BLE001
        logger.exception("Authkey webhook handle failed: %s", e)
        logger.info("whatsapp_authkey phone_tail=%s error=internal_error", _phone_tail(phone))
        return {"ok": False, "error": "internal_error"}
