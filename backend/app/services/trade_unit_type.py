"""Canonical packing unit labels for persisted trade lines and SQL rollups."""

from __future__ import annotations


VALID_TRADE_UNIT_TYPES: frozenset[str] = frozenset({"bag", "box", "tin", "kg", "other"})


def derive_trade_unit_type(unit: str | None) -> str:
    """Maps free-form [unit] to bag | box | tin | kg | other (lowercase).

    Mirrors legacy `%LIKE%` aggregates: sack counts as bag; `KG`, ` PER KG`,
    compound labels with `BOX`/`BAG`/… are resolved by substring order below.
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
    if "KG" in u:
        return "kg"
    return "other"
