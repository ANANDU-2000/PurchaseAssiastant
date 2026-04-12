"""Razorpay Orders API + payment signature verification."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
from typing import Any

import httpx

from app.config import Settings
from app.services.platform_credentials import effective_razorpay_keys

logger = logging.getLogger(__name__)

RAZORPAY_API = "https://api.razorpay.com/v1"


def _basic_auth(key_id: str, key_secret: str) -> str:
    raw = f"{key_id}:{key_secret}".encode("utf-8")
    return "Basic " + base64.b64encode(raw).decode("ascii")


async def create_order(
    *,
    settings: Settings,
    db,
    amount_paise: int,
    receipt: str,
    notes: dict[str, Any] | None = None,
) -> dict[str, Any]:
    kid, secret, _ = await effective_razorpay_keys(settings, db)
    if not kid or not secret:
        raise ValueError("Razorpay keys not configured")
    payload = {
        "amount": amount_paise,
        "currency": "INR",
        "receipt": receipt[:40],
        "payment_capture": 1,
        "notes": notes or {},
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        res = await client.post(
            f"{RAZORPAY_API}/orders",
            headers={
                "Authorization": _basic_auth(kid, secret),
                "Content-Type": "application/json",
            },
            json=payload,
        )
        if res.status_code >= 400:
            logger.warning("Razorpay create_order failed %s: %s", res.status_code, res.text[:500])
            raise ValueError(res.text)
        return res.json()


def verify_payment_signature(order_id: str, payment_id: str, signature: str, key_secret: str) -> bool:
    msg = f"{order_id}|{payment_id}".encode("utf-8")
    expected = hmac.new(key_secret.encode("utf-8"), msg, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature.strip())


def verify_webhook_signature(raw_body: bytes, webhook_secret: str, header_value: str | None) -> bool:
    if not header_value or not webhook_secret:
        return False
    expected = hmac.new(webhook_secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
    got = header_value.strip()
    return hmac.compare_digest(expected, got)


def parse_webhook_json(raw: bytes) -> dict[str, Any]:
    try:
        data = json.loads(raw.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}
