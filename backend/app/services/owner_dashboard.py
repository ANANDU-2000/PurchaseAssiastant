"""Owner command-center aggregate (single payload)."""

from __future__ import annotations

import uuid
from datetime import date, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem
from app.models.owner_ops import BackupLog
from app.services import staff_tasks as st
from app.services import trade_query as tq
from app.models.trade_purchase import TradePurchase


async def build_owner_dashboard(
    db: AsyncSession, business_id: uuid.UUID
) -> dict[str, Any]:
    today = date.today()
    week_ago = today - timedelta(days=6)

    staff = await st.performance_summary(db, business_id)

    low = (
        await db.execute(
            select(func.count())
            .select_from(CatalogItem)
            .where(
                CatalogItem.business_id == business_id,
                CatalogItem.deleted_at.is_(None),
                CatalogItem.reorder_level.is_not(None),
                CatalogItem.current_stock <= CatalogItem.reorder_level,
            )
        )
    ).scalar() or 0

    out_of = (
        await db.execute(
            select(func.count())
            .select_from(CatalogItem)
            .where(
                CatalogItem.business_id == business_id,
                CatalogItem.deleted_at.is_(None),
                CatalogItem.current_stock <= 0,
            )
        )
    ).scalar() or 0

    spend_week = (
        await db.execute(
            select(func.coalesce(func.sum(TradePurchase.total_landing_subtotal), 0))
            .where(
                TradePurchase.business_id == business_id,
                tq.trade_purchase_status_in_reports(),
                TradePurchase.purchase_date >= week_ago,
                TradePurchase.purchase_date <= today,
            )
        )
    ).scalar() or 0

    last_backup = (
        await db.execute(
            select(BackupLog)
            .where(BackupLog.business_id == business_id)
            .order_by(BackupLog.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()

    exceptions: list[dict[str, Any]] = []
    if int(out_of) > 0:
        exceptions.append(
            {"kind": "out_of_stock", "message": f"{int(out_of)} items at zero stock"}
        )
    if int(low) > 0:
        exceptions.append(
            {"kind": "low_stock", "message": f"{int(low)} items at/below reorder"}
        )
    if last_backup is None:
        exceptions.append(
            {"kind": "backup", "message": "No server backup logged yet"}
        )
    elif last_backup.status == "fail":
        exceptions.append(
            {
                "kind": "backup_failed",
                "message": last_backup.error_message or "Last backup failed",
            }
        )

    pending_tasks = sum(int(s.get("pending") or 0) for s in staff)
    if pending_tasks > 0:
        exceptions.append(
            {
                "kind": "staff_pending",
                "message": f"{pending_tasks} staff tasks still open",
            }
        )

    return {
        "as_of": today.isoformat(),
        "exceptions": exceptions,
        "staff_performance": staff,
        "stock": {
            "low_count": int(low),
            "out_count": int(out_of),
        },
        "comparison": {
            "spend_last_7_days": float(spend_week),
        },
        "backup": {
            "last_status": last_backup.status if last_backup else None,
            "last_at": last_backup.created_at.isoformat() if last_backup else None,
            "last_size_bytes": last_backup.size_bytes if last_backup else None,
        },
        "ai_usage": {
            "note": "AI usage panel activates after provider credential logging (Wave 4/7).",
            "requests_today": 0,
        },
    }
