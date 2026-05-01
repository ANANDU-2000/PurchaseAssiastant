"""Purchase bill text parsing helpers (supplier hint + tabular rows).

Used by `/v1/me/scan-purchase` and can be composed with OCR engines that return plain text."""

from __future__ import annotations

import re
from typing import Any

from app.services.bill_line_extract import extract_purchase_lines_from_text


def extract_supplier_candidate(lines: list[str]) -> str | None:
    """Pick a tentative supplier/header line — conservative; callers must confirm."""
    for raw in lines[:12]:
        t = raw.strip()
        if len(t) < 5 or len(t) > 200:
            continue
        # Skip obvious table / numeric-heavy rows
        if re.search(r"^\s*\d+(\.\d+)?\s*(bag|kg|kgs)\b", t, re.I):
            continue
        if re.match(r"^[\d₹Rs.,\s]+$", t, re.I):
            continue
        if "total" == t.strip().split()[0].lower():
            continue
        return t
    return None


_UNIT_ALIASES = {
    "bags": "bag",
    "sack": "sack",
    "sacks": "sack",
    "kgs": "kg",
    "kilogram": "kg",
    "ltr": "ltr",
    "litre": "ltr",
    "liter": "ltr",
}


def normalize_purchase_unit(u: str) -> str:
    t = (u or "").strip().lower()
    if not t:
        return "kg"
    return _UNIT_ALIASES.get(t, t)


def extract_item_rows(text: str) -> tuple[list[dict[str, Any]], list[str]]:
    """Structured lines + keys that commonly need confirmation when ambiguous."""
    raw = extract_purchase_lines_from_text(text)
    missing: list[str] = []
    out: list[dict[str, Any]] = []
    for idx, e in enumerate(raw):
        name = (e.get("item_name") or "").strip()
        qty = float(e.get("qty") or 0)
        unit = normalize_purchase_unit(str(e.get("unit") or "kg"))
        rate = float(e.get("landing_cost") or 0)
        pref = f"line_{idx}"
        if not name:
            missing.append(f"{pref}.item_name")
        if qty <= 0:
            missing.append(f"{pref}.qty")
        if rate <= 0:
            missing.append(f"{pref}.rate")
        if unit not in ("kg", "bag", "sack", "ltr", "box", "tin", "unit"):
            missing.append(f"{pref}.unit")
        out.append(
            {
                "name": name or "Unknown item",
                "qty": qty,
                "unit": unit,
                "rate": rate,
            }
        )
    if not out:
        missing.extend(["supplier_name", "items", "qty", "unit", "rate"])
    return out, missing


def normalize_scan_text(blob: bytes) -> str:
    """Best-effort decode for stubs / mis-encoded uploads."""
    if not blob:
        return ""
    for enc in ("utf-8", "utf-8-sig", "latin-1"):
        try:
            return blob.decode(enc, errors="ignore")
        except Exception:  # noqa: BLE001
            continue
    return ""
