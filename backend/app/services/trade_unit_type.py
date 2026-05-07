"""Canonical packing unit labels for persisted trade lines and SQL rollups."""

from __future__ import annotations

import re
from decimal import Decimal


VALID_TRADE_UNIT_TYPES: frozenset[str] = frozenset({"bag", "box", "tin", "kg", "pcs", "other"})


def derive_trade_unit_type(unit: str | None) -> str:
    """Maps free-form [unit] to bag | box | tin | kg | other (lowercase).

    Mirrors legacy `%LIKE%` aggregates while enforcing the master rebuild unit set.
    `KG`, ` PER KG`, compound labels with `BOX`/`BAG`/… are resolved by substring
    order below.

    Back-compat note: existing historical rows may contain `SACK`. We normalize
    `SACK` to the canonical `bag` bucket so reports remain stable, but the UI
    must not allow creating new `sack` units.
    """
    u = (unit or "").strip().upper()
    if not u:
        return "other"
    if "SACK" in u or "BAG" in u:
        return "bag"
    if "BOX" in u:
        return "box"
    if "TIN" in u:
        return "tin"
    if u in ("PCS", "PC", "PIECE", "PIECES"):
        return "pcs"
    if "KG" in u:
        return "kg"
    return "other"


_NN_KG_PATTERN = re.compile(r"(\d+(?:\.\d+)?)\s*KG", re.IGNORECASE)


def parse_kg_per_bag_from_name(item_name: str | None) -> Decimal | None:
    """[Bug 2 fix] Returns the first `NN KG` token in [item_name] as a Decimal.

    Used to auto-derive `weight_per_unit` for BAG lines that omit it on
    create/update, mirroring the Flutter `UnitClassifier.kgFromName` so the
    backend total kg matches the wizard preview (e.g. `SUGAR 50 KG` → 50).
    Returns None when the name has no kg token, parses to <= 0, or exceeds
    the realistic 200 kg/bag ceiling.
    """
    if not item_name:
        return None
    m = _NN_KG_PATTERN.search(item_name)
    if not m:
        return None
    raw = m.group(1)
    try:
        v = Decimal(raw)
    except Exception:
        return None
    if v <= 0:
        return None
    if v > Decimal("200"):
        return None
    return v
