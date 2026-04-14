"""Optional LLM-backed intent JSON extraction (OpenAI / Groq / Gemini). Falls back to caller on error."""

from __future__ import annotations

import json
import logging
from typing import Any

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.services.assistant_system_prompt import REPORT_SYSTEM_PROMPT, SYSTEM_PROMPT
from app.services.llm_failover import (
    any_llm_key,
    resolve_provider_keys,
    run_ordered_failover,
)
from app.services.platform_credentials import (
    effective_google_ai_key,
    effective_groq_key,
    effective_openai_key,
)

logger = logging.getLogger(__name__)

# Single source: app.services.assistant_system_prompt.SYSTEM_PROMPT
_INTENT_JSON_INSTRUCTIONS = SYSTEM_PROMPT


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


def _strip_markdown_json_fence(s: str) -> str:
    t = (s or "").strip()
    if not t.startswith("```"):
        return t
    lines = t.split("\n")
    if len(lines) >= 2:
        lines = lines[1:]
    if lines and lines[-1].strip().startswith("```"):
        lines = lines[:-1]
    return "\n".join(lines).strip()


def _parse_json_loose(raw: str) -> Any | None:
    """Parse JSON from LLM output; tolerate markdown fences and extra prose."""
    s = _strip_markdown_json_fence(raw)
    if not s:
        return None
    try:
        out = json.loads(s)
        return out
    except json.JSONDecodeError:
        pass
    i = s.find("{")
    j = s.rfind("}")
    if i >= 0 and j > i:
        try:
            return json.loads(s[i : j + 1])
        except json.JSONDecodeError:
            pass
    return None


def _intent_user_payload(
    user_text: str,
    conversation_context: str | None,
    business_snapshot: str | None = None,
) -> str:
    snap = (business_snapshot or "").strip()
    head = ""
    if snap:
        head = f"Database snapshot (aggregates for this business; use for disambiguation, not invented numbers):\n{snap[:4500]}\n\n"
    if not (conversation_context or "").strip():
        return (head + user_text.strip())[:12000]
    merged = (
        head
        + f"Conversation so far (context):\n{conversation_context.strip()[:6000]}\n\n"
        + f"Latest user message:\n{user_text.strip()[:8000]}"
    )
    return merged[:12000]


async def extract_intent_json_with_meta(
    *,
    user_text: str,
    settings: Settings,
    db: AsyncSession,
    conversation_context: str | None = None,
    business_snapshot: str | None = None,
) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    """
    Ordered failover: Gemini -> Groq -> OpenAI for structured intent JSON.
    Returns (normalized dict or None, metadata with provider_used / failover attempts).
    """
    if not settings.enable_ai:
        return None, {"reason": "enable_ai_false", "failover": []}

    keys = await resolve_provider_keys(settings, db)
    if not any_llm_key(keys):
        return None, {"reason": "no_api_keys", "failover": []}

    payload_text = _intent_user_payload(user_text, conversation_context, business_snapshot)
    gk, qk, ok = keys.get("gemini"), keys.get("groq"), keys.get("openai")

    async def try_gemini() -> dict[str, Any] | None:
        if not (gk or "").strip():
            return None
        return await _gemini_json(payload_text, settings, gk.strip())

    async def try_groq() -> dict[str, Any] | None:
        if not (qk or "").strip():
            return None
        return await _groq_json(payload_text, settings, qk.strip())

    async def try_openai() -> dict[str, Any] | None:
        if not (ok or "").strip():
            return None
        return await _openai_json(payload_text, settings, ok.strip())

    runners = [
        ("gemini", gk, try_gemini),
        ("groq", qk, try_groq),
        ("openai", ok, try_openai),
    ]

    out, meta = await run_ordered_failover(runners=runners)
    if out is None:
        return None, meta
    if not isinstance(out, dict):
        return None, {**meta, "reason": "invalid_payload_type"}
    return out, meta


async def extract_intent_json(
    *,
    user_text: str,
    settings: Settings,
    db: AsyncSession,
    conversation_context: str | None = None,
    business_snapshot: str | None = None,
) -> dict[str, Any] | None:
    """Returns normalized dict or None if provider disabled / error."""
    out, _meta = await extract_intent_json_with_meta(
        user_text=user_text,
        settings=settings,
        db=db,
        conversation_context=conversation_context,
        business_snapshot=business_snapshot,
    )
    return out


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
        if not isinstance(content, str):
            return None
        raw = _parse_json_loose(content)
    except (KeyError, IndexError, TypeError) as e:
        logger.warning("Bad LLM JSON: %s", e)
        return None
    if raw is None or not isinstance(raw, dict):
        logger.warning("Bad LLM JSON: could not parse object")
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
        if not isinstance(raw_text, str):
            return None
        raw = _parse_json_loose(raw_text)
    except (KeyError, IndexError, TypeError) as e:
        logger.warning("Bad Gemini JSON: %s", e)
        return None
    if raw is None or not isinstance(raw, dict):
        logger.warning("Bad Gemini JSON: could not parse object")
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


_APP_QUERY_SYSTEM = REPORT_SYSTEM_PROMPT


def _finalize_app_reply(text: str | None) -> str | None:
    if not text:
        return None
    t = text.strip()
    if not t:
        return None
    if len(t) > 2800:
        t = t[:2797] + "..."
    return t


async def _app_plain_openai(
    sys_p: str, user_content: str, settings: Settings, api_key: str
) -> str | None:
    payload = {
        "model": settings.openai_model_summary or settings.openai_model_parse,
        "max_tokens": 450,
        "messages": [
            {"role": "system", "content": sys_p},
            {"role": "user", "content": user_content},
        ],
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        res = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            json=payload,
        )
        if res.status_code >= 400:
            logger.warning("OpenAI app query synthesis failed %s", res.status_code)
            return None
        return _finalize_app_reply(_extract_openai_style_plain_text(res.json()))


async def _app_plain_groq(
    sys_p: str, user_content: str, settings: Settings, api_key: str
) -> str | None:
    payload = {
        "model": settings.groq_model,
        "max_tokens": 450,
        "messages": [
            {"role": "system", "content": sys_p},
            {"role": "user", "content": user_content},
        ],
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        res = await client.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            json=payload,
        )
        if res.status_code >= 400:
            logger.warning("Groq app query synthesis failed %s", res.status_code)
            return None
        return _finalize_app_reply(_extract_openai_style_plain_text(res.json()))


async def _app_plain_gemini(
    sys_p: str, user_content: str, settings: Settings, api_key: str
) -> str | None:
    model = settings.gemini_model.strip()
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    body = {
        "systemInstruction": {"parts": [{"text": sys_p}]},
        "contents": [{"parts": [{"text": user_content}]}],
        "generationConfig": {"maxOutputTokens": 450, "temperature": 0.35},
    }
    async with httpx.AsyncClient(timeout=60.0) as client:
        res = await client.post(url, params={"key": api_key}, json=body)
        if res.status_code >= 400:
            logger.warning("Gemini app query synthesis failed %s", res.status_code)
            return None
        outer = res.json()
    try:
        raw_text = outer["candidates"][0]["content"]["parts"][0]["text"]
        if isinstance(raw_text, str) and raw_text.strip():
            return _finalize_app_reply(raw_text.strip())
    except (KeyError, IndexError, TypeError):
        pass
    return None


async def synthesize_app_query_reply(
    *,
    user_text: str,
    facts_text: str,
    settings: Settings,
    db: AsyncSession,
    business_snapshot: str | None = None,
) -> tuple[str | None, dict[str, Any]]:
    """
    Optional LLM phrasing for grounded query replies (report/decision style only).
    Failover: Gemini -> Groq -> OpenAI. Returns (text or None, meta).
    """
    if not settings.enable_ai:
        return None, {"reason": "enable_ai_false", "failover": []}

    keys = await resolve_provider_keys(settings, db)
    if not any_llm_key(keys):
        return None, {"reason": "no_api_keys", "failover": []}

    ut = user_text.strip()[:2000]
    facts = (facts_text or "").strip()[:6000]
    if not facts:
        return None, {"reason": "empty_facts", "failover": []}

    sys_p = _APP_QUERY_SYSTEM.strip()
    snap = (business_snapshot or "").strip()
    snap_block = f"\n\nOVERVIEW (month-to-date aggregates):\n{snap[:2500]}" if snap else ""
    user_block = f"USER MESSAGE:\n{ut}{snap_block}\n\nFACTS (from Harisree database):\n{facts}"

    gk, qk, ok = keys.get("gemini"), keys.get("groq"), keys.get("openai")

    async def try_gemini() -> str | None:
        if not (gk or "").strip():
            return None
        return await _app_plain_gemini(sys_p, user_block, settings, gk.strip())

    async def try_groq() -> str | None:
        if not (qk or "").strip():
            return None
        return await _app_plain_groq(sys_p, user_block, settings, qk.strip())

    async def try_openai() -> str | None:
        if not (ok or "").strip():
            return None
        return await _app_plain_openai(sys_p, user_block, settings, ok.strip())

    runners = [
        ("gemini", gk, try_gemini),
        ("groq", qk, try_groq),
        ("openai", ok, try_openai),
    ]

    out, meta = await run_ordered_failover(runners=runners)
    if out is None:
        return None, meta
    if not isinstance(out, str):
        return None, {**meta, "reason": "invalid_text"}
    return out, meta
