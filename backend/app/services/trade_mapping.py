"""Item ↔ supplier / broker trade stats for recommendations and dashboard alignment."""

from __future__ import annotations

import math
import uuid
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Broker, TradePurchase, TradePurchaseLine
from app.models.contacts import Supplier
from app.services import trade_query as tq


def _zscores(values: list[float]) -> list[float | None]:
    if len(values) < 2:
        return [None] * len(values)
    mean = sum(values) / len(values)
    var = sum((v - mean) ** 2 for v in values) / max(len(values) - 1, 1)
    std = math.sqrt(var) if var > 0 else 0.0
    out: list[float | None] = []
    for v in values:
        if std < 1e-12:
            out.append(0.0)
        else:
            out.append((v - mean) / std)
    return out


async def item_supplier_broker_rows(
    db: AsyncSession,
    business_id: uuid.UUID,
    date_from: date,
    date_to: date,
) -> tuple[list[dict], list[dict]]:
    """
    Per (catalog_item, supplier, broker) aggregates using the same line value + status
    rules as trade reports. Returns (detail_rows, recommendation_rows) where each
    recommendation is the best vwap for items with at least one supplier with deals>=2.
    """
    amt = tq.trade_line_amount_expr()
    bf = tq.trade_purchase_date_filter(business_id, date_from, date_to)
    q = (
        select(
            TradePurchaseLine.catalog_item_id,
            func.max(TradePurchaseLine.item_name).label("item_name"),
            TradePurchase.supplier_id,
            func.coalesce(Supplier.name, "Unknown").label("supplier_name"),
            TradePurchase.broker_id,
            func.coalesce(Broker.name, "—").label("broker_name"),
            func.count(func.distinct(TradePurchase.id)).label("deals"),
            func.coalesce(func.sum(amt), 0.0).label("total_value"),
            func.coalesce(func.sum(TradePurchaseLine.qty), 0.0).label("total_qty"),
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchase.id == TradePurchaseLine.trade_purchase_id)
        .outerjoin(Supplier, Supplier.id == TradePurchase.supplier_id)
        .outerjoin(Broker, Broker.id == TradePurchase.broker_id)
        .where(
            bf,
            TradePurchaseLine.catalog_item_id.isnot(None),
            TradePurchase.supplier_id.isnot(None),
        )
        .group_by(
            TradePurchaseLine.catalog_item_id,
            TradePurchase.supplier_id,
            TradePurchase.broker_id,
            Supplier.name,
            Broker.name,
        )
    )
    rows = (await db.execute(q)).mappings().all()

    by_item: dict[uuid.UUID, list[dict]] = {}
    detail: list[dict] = []
    for r in rows:
        cid = r["catalog_item_id"]
        if cid is None:
            continue
        total_value = float(r["total_value"] or 0)
        total_qty = float(r["total_qty"] or 0)
        deals = int(r["deals"] or 0)
        vwap = (total_value / total_qty) if total_qty > 1e-12 else 0.0
        row = {
            "catalog_item_id": str(cid),
            "item_name": str(r["item_name"] or "").strip() or "—",
            "supplier_id": str(r["supplier_id"]),
            "supplier_name": str(r["supplier_name"] or "Unknown"),
            "broker_id": str(r["broker_id"]) if r["broker_id"] is not None else None,
            "broker_name": str(r["broker_name"] or "—")
            if r["broker_id"] is not None
            else None,
            "deals": deals,
            "total_qty": total_qty,
            "total_purchase": total_value,
            "volume_weighted_avg": vwap,
            "vwap_zscore": None,
        }
        detail.append(row)
        by_item.setdefault(cid, []).append(row)

    for _cid, group in by_item.items():
        with_qty = [
            (g, float(g["volume_weighted_avg"] or 0))
            for g in group
            if float(g.get("total_qty") or 0) > 1e-12
        ]
        vwaps = [v for _, v in with_qty]
        zs = _zscores(vwaps)
        for (g, _), z in zip(with_qty, zs):
            g["vwap_zscore"] = z
        for g in group:
            if float(g.get("total_qty") or 0) <= 1e-12:
                g["vwap_zscore"] = None

    recommendations: list[dict] = []
    for cid, group in by_item.items():
        candidates = [g for g in group if g["deals"] >= 2 and float(g.get("total_qty") or 0) > 1e-12]
        if not candidates:
            continue
        best = min(candidates, key=lambda g: (g["volume_weighted_avg"], g["supplier_id"]))
        item_name = best["item_name"]
        recommendations.append(
            {
                "catalog_item_id": str(cid),
                "item_name": item_name,
                "best_supplier_id": best["supplier_id"],
                "best_broker_id": best.get("broker_id"),
                "deals": best["deals"],
                "volume_weighted_avg": best["volume_weighted_avg"],
                "total_purchase": best["total_purchase"],
            }
        )

    return detail, recommendations


def consistency_score_from_zscores(zs: list[float | None]) -> float | None:
    """0–1 score: 1.0 = all z-scores near 0; None if not enough data."""
    vals = [z for z in zs if z is not None]
    if len(vals) < 2:
        return None
    mean_abs = sum(abs(v) for v in vals) / len(vals)
    return max(0.0, min(1.0, 1.0 - min(mean_abs / 3.0, 1.0)))


async def item_price_consistency(
    db: AsyncSession, business_id: uuid.UUID, date_from: date, date_to: date, catalog_item_id: uuid.UUID
) -> float | None:
    """Aggregate consistency for one catalog item (brokers/suppliers in window)."""
    detail, _ = await item_supplier_broker_rows(db, business_id, date_from, date_to)
    rows = [r for r in detail if r.get("catalog_item_id") == str(catalog_item_id)]
    zs: list[float | None] = [r.get("vwap_zscore") for r in rows]  # type: ignore[assignment]
    return consistency_score_from_zscores(zs)
