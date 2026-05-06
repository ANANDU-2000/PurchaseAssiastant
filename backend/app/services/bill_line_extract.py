"""Heuristic extraction of purchase lines from pasted invoice text (OCR stub / manual paste)."""

from __future__ import annotations

import re
from typing import Any

# qty [unit] name [@₹] rate  OR  name qty unit rate
_UNIT = r"bags?|bag|sacks?|sack|boxes?|box|tins?|tin|pcs?|pieces?|kgs?|kg"
_PAT_A = re.compile(
    rf"^(?P<qty>\d+(?:\.\d+)?)\s*(?P<unit>{_UNIT})\s+(?P<name>.+?)\s*(?:@|at|₹|rs\.?)?\s*(?P<rate>\d+(?:\.\d+)?)\s*$",
    re.IGNORECASE,
)
_PAT_B = re.compile(
    rf"^(?P<name>.+?)\s+(?P<qty>\d+(?:\.\d+)?)\s*(?P<unit>{_UNIT})\s*(?:@|at|₹|rs\.?)?\s*(?P<rate>\d+(?:\.\d+)?)\s*$",
    re.IGNORECASE,
)
_PAT_C = re.compile(
    r"^(?P<name>[A-Za-z][A-Za-z0-9\s\-]{1,60})\s+(?P<qty>\d+(?:\.\d+)?)\s+(?P<rate>\d+(?:\.\d+)?)\s*$",
    re.IGNORECASE,
)


def _norm_unit(u: str) -> str:
    u = (u or "").strip().lower()
    if u.startswith("bag"):
        return "bag"
    if u.startswith("sack"):
        # Master rebuild: sacks are not supported; normalize to BAG.
        return "bag"
    if u.startswith("box"):
        return "box"
    if u.startswith("tin"):
        return "tin"
    if u.startswith("pc") or u.startswith("piece"):
        return "piece"
    if u.startswith("kg"):
        return "kg"
    return "kg"


def extract_purchase_lines_from_text(text: str) -> list[dict[str, Any]]:
    """Return list of {item_name, qty, unit, landing_cost (rate)} for known line patterns."""
    out: list[dict[str, Any]] = []
    if not text or not text.strip():
        return out
    for raw in text.splitlines():
        line = raw.strip()
        if len(line) < 3:
            continue
        m = _PAT_A.match(line) or _PAT_B.match(line)
        if m:
            name = m.group("name").strip(" ,.-")
            qty = float(m.group("qty"))
            unit = _norm_unit(m.group("unit"))
            rate = float(m.group("rate"))
            if name and qty > 0 and rate >= 0:
                out.append(
                    {
                        "item_name": name[:200],
                        "qty": qty,
                        "unit": unit,
                        "landing_cost": rate,
                    }
                )
            continue
        m2 = _PAT_C.match(line)
        if m2:
            name = m2.group("name").strip(" ,.-")
            qty = float(m2.group("qty"))
            rate = float(m2.group("rate"))
            if name and qty > 0 and rate >= 0:
                out.append(
                    {
                        "item_name": name[:200],
                        "qty": qty,
                        "unit": "kg",
                        "landing_cost": rate,
                    }
                )
    return out
