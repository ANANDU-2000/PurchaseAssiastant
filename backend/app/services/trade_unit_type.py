"""Canonical packing unit labels for persisted trade lines and SQL rollups."""

from __future__ import annotations


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
