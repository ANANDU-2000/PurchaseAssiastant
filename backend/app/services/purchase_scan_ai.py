"""AI-assisted purchase scan parsing (Gemini -> Groq failover).

This module never writes to the database. It only converts OCR text to a
structured preview payload and conservative warnings.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.services.llm_failover import any_llm_key, resolve_provider_keys, run_ordered_failover
from app.services.llm_intent import _parse_json_loose  # type: ignore
from app.services.ocr_parser import normalize_item_name

logger = logging.getLogger(__name__)


def _normalize_ws(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())


def _infer_weight_kg_from_name(name: str) -> float | None:
    """Find first 'NN KG' in a name; guard against nonsense."""
    m = re.search(r"(\d{1,3}(?:\.\d{1,2})?)\s*KG\b", name.upper())
    if not m:
        return None
    v = float(m.group(1))
    if v <= 0 or v > 200:
        return None
    return v


def _post_validate(payload: dict[str, Any]) -> tuple[dict[str, Any], list[str], list[str]]:
    """Return (payload, missing_fields, warnings). Does not invent values."""
    missing: list[str] = []
    warnings: list[str] = []

    sup = _normalize_ws(str(payload.get("supplier_name") or ""))
    if not sup:
        missing.append("supplier_name")

    items = payload.get("items")
    if not isinstance(items, list) or not items:
        missing.append("items")
        return payload, missing, warnings

    out_items: list[dict[str, Any]] = []
    for i, it in enumerate(items):
        if not isinstance(it, dict):
            continue
        pref = f"line_{i}"
        name = normalize_item_name(_normalize_ws(str(it.get("name") or it.get("item_name") or "")))
        qty = it.get("qty")
        unit = _normalize_ws(str(it.get("unit") or "")).lower() or "kg"
        if unit in ("bags", "bag"):
            unit = "bag"
        elif unit in ("sacks", "sack"):
            unit = "sack"
        elif unit in ("boxes", "box"):
            unit = "box"
        elif unit in ("tins", "tin"):
            unit = "tin"
        elif unit in ("pcs", "pc", "pieces", "piece"):
            unit = "piece"
        elif unit in ("kgs",):
            unit = "kg"
        pr = it.get("purchase_rate") or it.get("p_rate") or it.get("rate")
        sr = it.get("selling_rate") or it.get("s_rate")

        try:
            qty_f = float(qty) if qty is not None else 0.0
        except Exception:
            qty_f = 0.0
        try:
            pr_f = float(pr) if pr is not None else 0.0
        except Exception:
            pr_f = 0.0
        try:
            sr_f = float(sr) if sr is not None else 0.0
        except Exception:
            sr_f = 0.0

        wpu = it.get("weight_per_unit_kg")
        if wpu is None:
            wpu = _infer_weight_kg_from_name(name) if unit in ("bag", "sack", "box", "tin") else None
        try:
            wpu_f = float(wpu) if wpu is not None else None
        except Exception:
            wpu_f = None

        if not name:
            missing.append(f"{pref}.item_name")
        if qty_f <= 0:
            missing.append(f"{pref}.qty")
        if pr_f <= 0:
            missing.append(f"{pref}.purchase_rate")
        if unit not in ("kg", "bag", "sack", "box", "tin", "ltr", "piece"):
            missing.append(f"{pref}.unit")

        # Safety rule: unit=kg means qty is already kg. Never multiply by name weight.
        if unit == "kg" and wpu_f is not None:
            warnings.append(f"{pref}: ignoring name weight for KG unit")
            wpu_f = None

        out_items.append(
            {
                "name": name or "Unknown item",
                "qty": qty_f,
                "unit": unit,
                "purchase_rate": pr_f,
                "selling_rate": (sr_f if sr_f > 0 else None),
                "weight_per_unit_kg": (wpu_f if wpu_f and wpu_f > 0 else None),
            }
        )

    payload["supplier_name"] = sup or None
    payload["broker_name"] = _normalize_ws(str(payload.get("broker_name") or "")) or None
    payload["items"] = out_items

    charges = payload.get("charges") if isinstance(payload.get("charges"), dict) else {}
    payload["charges"] = charges if isinstance(charges, dict) else {}

    return payload, sorted(set(missing)), warnings


def _scanner_system_prompt() -> str:
    return (
        "You are an OCR-to-JSON parser for purchase bills.\n"
        "Return ONLY valid JSON.\n"
        "\n"
        "Schema:\n"
        "{\n"
        '  \"supplier_name\": string|null,\n'
        '  \"broker_name\": string|null,\n'
        '  \"charges\": {\"delivered_rate\": number|null, \"billty_rate\": number|null, \"freight_amount\": number|null, \"freight_type\": \"included\"|\"separate\"|null},\n'
        '  \"items\": [\n'
        "    {\n"
        '      \"name\": string,\n'
        '      \"qty\": number,\n'
        '      \"unit\": string,\n'
        '      \"purchase_rate\": number,\n'
        '      \"selling_rate\": number|null,\n'
        '      \"weight_per_unit_kg\": number|null\n'
        "    }\n"
        "  ]\n"
        "}\n"
        "\n"
        "Rules:\n"
        "- Malayalam+English mix: try best-effort transliteration/cleanup.\n"
        "- Fix common spelling: suger->sugar.\n"
        "- If you see two rates (P and S): first is purchase_rate, second is selling_rate.\n"
        "- If unit is KG, qty is already kg; do NOT treat '50 KG' in the name as multiplier.\n"
        "- If unit is bag/sack and name contains '50 KG' etc, set weight_per_unit_kg to that.\n"
        "- Extract header charges when present: delivered/delhead/delivery, billty/bilty/bilti, freight.\n"
        "- If freight looks included in the note, set freight_type='included' else 'separate' when freight_amount is set.\n"
        "- Units: prefer one of kg|bag|sack|box|tin|piece|ltr.\n"
        "- If unknown, set fields to null; never invent missing values.\n"
    )


async def parse_scan_text_with_ai(
    *,
    text: str,
    settings: Settings,
    db: AsyncSession,
) -> tuple[dict[str, Any] | None, dict[str, Any]]:
    """Return (payload or None, meta)."""
    keys = await resolve_provider_keys(settings, db)
    if not any_llm_key(keys):
        return None, {"reason": "no_api_keys", "provider_used": None, "failover": []}

    system = _scanner_system_prompt()
    user = (text or "").strip()[:9000]
    if not user:
        return None, {"reason": "empty_text", "provider_used": None, "failover": []}

    from app.services.llm_intent import _gemini_json, _groq_json  # lazy import

    async def try_gemini() -> dict[str, Any] | None:
        gk = (keys.get("gemini") or "").strip()
        if not gk:
            return None
        # Reuse Gemini helper by embedding system + user.
        return await _gemini_json(f"{system}\n\nOCR:\n{user}", settings, gk)

    async def try_groq() -> dict[str, Any] | None:
        qk = (keys.get("groq") or "").strip()
        if not qk:
            return None
        return await _groq_json(f"{system}\n\nOCR:\n{user}", settings, qk)

    out, meta = await run_ordered_failover(
        runners=[
            ("gemini", keys.get("gemini"), try_gemini),
            ("groq", keys.get("groq"), try_groq),
        ]
    )
    if out is None:
        return None, meta
    if not isinstance(out, dict):
        return None, {**meta, "reason": "non_object"}

    # llm_intent returns {intent,data,...} normally; tolerate both formats.
    if "data" in out and isinstance(out.get("data"), dict):
        payload = out["data"]
    else:
        payload = out
    if not isinstance(payload, dict):
        return None, {**meta, "reason": "bad_payload"}

    payload, missing, warnings = _post_validate(payload)
    return (
        {
            "payload": payload,
            "missing_fields": missing,
            "parse_warnings": warnings,
        },
        meta,
    )

