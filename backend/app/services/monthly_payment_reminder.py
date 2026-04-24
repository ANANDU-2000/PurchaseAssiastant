"""Due-soon trade purchase scan (call from scheduler or cron)."""

from __future__ import annotations

from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import TradePurchase


async def check_due_soon_purchases(
    db: AsyncSession,
    business_id,
    within_days: int = 3,
) -> list[dict]:
    """Return unpaid trade purchases with due_date in [today, today+within_days]."""
    today = date.today()
    win = today + timedelta(days=within_days)
    r = await db.execute(
        select(TradePurchase).where(
            TradePurchase.business_id == business_id,
            TradePurchase.paid_at.is_(None),
            TradePurchase.due_date.isnot(None),
            TradePurchase.due_date >= today,
            TradePurchase.due_date <= win,
        )
    )
    rows = r.scalars().all()
    out: list[dict] = []
    for p in rows:
        out.append(
            {
                "id": str(p.id),
                "reference": p.human_id,
                "amount": float(p.total_amount or 0),
                "due_date": p.due_date.isoformat() if p.due_date else None,
            }
        )
    return out
