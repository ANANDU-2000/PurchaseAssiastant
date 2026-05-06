from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Any

from sqlalchemy import and_, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.models import TradePurchase, TradePurchaseLine, WhatsAppReportSchedule
from app.services import trade_query as tq
from app.services.whatsapp_cloud_send import send_whatsapp_cloud_text

logger = logging.getLogger(__name__)


def _ist_today() -> date:
    ist = datetime.now(timezone.utc) + timedelta(hours=5, minutes=30)
    return date(ist.year, ist.month, ist.day)


def _range_for_type(t: str, today: date) -> tuple[date, date]:
    x = (t or "weekly").strip().lower()
    if x == "daily":
        return today, today
    if x == "monthly":
        return today - timedelta(days=29), today
    return today - timedelta(days=6), today


def _should_send(schedule_type: str, last_sent_at: datetime | None, today: date) -> bool:
    if last_sent_at is None:
        return True
    last_ist = last_sent_at.astimezone(timezone(timedelta(hours=5, minutes=30))).date()
    t = (schedule_type or "weekly").strip().lower()
    if t == "daily":
        return last_ist != today
    if t == "weekly":
        return (today - last_ist).days >= 6
    if t == "monthly":
        return (today - last_ist).days >= 29
    return last_ist != today


async def _build_summary_lines(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
) -> dict[str, Any]:
    amt_inner = tq.trade_line_amount_expr()
    conditions = [
        TradePurchase.business_id == business_id,
        tq.trade_purchase_status_in_reports(),
        TradePurchase.purchase_date >= date_from,
        TradePurchase.purchase_date <= date_to,
    ]
    q_inner = (
        select(
            func.count(func.distinct(TradePurchase.id)).label("deals"),
            func.coalesce(func.sum(amt_inner), 0.0).label("total_purchase"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(and_(*conditions))
    )
    m = (await db.execute(q_inner)).mappings().one()
    deals = int(m["deals"] or 0)
    total_purchase = float(m["total_purchase"] or 0.0)

    kg_expr = tq.trade_line_weight_expr()
    bag_expr = tq.trade_line_qty_bags_expr()
    box_expr = tq.trade_line_qty_boxes_expr()
    tin_expr = tq.trade_line_qty_tins_expr()
    roll_q = (
        select(
            func.coalesce(func.sum(bag_expr), 0.0).label("total_bags"),
            func.coalesce(func.sum(box_expr), 0.0).label("total_boxes"),
            func.coalesce(func.sum(tin_expr), 0.0).label("total_tins"),
            func.coalesce(func.sum(kg_expr), 0.0).label("total_kg"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .where(and_(*conditions))
    )
    r = (await db.execute(roll_q)).mappings().one()
    return {
        "deals": deals,
        "total_purchase": total_purchase,
        "total_kg": float(r["total_kg"] or 0.0),
        "total_bags": float(r["total_bags"] or 0.0),
        "total_boxes": float(r["total_boxes"] or 0.0),
        "total_tins": float(r["total_tins"] or 0.0),
    }


def _fmt_inr0(v: float) -> str:
    return f"₹{int(round(v)):,}".replace(",", ",")


def _qty_line(t: dict[str, Any]) -> str:
    parts: list[str] = []
    kg = float(t.get("total_kg") or 0.0)
    bags = float(t.get("total_bags") or 0.0)
    boxes = float(t.get("total_boxes") or 0.0)
    tins = float(t.get("total_tins") or 0.0)
    if kg > 1e-9:
        parts.append(f"{kg:.0f} KG")
    if bags > 1e-9:
        parts.append(f"{bags:.0f} BAGS")
    if boxes > 1e-9:
        parts.append(f"{boxes:.0f} BOX")
    if tins > 1e-9:
        parts.append(f"{tins:.0f} TIN")
    return " • ".join(parts)


async def send_due_whatsapp_reports(
    settings: Settings,
    db: AsyncSession,
) -> dict[str, Any]:
    """
    Server-side auto-send.

    Triggered by a Render Cron Job hitting an internal endpoint.
    """
    today = _ist_today()
    now_ist = datetime.now(timezone.utc) + timedelta(hours=5, minutes=30)

    # Fetch enabled schedules near the configured time window (±10 minutes).
    q = select(WhatsAppReportSchedule).where(WhatsAppReportSchedule.enabled.is_(True))
    rows = (await db.execute(q)).scalars().all()

    sent = 0
    skipped = 0
    failures = 0
    for s in rows:
        # Only send close to scheduled HH:mm in IST for now (single timezone support).
        if abs((now_ist.hour * 60 + now_ist.minute) - (int(s.hour) * 60 + int(s.minute))) > 10:
            skipped += 1
            continue
        if not _should_send(s.schedule_type, s.last_sent_at, today):
            skipped += 1
            continue

        date_from, date_to = _range_for_type(s.schedule_type, today)
        totals = await _build_summary_lines(db, business_id=s.business_id, date_from=date_from, date_to=date_to)
        body = "\n".join(
            [
                f"Purchase Report ({date_from.strftime('%d %b')} → {date_to.strftime('%d %b')})",
                "",
                f"Deals: {int(totals['deals'])}",
                f"Total: {_fmt_inr0(float(totals['total_purchase']))}",
                _qty_line(totals),
            ]
        ).strip()

        res = send_whatsapp_cloud_text(settings, to_e164=s.to_e164, body=body)
        if not res.get("ok"):
            failures += 1
            continue

        sent += 1
        await db.execute(
            update(WhatsAppReportSchedule)
            .where(WhatsAppReportSchedule.id == s.id)
            .values(last_sent_at=datetime.now(timezone.utc))
        )

    await db.commit()
    logger.info("wa_auto_reports sent=%s skipped=%s failures=%s total=%s", sent, skipped, failures, len(rows))
    return {"ok": True, "sent": sent, "skipped": skipped, "failures": failures, "total": len(rows)}

