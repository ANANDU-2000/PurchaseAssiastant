from __future__ import annotations

import logging
from typing import Any

import requests

from app.config import Settings

logger = logging.getLogger(__name__)


def _digits_only(s: str) -> str:
    return "".join(c for c in (s or "") if c.isdigit())


def send_whatsapp_cloud_text(
    settings: Settings,
    *,
    to_e164: str,
    body: str,
) -> dict[str, Any]:
    """
    WhatsApp Cloud API: send a plain text message.

    Requires:
    - settings.whatsapp_cloud_access_token
    - settings.whatsapp_cloud_phone_number_id
    """
    token = (settings.whatsapp_cloud_access_token or "").strip()
    phone_id = (settings.whatsapp_cloud_phone_number_id or "").strip()
    if not token or not phone_id:
        return {"ok": False, "error": "whatsapp_cloud_not_configured"}

    to_digits = _digits_only(to_e164)
    if len(to_digits) < 10:
        return {"ok": False, "error": "invalid_to_number"}

    url = f"https://graph.facebook.com/v21.0/{phone_id}/messages"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    payload = {
        "messaging_product": "whatsapp",
        "to": to_digits,
        "type": "text",
        "text": {"body": body},
    }
    try:
        r = requests.post(url, headers=headers, json=payload, timeout=15)
        if r.status_code >= 400:
            logger.warning("wa_cloud_send failed status=%s body=%s", r.status_code, r.text[:300])
            return {"ok": False, "status": r.status_code, "error": r.text[:500]}
        return {"ok": True, "status": r.status_code, "data": r.json()}
    except Exception as e:  # noqa: BLE001
        logger.warning("wa_cloud_send exception=%s", type(e).__name__)
        return {"ok": False, "error": f"{type(e).__name__}: {e}"}

