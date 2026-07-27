"""Low-stock priority scoring for shortage management.

This is intentionally heuristic for v1: it combines stock urgency, reorder gaps,
delays, verification/mismatch signals, and period usage into a single score
so the UI can sort shortages enterprise-style.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from typing import Literal

from app.schemas.stock import StockListItemOut


PriorityBand = Literal["critical", "high", "normal"]


@dataclass(frozen=True)
class LowStockPriority:
    score: float
    band: PriorityBand

    out_of_stock_flag: bool
    delayed_flag: bool
    mismatch_flag: bool
    needs_verification: bool


def _to_float(d: Decimal | None) -> float:
    if d is None:
        return 0.0
    try:
        return float(d)
    except Exception:
        return 0.0


def compute_low_stock_priority(
    item: StockListItemOut,
    *,
    delayed_threshold_days: int = 7,
) -> LowStockPriority:
    """Compute priority score & band for one stock list row."""

    cur = _to_float(item.current_stock)
    reorder = _to_float(item.reorder_level)
    period_usage = _to_float(item.period_usage_qty)

    pending_days = item.pending_order_days or 0
    has_pending = bool(item.has_pending_order)

    out_of_stock_flag = item.stock_status.lower() == "out" or cur <= 0.0
    delayed_flag = has_pending and pending_days >= delayed_threshold_days

    phys_diff = _to_float(item.physical_stock_difference_qty)
    mismatch_flag = abs(phys_diff) > 0.001

    needs_verification = bool(item.needs_verification)

    # Normalize pieces to avoid huge swings when usage units differ.
    # - reorder_gap_norm is in [0..1] relative to reorder_level
    reorder_gap = max(0.0, reorder - cur)
    reorder_gap_norm = reorder_gap / max(1.0, reorder) if reorder > 0 else 0.0
    reorder_gap_norm = max(0.0, min(1.0, reorder_gap_norm))

    # - pending_norm is in [0..1] relative to 2 weeks
    pending_norm = min(1.0, max(0.0, float(pending_days) / 14.0))

    # - mismatch_norm in [0..1] relative to an "actionable" diff.
    # The backend verification threshold is ~2 units, so we normalize against 2.
    mismatch_norm = abs(phys_diff) / 2.0
    mismatch_norm = max(0.0, min(1.0, mismatch_norm))

    # - usage_boost uses log1p so large usage doesn't dominate
    usage_boost = period_usage if period_usage > 0 else 0.0

    # Weights (v1)
    w_out = 100.0
    w_reorder_gap = 35.0
    w_usage = 12.0
    w_delay = 45.0
    w_mismatch = 30.0
    w_verify = 28.0

    score = 0.0
    if out_of_stock_flag:
        score += w_out
    score += w_reorder_gap * reorder_gap_norm
    score += w_usage * (0.0 if usage_boost <= 0 else (abs(usage_boost) ** 0.5))
    score += w_delay * pending_norm
    score += w_mismatch * mismatch_norm
    if needs_verification:
        score += w_verify

    # Priority band (v1 heuristic)
    if out_of_stock_flag or mismatch_flag or (delayed_flag and pending_days >= 14):
        band: PriorityBand = "critical"
    elif delayed_flag or needs_verification:
        band = "high"
    else:
        band = "normal"

    return LowStockPriority(
        score=float(score),
        band=band,
        out_of_stock_flag=out_of_stock_flag,
        delayed_flag=delayed_flag,
        mismatch_flag=mismatch_flag,
        needs_verification=needs_verification,
    )

