"""Helpers for OCR / scanner confidence blending (0–100 scale)."""

from __future__ import annotations

from decimal import Decimal


def clamp_score(value: float | int | Decimal | None, *, lo: float = 0.0, hi: float = 100.0) -> float:
    if value is None:
        return lo
    try:
        x = float(value)
    except (TypeError, ValueError):
        return lo
    return max(lo, min(hi, x))


def combine_weighted_average(*pairs: tuple[float | None, float]) -> float:
    """pairs: (score, weight). Missing scores skipped; weight 0 ignored."""
    num = 0.0
    den = 0.0
    for score, weight in pairs:
        if weight <= 0:
            continue
        if score is None:
            continue
        num += float(score) * float(weight)
        den += float(weight)
    if den <= 0:
        return 0.0
    return clamp_score(num / den)
