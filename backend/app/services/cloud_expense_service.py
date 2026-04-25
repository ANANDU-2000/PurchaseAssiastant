"""Business-scoped cloud cost: next due dates, payment, UI flags."""

from __future__ import annotations

import calendar
import uuid
from dataclasses import dataclass
from datetime import date, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cloud_expense import CloudExpense, CloudPaymentHistory


def _clamp_day(y: int, m: int, day: int) -> int:
    last = calendar.monthrange(y, m)[1]
    return min(max(1, day), last)


def first_next_due_from(today: date, due_day: int) -> date:
    """First calendar date >= *today* that falls on *due_day* (month-clamped)."""
    d = _clamp_day(today.year, today.month, due_day)
    candidate = date(today.year, today.month, d)
    if candidate >= today:
        return candidate
    m = today.month + 1
    y = today.year
    if m > 12:
        m = 1
        y += 1
    d2 = _clamp_day(y, m, due_day)
    return date(y, m, d2)


def next_due_after_payment(last_paid: date, due_day: int) -> date:
    """The *due_day* in the calendar month following *last_paid*'s month."""
    m = last_paid.month + 1
    y = last_paid.year
    if m > 12:
        m = 1
        y += 1
    d = _clamp_day(y, m, due_day)
    return date(y, m, d)


# Unpaid: show the home card only inside this many calendar days before due (and when overdue).
PRE_DUE_VISIBILITY_DAYS = 3


@dataclass
class CloudExpenseFlags:
    show_alert: bool
    status: str  # "ok" | "due_soon" | "overdue"
    is_overdue: bool
    show_home_card: bool
    in_pre_due_window: bool


def compute_ui_flags(today: date, row: CloudExpense) -> CloudExpenseFlags:
    """
    Home card visibility (unpaid path):
    - Hidden when *today* is earlier than (next_due - PRE_DUE_VISIBILITY_DAYS): not in the reminder window.
    - From (next_due - PRE_DUE_VISIBILITY_DAYS) through the day before next_due: due_soon (soft reminder + UPI).
    - On or after next_due: overdue, show_alert for primary CTA.
    """
    nd = row.next_due_date
    window_start = nd - timedelta(days=PRE_DUE_VISIBILITY_DAYS)
    if today < window_start:
        return CloudExpenseFlags(
            show_alert=False,
            status="ok",
            is_overdue=False,
            show_home_card=False,
            in_pre_due_window=False,
        )
    if today < nd:
        return CloudExpenseFlags(
            show_alert=False,
            status="due_soon",
            is_overdue=False,
            show_home_card=True,
            in_pre_due_window=True,
        )
    return CloudExpenseFlags(
        show_alert=True,
        status="overdue",
        is_overdue=True,
        show_home_card=True,
        in_pre_due_window=False,
    )


async def ensure_cloud_expense(db: AsyncSession, business_id: uuid.UUID, today: date) -> CloudExpense:
    r = await db.execute(select(CloudExpense).where(CloudExpense.business_id == business_id))
    row = r.scalar_one_or_none()
    if row is not None:
        return row
    due_day = 1
    nd = first_next_due_from(today, due_day)
    row = CloudExpense(
        business_id=business_id,
        name="Cloud Cost",
        amount_inr=2500.0,
        due_day=due_day,
        last_paid_date=None,
        next_due_date=nd,
    )
    db.add(row)
    await db.flush()
    return row


async def pay_cloud_expense(
    db: AsyncSession,
    row: CloudExpense,
    today: date,
    amount_override: float | None,
    *,
    external_payment_id: str | None = None,
    payment_provider: str | None = None,
) -> CloudPaymentHistory:
    amt = float(amount_override) if amount_override is not None else float(row.amount_inr)
    if amt <= 0:
        raise ValueError("amount must be > 0")
    row.last_paid_date = today
    row.next_due_date = next_due_after_payment(today, row.due_day)
    ext = (external_payment_id or "").strip() or None
    prov = (payment_provider or "").strip() or None
    hist = CloudPaymentHistory(
        business_id=row.business_id,
        amount_inr=amt,
        paid_on=today,
        external_payment_id=ext,
        payment_provider=prov,
    )
    db.add(hist)
    await db.flush()
    return hist


def validate_config(*, amount_inr: float, due_day: int) -> None:
    if amount_inr <= 0:
        raise ValueError("amount_inr must be > 0")
    if not (1 <= due_day <= 31):
        raise ValueError("due_day must be 1–31")


async def list_history(
    db: AsyncSession, business_id: uuid.UUID, limit: int = 24
) -> list[CloudPaymentHistory]:
    q = (
        select(CloudPaymentHistory)
        .where(CloudPaymentHistory.business_id == business_id)
        .order_by(CloudPaymentHistory.paid_on.desc(), CloudPaymentHistory.created_at.desc())
        .limit(limit)
    )
    r = await db.execute(q)
    return list(r.scalars().all())


def row_to_dict(row: CloudExpense, today: date, history: list[CloudPaymentHistory]) -> dict[str, Any]:
    flags = compute_ui_flags(today, row)
    paid_up = today < row.next_due_date
    return {
        "id": str(row.id),
        "business_id": str(row.business_id),
        "name": row.name,
        "amount_inr": float(row.amount_inr),
        "due_day": int(row.due_day),
        "last_paid_date": row.last_paid_date.isoformat() if row.last_paid_date else None,
        "next_due_date": row.next_due_date.isoformat(),
        "show_alert": flags.show_alert,
        "status": flags.status,
        "is_overdue": flags.is_overdue,
        "paid_up": paid_up,
        "show_home_card": flags.show_home_card,
        "in_pre_due_window": flags.in_pre_due_window,
        "pre_due_visibility_days": PRE_DUE_VISIBILITY_DAYS,
        "history": [
            {
                "id": str(h.id),
                "amount_inr": float(h.amount_inr),
                "paid_on": h.paid_on.isoformat(),
                "created_at": h.created_at.isoformat() if h.created_at else None,
                "external_payment_id": h.external_payment_id,
                "payment_provider": h.payment_provider,
            }
            for h in history
        ],
    }