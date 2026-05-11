"""Heuristic intent extraction when LLM is disabled — shared by /ai/intent and app assistant."""

from __future__ import annotations

import re
from typing import Any


def stub_intent_from_text(text: str) -> tuple[dict[str, Any], list[str]]:
    """Very small heuristic — keeps preview→confirm flow testable without API keys."""
    t = text.lower().strip()
    data: dict[str, Any] = {
        "item": None,
        "variant": None,
        "unit_type": None,
        "bags": None,
        "kg_per_bag": None,
        "qty_kg": None,
        "purchase_price_per_bag": None,
        "landed_cost_per_bag": None,
        "selling_price_per_kg": None,
        "transport": None,
        "loading": None,
        "broker": None,
        "broker_percent": None,
        "supplier": None,
        "location": None,
    }
    missing: list[str] = []

    m = re.search(r"(\d+(?:\.\d+)?)\s*bags?", t)
    if m:
        data["bags"] = float(m.group(1))
        data["unit_type"] = "bag"
    m_kg = re.search(r"(\d+(?:\.\d+)?)\s*kg", t)
    if m_kg and data["bags"] is None:
        data["qty_kg"] = float(m_kg.group(1))
        data["unit_type"] = "kg"
    m2 = re.search(r"(\d+(?:\.\d+)?)\s*kg(?:/|\s*per\s*)?bag", t)
    if m2:
        data["kg_per_bag"] = float(m2.group(1))
    prices = re.findall(r"(?:rs\.?|₹|rupees?)\s*(\d{2,7})", t)
    if len(prices) >= 2:
        data["purchase_price_per_bag"] = float(prices[0])
        data["landed_cost_per_bag"] = float(prices[1])
    elif len(prices) == 1:
        data["landed_cost_per_bag"] = float(prices[0])
    sell_m = None
    for pat in (
        r"\bs(?:\s*)?rate\s+(\d+(?:\.\d+)?)",
        r"\bsrate\s*(\d+(?:\.\d+)?)",
        r"\bs\.r\s+(\d+(?:\.\d+)?)",
        r"\bsell(?:ing)?\s+(?:rate\s+)?(\d+(?:\.\d+)?)",
        r"\bsell\s+(\d+(?:\.\d+)?)",
        r"sell(?:ing)?\s*(?:₹|rs\.?)?\s*(\d+(?:\.\d+)?)",
    ):
        sell_m = re.search(pat, t)
        if sell_m:
            break
    if sell_m:
        data["selling_price_per_kg"] = float(sell_m.group(1))

    for word in ("rice", "oil", "atta", "dal"):
        if word in t:
            data["item"] = word
            break

    if data["bags"] is None and data["qty_kg"] is None:
        missing.append("quantity")
    if data["landed_cost_per_bag"] is None and data["purchase_price_per_bag"] is None:
        missing.append("landed_cost_per_bag or purchase_price")

    return data, missing
