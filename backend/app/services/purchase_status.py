"""Derive purchase lifecycle status from totals, payments, and due date."""

from __future__ import annotations

from datetime import date, datetime, timezone
from decimal import Decimal


def _dec(x: float | Decimal | None) -> Decimal:
    if x is None:
        return Decimal("0")
    if isinstance(x, Decimal):
        return x
    return Decimal(str(x))


def compute_status(
    *,
    stored_status: str,
    total_amount: float | Decimal,
    paid_amount: float | Decimal,
    due_date: date | None,
    now: datetime | None = None,
) -> str:
    """Return derived status: paid / partially_paid / overdue override stored when applicable."""
    st = (stored_status or "confirmed").strip().lower()
    if st == "cancelled":
        return "cancelled"
    if st == "deleted":
        return "deleted"
    if st == "draft":
        return "draft"

    total = _dec(total_amount)
    paid = _dec(paid_amount)
    if total <= 0:
        return st if st in {"saved", "confirmed", "paid", "partially_paid", "overdue"} else "confirmed"
    remaining = total - paid
    if remaining <= 0 or paid >= total:
        return "paid"

    when = now or datetime.now(timezone.utc)
    today = when.date() if isinstance(when, datetime) else when
    if due_date is not None and remaining > 0:
        if today > due_date:
            return "overdue"
        delta = (due_date - today).days
        if 0 <= delta <= 3:
            return "due_soon"

    if paid > 0:
        return "partially_paid"

    if st in {"saved", "confirmed", "partially_paid", "paid", "overdue", "due_soon"}:
        return st
    return "confirmed"
