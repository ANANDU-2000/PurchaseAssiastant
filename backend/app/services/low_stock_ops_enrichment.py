"""Lifecycle and dispute enrichment for low-stock operations rows."""

from __future__ import annotations

import uuid
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.reorder_list import ReorderListEntry
from app.models.stock_audit import StockAudit, StockAuditItem
from app.models.stock_dispute_case import StockDisputeCase
from app.schemas.stock import StockListItemOut
from app.services.low_stock_priority import compute_low_stock_priority


def derive_lifecycle_stage(
    item: StockListItemOut,
    *,
    reorder_entry_status: str | None,
    has_open_dispute: bool,
) -> str:
    """Map existing trade/reorder/audit signals to a UI lifecycle enum."""
    cur = float(item.current_stock or 0)
    if cur <= 0 or item.stock_status.lower() == "out":
        return "out"
    if item.has_pending_order:
        days = item.pending_order_days or 0
        if days >= 7:
            return "delayed"
        return "ordered"
    if has_open_dispute:
        return "disputed"
    if item.needs_verification:
        return "verification"
    if reorder_entry_status == "pending":
        return "reorder_requested"
    if reorder_entry_status in ("ordered", "done"):
        return "reorder_done"
    if item.stock_status.lower() in ("low", "critical"):
        return "low"
    return "attention"


async def reorder_status_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> dict[uuid.UUID, str]:
    if not item_ids:
        return {}
    r = await db.execute(
        select(ReorderListEntry.item_id, ReorderListEntry.status).where(
            ReorderListEntry.business_id == business_id,
            ReorderListEntry.item_id.in_(item_ids),
        )
    )
    out: dict[uuid.UUID, str] = {}
    for iid, status in r.all():
        if iid is not None:
            out[iid] = (status or "pending").lower()
    return out


async def open_dispute_item_ids(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> set[uuid.UUID]:
    if not item_ids:
        return set()
    try:
        r = await db.execute(
            select(StockDisputeCase.item_id).where(
                StockDisputeCase.business_id == business_id,
                StockDisputeCase.item_id.in_(item_ids),
                StockDisputeCase.status == "open",
            )
        )
        return {row[0] for row in r.all() if row[0] is not None}
    except Exception:
        return set()


async def rejected_audit_item_ids(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> set[uuid.UUID]:
    """V1 disputed signal: audit lines explicitly rejected."""
    if not item_ids:
        return set()
    r = await db.execute(
        select(StockAuditItem.item_id)
        .join(StockAudit, StockAudit.id == StockAuditItem.audit_id)
        .where(
            StockAudit.business_id == business_id,
            StockAuditItem.item_id.in_(item_ids),
            StockAuditItem.line_status == "rejected",
        )
    )
    return {row[0] for row in r.all() if row[0] is not None}


def item_is_disputed(
    item: StockListItemOut,
    *,
    open_disputes: set[uuid.UUID],
    rejected_audits: set[uuid.UUID],
) -> bool:
    pr = compute_low_stock_priority(item)
    if pr.mismatch_flag:
        return True
    if item.id in open_disputes:
        return True
    if item.id in rejected_audits:
        return True
    phys = item.physical_stock_difference_qty
    if phys is not None and abs(Decimal(phys)) > Decimal("0.001"):
        return True
    return False
