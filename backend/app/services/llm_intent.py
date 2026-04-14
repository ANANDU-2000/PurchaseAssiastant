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

_INTENT_JSON_INSTRUCTIONS = """You are Harisree Purchase Assistant. Classify the user message and extract fields.

Return ONE JSON object only (no markdown) with exactly these keys:
- "intent": one of:
  - "create_entry" — record a purchase (qty, prices, item, supplier, …)
  - "create_supplier" — new supplier (needs supplier_name or name)
  - "create_category" — new top-level category only (category_name or name)
  - "create_category_item" — category + first catalog item / "type" line, e.g. Rice → Biriyani (needs category_name and item_name)
  - "create_catalog_item" — new item under existing category (needs item_name or name, and category_name)
  - "create_variant" — variant under an item (variant_name, item_name)
  - "update_entry", "delete_entry", "query_summary"
- "data": object — include only relevant keys; use null for unknown (never guess numbers):
  For purchases: item, variant, unit_type, bags, kg_per_bag, qty_kg, buy_price, landing_cost, selling_price_per_kg, broker, supplier, supplier_name, …
  For entities: supplier_name, name, category_name, item_name, variant_name, default_unit, kg_per_bag
- "missing_fields": array of strings for required fields still unknown
- "reply_text": one short sentence if you need to clarify; else a neutral note

Rules: Do not invent prices or quantities. Prefer create_category_item when the user gives "category X > Y" or "X under Y" for types. Short replies."""


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

STRICT_WHATSAPP_LLM_PREFIX = """STRICT MODE (mandatory):
- Never invent, guess, or round numbers, quantities, prices, dates, supplier names, or item names.
- Copy numeric values from the user message exactly into JSON fields; use null only when absent.
- Never change intent to match a guess; use out_of_scope or missing_fields when unclear.
- You do not write to the database; the server validates and may reject saves.

"""

WHATSAPP_TRANSACTIONAL_INSTRUCTIONS = (
    STRICT_WHATSAPP_LLM_PREFIX
    + """You are Harisree Purchase Assistant for WhatsApp. Output ONE JSON object only (no markdown).

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
)


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


_WHATSAPP_FACTS_SYSTEM = (
    STRICT_WHATSAPP_LLM_PREFIX
    + """You are Harisree Purchase Assistant on WhatsApp.
The user's message asks about their purchase business. A FACTS block was computed by Harisree's server from their database — it is the only source of truth for numbers and names.
Write a short reply (max ~650 characters) in plain text for WhatsApp. Use ₹ for rupees.
Copy every amount exactly from FACTS; never change digits. If FACTS are a help / hint message with suggested commands, keep that guidance.
You may tighten wording; match English or a short mix if the user did. No markdown, no bullet stars."""
)


def _extract_openai_style_plain_text(data: dict[str, Any]) -> str | None:
    try:
        t = data["choices"][0]["message"]["content"]
        if isinstance(t, str) and t.strip():
            return t.strip()
    except (KeyError, IndexError, TypeError):
        pass
    return None


async def synthesize_whatsapp_plain_chat(
    *,
    system_prompt: str,
    user_content: str,
    settings: Settings,
    db: AsyncSession,
) -> str | None:
    """
    Generic plain-text completion for WhatsApp (no JSON). Same provider routing as intent parsing.
    Returns None if stub, missing key, or API error.
    """
    prov = (settings.ai_provider or "stub").strip().lower()
    if prov == "stub":
        return None

    uc = (user_content or "").strip()[:8000]
    if not uc:
        return None
    sys_p = (system_prompt or "").strip()[:12000]
    if not sys_p:
        return None

    if prov == "openai":
        key = await effective_openai_key(settings, db)
        if not key:
            return None
        payload = {
            "model": settings.openai_model_summary or settings.openai_model_parse,
            "max_tokens": 450,
            "messages": [
                {"role": "system", "content": sys_p},
                {"role": "user", "content": uc},
            ],
        }
        async with httpx.AsyncClient(timeout=60.0) as client:
            res = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                json=payload,
            )
            if res.status_code >= 400:
                logger.warning("OpenAI plain chat failed %s", res.status_code)
                return None
            return _finalize_whatsapp_reply(_extract_openai_style_plain_text(res.json()))

    if prov == "groq":
        key = await effective_groq_key(settings, db)
        if not key:
            return None
        payload = {
            "model": settings.groq_model,
            "max_tokens": 450,
            "messages": [
                {"role": "system", "content": sys_p},
                {"role": "user", "content": uc},
            ],
        }
        async with httpx.AsyncClient(timeout=60.0) as client:
            res = await client.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
                json=payload,
            )
            if res.status_code >= 400:
                logger.warning("Groq plain chat failed %s", res.status_code)
                return None
            return _finalize_whatsapp_reply(_extract_openai_style_plain_text(res.json()))

    if prov == "gemini":
        key = await effective_google_ai_key(settings, db)
        if not key:
            return None
        model = settings.gemini_model.strip()
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        body = {
            "systemInstruction": {"parts": [{"text": sys_p}]},
            "contents": [{"parts": [{"text": uc}]}],
            "generationConfig": {"maxOutputTokens": 450, "temperature": 0.35},
        }
        async with httpx.AsyncClient(timeout=60.0) as client:
            res = await client.post(url, params={"key": key}, json=body)
            if res.status_code >= 400:
                logger.warning("Gemini plain chat failed %s", res.status_code)
                return None
            outer = res.json()
        try:
            raw_text = outer["candidates"][0]["content"]["parts"][0]["text"]
            if isinstance(raw_text, str) and raw_text.strip():
                return _finalize_whatsapp_reply(raw_text.strip())
        except (KeyError, IndexError, TypeError):
            pass
        return None

    return None


async def synthesize_whatsapp_facts_reply(
    *,
    user_text: str,
    facts_text: str,
    settings: Settings,
    db: AsyncSession,
) -> str | None:
    """
    Optional natural-language layer on top of deterministic query reports.
    Uses the same AI_PROVIDER + keys as transactional JSON parsing. Returns None on failure / stub.
    """
    ut = user_text.strip()[:2000]
    facts = (facts_text or "").strip()[:6000]
    if not facts:
        return None
    user_block = f"USER MESSAGE:\n{ut}\n\nFACTS (from Harisree database):\n{facts}"
    return await synthesize_whatsapp_plain_chat(
        system_prompt=_WHATSAPP_FACTS_SYSTEM,
        user_content=user_block,
        settings=settings,
        db=db,
    )


def _finalize_whatsapp_reply(text: str | None) -> str | None:
    if not text:
        return None
    t = text.strip()
    if not t:
        return None
    # WhatsApp message max 4096; keep headroom
    if len(t) > 3900:
        t = t[:3897] + "..."
    return t
