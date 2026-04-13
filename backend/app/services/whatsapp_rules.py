"""Rule-based transactional parse when LLM is disabled or returns nothing."""

from __future__ import annotations

import re
from typing import Any

_QUERY_RE = re.compile(r"(?P<item>.+?)\s+(?P<price>\d+(?:\.\d+)?)\s*(?:ok|okay|good|fine)\??", re.I)

# Reuse multiline key:value parser from whatsapp_flow logic — duplicated minimal check
_LINE_KV = re.compile(r"^(\w[\w\s]*?):\s*(.+)$", re.M)


def _pick_kv(text: str) -> dict[str, str]:
    kv: dict[str, str] = {}
    for ln in text.splitlines():
        ln = ln.strip()
        if ":" not in ln:
            continue
        k, v = ln.split(":", 1)
        key = k.strip().lower().replace(" ", "_")
        kv[key] = v.strip()
    return kv


def rule_parse_whatsapp(text: str) -> dict[str, Any] | None:
    """
    Return transactional shape compatible with _normalize_whatsapp_payload output,
    or None to defer to help text.
    """
    raw = text.strip()
    if not raw:
        return None
    low = raw.lower()

    # --- multiline draft (same as legacy WhatsApp entry) ---
    kv = _pick_kv(raw)
    if len(kv) >= 3:
        item = kv.get("item") or kv.get("name") or kv.get("product")
        qty_s = kv.get("qty") or kv.get("quantity")
        unit = (kv.get("unit") or "").lower()
        buy_s = kv.get("buy") or kv.get("buy_price") or kv.get("rate") or kv.get("bp")
        land_s = kv.get("land") or kv.get("landing") or kv.get("landing_cost") or kv.get("lc")
        if item and qty_s and unit in ("kg", "box", "piece") and buy_s and land_s:
            return {
                "intent": "create_entry",
                "data": {
                    "item": item,
                    "qty": qty_s,
                    "unit": unit,
                    "buy_price": buy_s,
                    "landing_cost": land_s,
                    "selling_price": kv.get("sell") or kv.get("selling_price") or kv.get("selling"),
                    "supplier_name": kv.get("supplier"),
                    "broker_name": kv.get("broker"),
                    "entry_date": kv.get("date") or kv.get("entry_date"),
                },
                "missing_fields": [],
                "clarification_question": None,
                "confidence": 0.85,
                "preview_hint": f"Purchase draft: {item}",
            }

    # --- add supplier ---
    m = re.match(r"(?i)^(?:add|new)\s+supplier\s+(.+)$", raw)
    if m:
        rest = m.group(1).strip()
        phone = None
        name = rest
        pm = re.search(r"(\+?\d[\d\s\-]{8,})", rest)
        if pm:
            phone = pm.group(1).strip()
            name = rest.replace(pm.group(0), "").strip().strip(" -–,")
        return {
            "intent": "create_supplier",
            "data": {"supplier_name": name or rest, "supplier_phone": phone},
            "missing_fields": [] if name else ["supplier_name"],
            "clarification_question": None,
            "confidence": 0.75,
            "preview_hint": f"New supplier: {name or rest}",
        }

    # --- add broker ---
    m = re.match(r"(?i)^(?:add|new)\s+broker\s+(.+)$", raw)
    if m:
        name = m.group(1).strip()
        comm = None
        cm = re.search(r"(\d+(?:\.\d+)?)\s*%", name)
        if cm:
            comm = float(cm.group(1))
        return {
            "intent": "create_broker",
            "data": {"broker_name": name, "broker_commission_flat": comm},
            "missing_fields": [],
            "clarification_question": None,
            "confidence": 0.7,
            "preview_hint": f"New broker: {name}",
        }

    # --- add item (needs category) ---
    m = re.match(r"(?i)^(?:add|new)\s+item\s+(.+)$", raw)
    if m:
        tail = m.group(1).strip()
        cat = None
        im = re.match(r"(?i)^(.+?)\s+in\s+category\s+(.+)$", tail)
        if im:
            return {
                "intent": "create_item",
                "data": {"item_name": im.group(1).strip(), "category_name": im.group(2).strip()},
                "missing_fields": [],
                "clarification_question": None,
                "confidence": 0.72,
                "preview_hint": f"New item: {im.group(1).strip()}",
            }
        return {
            "intent": "create_item",
            "data": {"item_name": tail, "category_name": None},
            "missing_fields": ["category_name"],
            "clarification_question": "Which category should this item belong to? (reply with category name)",
            "confidence": 0.55,
            "preview_hint": f"New item: {tail}",
        }

    # --- update last entry (price) ---
    if re.search(r"(?i)(change|update|edit).*(last\s+)?entry", low) or re.search(
        r"(?i)last\s+entry.*(price|rate|land|cost)", low
    ):
        patch = {}
        pm = re.search(r"(?:₹|rs\.?\s*|price\s*|land(?:ing)?\s*|cost\s*)(\d+(?:\.\d+)?)", raw, re.I)
        if pm:
            patch["patch_land"] = float(pm.group(1))
        return {
            "intent": "update_entry",
            "data": {
                "update_scope": "last",
                **patch,
            },
            "missing_fields": [] if patch else ["patch_land or patch_buy"],
            "clarification_question": None if patch else "What should the new landing or buy price be?",
            "confidence": 0.55,
            "preview_hint": "Update last entry",
        }

    # --- query: item profit week ---
    m = re.match(
        r"(?i)^(?:profit|ലാഭം)?\s*(?:for\s+)?(.+?)\s+(?:this\s+)?(week|month|today|mtd)\??$",
        raw,
    )
    if m:
        item = m.group(1).strip().strip("?")
        dr = m.group(2).lower()
        if dr == "mtd":
            dr = "month"
        return {
            "intent": "query",
            "data": {"query_kind": "item_profit", "item": item, "date_range": dr},
            "missing_fields": [],
            "clarification_question": None,
            "confidence": 0.65,
            "preview_hint": f"Profit {item} ({dr})",
        }

    # --- query: best supplier (keyword) ---
    if "best supplier" in low or "top supplier" in low:
        return {
            "intent": "query",
            "data": {"query_kind": "best_supplier_mtd", "item": None},
            "missing_fields": [],
            "clarification_question": None,
            "confidence": 0.8,
            "preview_hint": "Best supplier MTD",
        }

    # --- today / month overview (legacy keywords) ---
    if low in ("today", "daily") or "ഇന്ന്" in raw:
        return {
            "intent": "query",
            "data": {"query_kind": "today_summary"},
            "missing_fields": [],
            "clarification_question": None,
            "confidence": 0.82,
            "preview_hint": "Today",
        }
    if (
        low in ("overview", "summary", "stats", "report", "?")
        or "overview" in low
        or "report" in low
        or "ഈ മാസം" in raw
    ):
        return {
            "intent": "query",
            "data": {"query_kind": "month_summary"},
            "missing_fields": [],
            "clarification_question": None,
            "confidence": 0.8,
            "preview_hint": "Month overview",
        }

    # --- best <item> (not "best supplier" alone) ---
    if low.startswith("best ") and len(low) > 5:
        rest = low[5:].strip()
        if rest and rest != "supplier":
            return {
                "intent": "query",
                "data": {"query_kind": "best_supplier_for_item", "item": rest},
                "missing_fields": [],
                "clarification_question": None,
                "confidence": 0.78,
                "preview_hint": f"Best supplier for {rest}",
            }

    # --- broker commission summary ---
    if re.search(r"(?i)broker.*(commission|impact|summary)|commission.*broker", low):
        return {
            "intent": "query",
            "data": {"query_kind": "broker_commission", "date_range": "month"},
            "missing_fields": [],
            "clarification_question": None,
            "confidence": 0.65,
            "preview_hint": "Broker commission",
        }

    # --- quick price check: "Oil 1200 ok?" ---
    m = _QUERY_RE.match(raw.strip())
    if m:
        return {
            "intent": "query",
            "data": {
                "query_kind": "price_check",
                "item": m.group("item").strip(),
                "price": float(m.group("price")),
            },
            "missing_fields": [],
            "clarification_question": None,
            "confidence": 0.7,
            "preview_hint": "Price check",
        }

    return None
