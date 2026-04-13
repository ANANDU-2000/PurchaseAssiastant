"""Optional outbound WhatsApp via Authkey.io (when AUTHKEY_API_KEY is set)."""

from __future__ import annotations

import logging
from typing import Any

import httpx

from app.config import Settings

logger = logging.getLogger(__name__)


def _normalize_in_phone(raw: str) -> str:
    d = "".join(c for c in raw if c.isdigit())
    if len(d) == 10:
        return "91" + d
    return d


async def send_whatsapp_authkey(
    settings: Settings,
    *,
    to_e164_digits: str,
    body: str,
) -> dict[str, Any] | None:
    """
    Best-effort POST to Authkey dashboard API. Endpoint shape may vary by BSP —
    adjust `authkey_base_url` or extend payload after verifying their docs.
    """
    key = (settings.authkey_api_key or "").strip()
    if not key:
        return None
    phone = _normalize_in_phone(to_e164_digits)
    base = settings.authkey_base_url.rstrip("/")
    url = f"{base}/api/whatsapp/send"
    payload = {
        "mobile": phone,
        "msg": body[:4096],
        "authkey": key,
        "sender": settings.authkey_sender_label,
    }
    if (settings.authkey_from_number or "").strip():
        payload["from"] = settings.authkey_from_number.strip()
    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            res = await client.post(url, json=payload)
            if res.status_code >= 400:
                logger.warning("authkey send failed %s: %s", res.status_code, res.text[:300])
                return {"error": res.text, "status": res.status_code}
            try:
                return res.json()
            except Exception:  # noqa: BLE001
                return {"ok": True, "raw": res.text[:200]}
    except Exception as e:  # noqa: BLE001
        logger.exception("authkey send error: %s", e)
        return {"error": str(e)}
