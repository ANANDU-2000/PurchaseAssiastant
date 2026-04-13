"""Optional LLM-backed intent JSON extraction (OpenAI / Groq / Gemini). Falls back to caller on error."""

from __future__ import annotations

import json
import logging
from typing import Any

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.services.platform_credentials import (
    effective_google_ai_key,
    effective_groq_key,
    effective_openai_key,
)

logger = logging.getLogger(__name__)

_INTENT_JSON_INSTRUCTIONS = """You are Harisree Purchase Assistant. Extract fields from the user's message for a purchase entry.
Return ONE JSON object only (no markdown) with exactly these keys:
- "intent": one of "create_entry", "update_entry", "delete_entry", "query_summary"
- "data": object with keys: item, variant, unit_type, bags, kg_per_bag, qty_kg, purchase_price_per_bag, landed_cost_per_bag, selling_price_per_kg, transport, loading, broker, broker_percent, supplier, location — use JSON null for unknown (never guess numbers)
- "missing_fields": array of strings listing required fields still unknown
- "reply_text": one short helpful sentence for the user

Rules: Do not invent prices or quantities. If unclear, null and list in missing_fields."""


def _normalize_payload(raw: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    intent = raw.get("intent")
    data = raw.get("data")
    if not isinstance(intent, str) or not isinstance(data, dict):
        return None
    missing = raw.get("missing_fields")
    if missing is None:
        missing = []
    if not isinstance(missing, list):
        missing = []
    missing = [str(x) for x in missing if x is not None]
    reply = raw.get("reply_text")
    if not isinstance(reply, str):
        reply = "Review the extracted fields — nothing is saved until you confirm in the app."
    return {
        "intent": intent,
        "data": data,
        "missing_fields": missing,
        "reply_text": reply,
    }


async def extract_intent_json(
    *,
    user_text: str,
    settings: Settings,
    db: AsyncSession,
) -> dict[str, Any] | None:
    """Returns normalized dict or None if provider disabled / error."""
    prov = (settings.ai_provider or "stub").strip().lower()
    if prov == "stub":
        return None

    if prov == "openai":
        key = await effective_openai_key(settings, db)
        if not key:
            logger.warning("ai_provider=openai but no API key")
            return None
        return await _openai_json(user_text, settings, key)

    if prov == "groq":
        key = await effective_groq_key(settings, db)
        if not key:
            logger.warning("ai_provider=groq but no API key")
            return None
        return await _groq_json(user_text, settings, key)

    if prov == "gemini":
        key = await effective_google_ai_key(settings, db)
        if not key:
            logger.warning("ai_provider=gemini but no GOOGLE_AI / DB key")
            return None
        return await _gemini_json(user_text, settings, key)

    logger.warning("Unknown ai_provider=%s", prov)
    return None


async def _openai_json(text: str, settings: Settings, api_key: str) -> dict[str, Any] | None:
    payload = {
        "model": settings.openai_model_parse,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": _INTENT_JSON_INSTRUCTIONS},
            {"role": "user", "content": text[:8000]},
        ],
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        res = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            json=payload,
        )
        if res.status_code >= 400:
            logger.warning("OpenAI intent failed %s: %s", res.status_code, res.text[:400])
            return None
        data = res.json()
    return _parse_openai_style_response(data)


async def _groq_json(text: str, settings: Settings, api_key: str) -> dict[str, Any] | None:
    payload = {
        "model": settings.groq_model,
        "messages": [
            {"role": "system", "content": _INTENT_JSON_INSTRUCTIONS},
            {"role": "user", "content": text[:8000]},
        ],
        "response_format": {"type": "json_object"},
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        res = await client.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            json=payload,
        )
        if res.status_code >= 400:
            logger.warning("Groq intent failed %s: %s", res.status_code, res.text[:400])
            return None
        data = res.json()
    return _parse_openai_style_response(data)


def _parse_openai_style_response(data: dict[str, Any]) -> dict[str, Any] | None:
    try:
        content = data["choices"][0]["message"]["content"]
        raw = json.loads(content)
    except (KeyError, IndexError, json.JSONDecodeError, TypeError) as e:
        logger.warning("Bad LLM JSON: %s", e)
        return None
    return _normalize_payload(raw)


async def _gemini_json(text: str, settings: Settings, api_key: str) -> dict[str, Any] | None:
    model = settings.gemini_model.strip()
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    body = {
        "systemInstruction": {"parts": [{"text": _INTENT_JSON_INSTRUCTIONS}]},
        "contents": [{"parts": [{"text": text[:8000]}]}],
        "generationConfig": {"responseMimeType": "application/json"},
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        res = await client.post(url, params={"key": api_key}, json=body)
        if res.status_code >= 400:
            logger.warning("Gemini intent failed %s: %s", res.status_code, res.text[:400])
            return None
        outer = res.json()
    try:
        raw_text = outer["candidates"][0]["content"]["parts"][0]["text"]
        raw = json.loads(raw_text)
    except (KeyError, IndexError, json.JSONDecodeError, TypeError) as e:
        logger.warning("Bad Gemini JSON: %s", e)
        return None
    return _normalize_payload(raw)


# --- WhatsApp transactional assistant (strict JSON; AI parses only; backend validates) ---

WHATSAPP_TRANSACTIONAL_INSTRUCTIONS = """You are Harisree Purchase Assistant for WhatsApp. Output ONE JSON object only (no markdown).

Allowed intents ONLY:
- "create_entry" — record a purchase line
- "update_entry" — change an existing entry (usually last / by item+date)
- "create_supplier" — new supplier name (+ optional phone)
- "create_broker" — new broker (+ optional commission)
- "create_item" — new catalog item (needs category name if possible)
- "query" — profit / best supplier / summary for a date range
- "out_of_scope" — not purchase-related

JSON keys (exactly):
- "intent": one of the allowed values above
- "data": object — use null for unknowns, NEVER guess numbers. Example fields:
  item, qty, unit (kg|box|piece|bag), buy_price, landing_cost, selling_price, supplier_name, broker_name,
  entry_date (YYYY-MM-DD or null), date_range (today|week|month|mtd|null),
  update_scope (last|by_id|null), target_entry_id (string uuid or null),
  patch_buy, patch_land, patch_sell, patch_supplier_name, patch_broker_name,
  supplier_phone, broker_commission_flat, category_name for create_item
- "missing_fields": string[] — required fields still unknown
- "clarification_question": string or null — ONE short question if needed
- "confidence": number 0.0-1.0 — lower if Malayalam/English mixed or noisy
- "preview_hint": string — one-line human summary for preview (no calculations)

Rules:
- Do not invent prices, qty, or dates.
- Purchases need buy + landing at minimum for create_entry (or list missing_fields).
- If user chats about weather, news, jokes → intent out_of_scope.
"""


def _normalize_whatsapp_payload(raw: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    intent = raw.get("intent")
    data = raw.get("data")
    if not isinstance(intent, str) or not isinstance(data, dict):
        return None
    allowed = frozenset(
        {
            "create_entry",
            "update_entry",
            "create_supplier",
            "create_broker",
            "create_item",
            "query",
            "out_of_scope",
        }
    )
    if intent not in allowed:
        intent = "out_of_scope"
    missing = raw.get("missing_fields")
    if missing is None:
        missing = []
    if not isinstance(missing, list):
        missing = []
    missing = [str(x) for x in missing if x is not None]
    cq = raw.get("clarification_question")
    if cq is not None and not isinstance(cq, str):
        cq = None
    conf = raw.get("confidence")
    try:
        cfn = float(conf) if conf is not None else 0.6
    except (TypeError, ValueError):
        cfn = 0.6
    cfn = max(0.0, min(1.0, cfn))
    ph = raw.get("preview_hint")
    if ph is not None and not isinstance(ph, str):
        ph = None
    return {
        "intent": intent,
        "data": data,
        "missing_fields": missing,
        "clarification_question": cq,
        "confidence": cfn,
        "preview_hint": ph,
    }


def _parse_whatsapp_openai_style(data: dict[str, Any]) -> dict[str, Any] | None:
    try:
        content = data["choices"][0]["message"]["content"]
        raw = json.loads(content)
    except (KeyError, IndexError, json.JSONDecodeError, TypeError) as e:
        logger.warning("Bad WhatsApp LLM JSON: %s", e)
        return None
    return _normalize_whatsapp_payload(raw)


async def extract_whatsapp_transactional_json(
    *,
    user_text: str,
    settings: Settings,
    db: AsyncSession,
) -> dict[str, Any] | None:
    """Returns normalized WhatsApp transactional dict or None to use rule-based fallback."""
    prov = (settings.ai_provider or "stub").strip().lower()
    if prov == "stub":
        return None

    if prov == "openai":
        key = await effective_openai_key(settings, db)
        if not key:
            return None
        payload = {
            "model": settings.openai_model_parse,
            "response_format": {"type": "json_object"},
            "max_tokens": 400,
            "messages": [
                {"role": "system", "content": WHATSAPP_TRANSACTIONAL_INSTRUCTIONS},
                {"role": "user", "content": user_text[:8000]},
            ],
        }
        async with httpx.AsyncClient(timeout=60.0) as client:
            res = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                json=payload,
            )
            if res.status_code >= 400:
                logger.warning("OpenAI WhatsApp intent failed %s", res.status_code)
                return None
            return _parse_whatsapp_openai_style(res.json())

    if prov == "groq":
        key = await effective_groq_key(settings, db)
        if not key:
            return None
        payload = {
            "model": settings.groq_model,
            "messages": [
                {"role": "system", "content": WHATSAPP_TRANSACTIONAL_INSTRUCTIONS},
                {"role": "user", "content": user_text[:8000]},
            ],
            "response_format": {"type": "json_object"},
        }
        async with httpx.AsyncClient(timeout=60.0) as client:
            res = await client.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                json=payload,
            )
            if res.status_code >= 400:
                logger.warning("Groq WhatsApp intent failed %s", res.status_code)
                return None
            return _parse_whatsapp_openai_style(res.json())

    if prov == "gemini":
        key = await effective_google_ai_key(settings, db)
        if not key:
            return None
        model = settings.gemini_model.strip()
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        body = {
            "systemInstruction": {"parts": [{"text": WHATSAPP_TRANSACTIONAL_INSTRUCTIONS}]},
            "contents": [{"parts": [{"text": user_text[:8000]}]}],
            "generationConfig": {"responseMimeType": "application/json"},
        }
        async with httpx.AsyncClient(timeout=60.0) as client:
            res = await client.post(url, params={"key": key}, json=body)
            if res.status_code >= 400:
                return None
            outer = res.json()
        try:
            raw_text = outer["candidates"][0]["content"]["parts"][0]["text"]
            raw = json.loads(raw_text)
        except (KeyError, IndexError, json.JSONDecodeError, TypeError):
            return None
        return _normalize_whatsapp_payload(raw)

    return None
