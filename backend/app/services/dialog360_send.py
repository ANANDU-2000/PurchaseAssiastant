"""Outbound WhatsApp text via 360dialog Cloud API (when API key + phone_number_id are set)."""

from __future__ import annotations

import logging
from typing import Any

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.services.authkey_send import send_whatsapp_authkey
from app.services.platform_credentials import effective_dialog360

logger = logging.getLogger(__name__)


async def send_text_message(
    settings: Settings,
    db: AsyncSession | None,
    *,
    to_e164: str,
    body: str,
) -> dict[str, Any] | None:
    """
    Send a plain text message. `to_e164` should be digits only (e.g. 9198...).
    Credentials: database row `platform_integration` overrides process env — no redeploy.
    If Authkey is configured, it takes precedence for outbound text.
    If 360dialog is not configured, logs and returns None (dev mode).
    """
    if (settings.authkey_api_key or "").strip():
        return await send_whatsapp_authkey(
            settings, to_e164_digits=to_e164, body=body
        )

    api_key, phone_id, base_url, _ = await effective_dialog360(settings, db)
    if not api_key or not phone_id:
        logger.info("360dialog not configured; outbound WA: %s", body[:500])
        return None

    url = f"{base_url}/{phone_id}/messages"
    headers = {"D360-API-KEY": api_key, "Content-Type": "application/json"}
    payload: dict[str, Any] = {
        "messaging_product": "whatsapp",
        "recipient_type": "individual",
        "to": to_e164,
        "type": "text",
        "text": {"preview_url": False, "body": body[:4096]},
    }
    async with httpx.AsyncClient(timeout=30.0) as client:
        res = await client.post(url, headers=headers, json=payload)
        if res.status_code >= 400:
            logger.warning("360dialog send failed %s: %s", res.status_code, res.text[:500])
            return {"error": res.text, "status": res.status_code}
        try:
            return res.json()
        except Exception:  # noqa: BLE001
            return {"ok": True, "raw": res.text[:200]}
