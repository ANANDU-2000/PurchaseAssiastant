import uuid
from collections import defaultdict
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import Integer, and_, case, func, literal, not_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem, ItemCategory, User
from app.models.operations import DailyUsageLog
from app.schemas.stock import StockAlertsSummaryOut
from app.models.stock_adjustment import StockAdjustmentLog
from app.models.stock_movement import StockMovement
from app.services.unit_normalization import (
    catalog_stock_unit,
    fetch_catalog_items_map,
    line_qty_in_stock_unit,
)


def stock_status(current: Decimal | None, reorder: Decimal | None) -> str:
    cur = Decimal(current or 0)
    ro = Decimal(reorder or 0)
    if cur <= 0:
        return "out"
    if ro <= 0 and Decimal("0") < cur < Decimal("1"):
        return "low"
    if ro > 0:
        if cur <= ro * Decimal("0.5"):
            return "critical"
        if cur <= ro:
            return "low"
    return "healthy"


def _days_since_last_purchase_expr(db: AsyncSession):
    """Integer days since last_purchase_at (floor at 0), SQLite + Postgres."""
    bind = db.get_bind()
    dialect = (getattr(getattr(bind, "dialect", None), "name", None) or "").lower()
    lpa = CatalogItem.last_purchase_at
    if dialect == "sqlite":
        raw = func.cast(func.julianday("now") - func.julianday(lpa), Integer)
        return case((raw < 0, 0), else_=raw)
    raw = func.floor(func.extract("epoch", func.now() - lpa) / literal(86400))
    return func.greatest(raw, 0)


def _int_count(value: Any) -> int:
    if value is None:
        return 0
    return int(value)


async def compute_stock_alerts_summary(
    db: AsyncSession,
    business_id: uuid.UUID,
) -> StockAlertsSummaryOut:
    """Single-query stock alert rollups (replaces per-row Python loop)."""
    cur = func.coalesce(CatalogItem.current_stock, 0)
    ro = func.coalesce(CatalogItem.reorder_level, 0)
    half_ro = ro * literal(0.5)

    is_out = cur <= 0
    is_critical = and_(not_(is_out), ro > 0, cur <= half_ro)
    is_low = or_(
        and_(not_(is_out), ro > 0, cur > half_ro, cur <= ro),
        and_(not_(is_out), ro <= 0, cur > 0, cur < 1),
    )
    opening_set = and_(
        CatalogItem.opening_stock_qty.isnot(None),
        CatalogItem.opening_stock_qty > 0,
    )
    is_active_out = and_(
        is_out,
        or_(opening_set, CatalogItem.last_purchase_at.isnot(None)),
    )
    barcode_missing = or_(
        CatalogItem.barcode.is_(None),
        func.trim(func.coalesce(CatalogItem.barcode, "")) == "",
    )
    code_missing = or_(
        CatalogItem.item_code.is_(None),
        func.trim(func.coalesce(CatalogItem.item_code, "")) == "",
    )
    days_since = _days_since_last_purchase_expr(db)
    is_eviction = and_(
        ItemCategory.is_perishable.is_(True),
        cur > 0,
        CatalogItem.eviction_days.isnot(None),
        CatalogItem.last_purchase_at.isnot(None),
        days_since > CatalogItem.eviction_days,
    )

    agg = await db.execute(
        select(
            func.count().label("total"),
            func.coalesce(func.sum(case((is_low, 1), else_=0)), 0).label("low"),
            func.coalesce(func.sum(case((is_critical, 1), else_=0)), 0).label(
                "critical"
            ),
            func.coalesce(func.sum(case((is_out, 1), else_=0)), 0).label("out"),
            func.coalesce(func.sum(case((is_active_out, 1), else_=0)), 0).label(
                "active_out"
            ),
            func.coalesce(func.sum(case((barcode_missing, 1), else_=0)), 0).label(
                "missing_barcode"
            ),
            func.coalesce(func.sum(case((code_missing, 1), else_=0)), 0).label(
                "missing_item_code"
            ),
            func.coalesce(func.sum(case((is_eviction, 1), else_=0)), 0).label(
                "eviction"
            ),
        )
        .select_from(CatalogItem)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    row = agg.one()
    catalog_total = _int_count(row.total)
    today = date.today()
    lr = await db.execute(
        select(func.count(DailyUsageLog.id)).where(
            DailyUsageLog.business_id == business_id,
            DailyUsageLog.usage_date == today,
        )
    )
    logged = _int_count(lr.scalar_one())
    return StockAlertsSummaryOut(
        low_stock=_int_count(row.low),
        critical_stock=_int_count(row.critical),
        out_of_stock=_int_count(row.out),
        active_out_of_stock=_int_count(row.active_out),
        missing_barcode=_int_count(row.missing_barcode),
        missing_item_code=_int_count(row.missing_item_code),
        missing_usage_logs=max(0, catalog_total - logged),
        eviction_count=_int_count(row.eviction),
        total_items=catalog_total,
    )


def catalog_stock_qty(item: CatalogItem) -> Decimal:
    return Decimal(item.current_stock or 0)


def catalog_reorder(item: CatalogItem) -> Decimal:
    return Decimal(item.reorder_level or 0)


def catalog_landing_rate(item: CatalogItem) -> Decimal:
    """Valuation rate for on-hand stock: landing cost only (never selling)."""
    for raw in (item.default_landing_cost, item.last_purchase_price):
        if raw is not None:
            rate = Decimal(raw)
            if rate > 0:
                return rate
    return Decimal(0)


def catalog_unit_key(item: CatalogItem) -> str:
    """Bucket on-hand qty into bags | boxes | tins | kg for dashboard totals."""
    unit = (
        (item.stock_unit or item.default_unit or item.selling_unit or "") or ""
    ).strip().lower()
    if "bag" in unit:
        return "bags"
    if "box" in unit:
        return "boxes"
    if "tin" in unit:
        return "tins"
    return "kg"


async def committed_purchase_delivered_qty_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> dict[uuid.UUID, Decimal]:
    """Sum qty from stock_committed purchase lines (stock unit), for legacy DBs without movements."""
    if not item_ids:
        return {}
    from app.models.trade_purchase import TradePurchase, TradePurchaseLine

    r = await db.execute(
        select(TradePurchaseLine, CatalogItem)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .join(CatalogItem, TradePurchaseLine.catalog_item_id == CatalogItem.id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.status.notin_(("cancelled", "deleted")),
            TradePurchase.delivery_status == "stock_committed",
            TradePurchaseLine.catalog_item_id.in_(item_ids),
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    totals: dict[uuid.UUID, Decimal] = defaultdict(lambda: Decimal(0))
    for line, cat_item in r.all():
        cid = line.catalog_item_id
        if cid is None:
            continue
        qty = line_qty_for_stock_commit(line, cat_item)
        if qty > 0:
            totals[cid] += qty
    return dict(totals)


async def movement_delivered_qty_map(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
) -> dict[uuid.UUID, Decimal]:
    """Lifetime qty added via committed PO deliveries (movements + legacy committed lines)."""
    movement = await movement_qty_map_by_kind(
        db,
        business_id,
        item_ids,
        kinds=("delivery_receive",),
    )
    committed = await committed_purchase_delivered_qty_map(db, business_id, item_ids)
    out: dict[uuid.UUID, Decimal] = {}
    for cid in set(movement) | set(committed):
        m = movement.get(cid, Decimal(0))
        c = committed.get(cid, Decimal(0))
        out[cid] = m if m >= c else c
    return out


async def movement_qty_map_by_kind(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_ids: list[uuid.UUID],
    *,
    kinds: tuple[str, ...],
) -> dict[uuid.UUID, Decimal]:
    if not item_ids or not kinds:
        return {}
    r = await db.execute(
        select(
            StockMovement.item_id,
            func.coalesce(func.sum(StockMovement.delta_qty), 0),
        )
        .where(
            StockMovement.business_id == business_id,
            StockMovement.item_id.in_(item_ids),
            StockMovement.movement_kind.in_(kinds),
        )
        .group_by(StockMovement.item_id)
    )
    return {row[0]: Decimal(row[1] or 0) for row in r.all()}


async def compute_inventory_summary(
    db: AsyncSession,
    business_id: uuid.UUID,
) -> dict[str, float | int]:
    """
    Point-in-time warehouse totals: sum(current_stock * landing rate) and unit buckets.
    Items without a landing rate still count toward unit buckets but not total_value_inr.
    """
    unit_expr = func.lower(
        func.coalesce(
            CatalogItem.stock_unit,
            CatalogItem.default_unit,
            CatalogItem.selling_unit,
            "",
        )
    )
    qty = func.coalesce(CatalogItem.current_stock, 0)
    rate = case(
        (
            func.coalesce(CatalogItem.default_landing_cost, 0) > 0,
            CatalogItem.default_landing_cost,
        ),
        (
            func.coalesce(CatalogItem.last_purchase_price, 0) > 0,
            CatalogItem.last_purchase_price,
        ),
        else_=0,
    )
    active = qty > 0
    value_line = case(
        (and_(active, rate > 0), qty * rate),
        else_=0,
    )
    bag_line = case(
        (and_(active, or_(unit_expr.like("%bag%"), unit_expr.like("%sack%"))), qty),
        else_=0,
    )
    box_line = case(
        (and_(active, unit_expr.like("%box%")), qty),
        else_=0,
    )
    tin_line = case(
        (and_(active, unit_expr.like("%tin%")), qty),
        else_=0,
    )
    kg_line = case(
        (
            and_(
                active,
                ~or_(
                    unit_expr.like("%bag%"),
                    unit_expr.like("%sack%"),
                    unit_expr.like("%box%"),
                    unit_expr.like("%tin%"),
                ),
            ),
            qty,
        ),
        else_=0,
    )
    row = (
        await db.execute(
            select(
                func.count().label("item_count"),
                func.coalesce(func.sum(value_line), 0).label("total_value_inr"),
                func.coalesce(func.sum(bag_line), 0).label("bags"),
                func.coalesce(func.sum(box_line), 0).label("boxes"),
                func.coalesce(func.sum(tin_line), 0).label("tins"),
                func.coalesce(func.sum(kg_line), 0).label("kg"),
            ).where(
                CatalogItem.business_id == business_id,
                CatalogItem.deleted_at.is_(None),
            )
        )
    ).mappings().one()
    return {
        "total_value_inr": float(row["total_value_inr"] or 0),
        "bags": float(row["bags"] or 0),
        "boxes": float(row["boxes"] or 0),
        "tins": float(row["tins"] or 0),
        "kg": float(row["kg"] or 0),
        "item_count": int(row["item_count"] or 0),
    }


def line_qty_for_stock_commit(line: Any, item: CatalogItem) -> Decimal:
    """Qty to add on delivery commit — uses staff [received_qty] when set."""
    recv = getattr(line, "received_qty", None)
    if recv is not None:
        recv_d = Decimal(str(recv))
        if recv_d <= 0:
            return Decimal(0)
        ordered_d = Decimal(getattr(line, "qty", 0) or 0)
        snap = getattr(line, "qty_in_stock_unit", None)
        if snap is not None and ordered_d > 0:
            from decimal import ROUND_HALF_UP

            snap_d = Decimal(str(snap))
            if snap_d > 0:
                return (snap_d * recv_d / ordered_d).quantize(
                    Decimal("0.001"), rounding=ROUND_HALF_UP
                )
        class _RecvLine:
            pass

        proxy = _RecvLine()
        proxy.qty = recv_d
        for attr in (
            "unit",
            "item_name",
            "kg_per_unit",
            "weight_per_unit",
            "total_weight",
            "qty_in_stock_unit",
        ):
            setattr(proxy, attr, getattr(line, attr, None))
        return line_qty_in_stock_unit(proxy, item)
    return line_qty_in_stock_unit(line, item)


async def _qty_by_catalog_item(
    db: AsyncSession,
    business_id: uuid.UUID,
    lines: list,
) -> dict[uuid.UUID, Decimal]:
    """Sum normalized line qty per catalog_item_id (stock unit)."""
    totals, _ = await _qty_by_catalog_item_with_skips(db, business_id, lines)
    return totals


async def _qty_by_catalog_item_with_skips(
    db: AsyncSession,
    business_id: uuid.UUID,
    lines: list,
) -> tuple[dict[uuid.UUID, Decimal], list[dict[str, Any]]]:
    totals: dict[uuid.UUID, Decimal] = defaultdict(lambda: Decimal(0))
    skipped: list[dict[str, Any]] = []
    item_ids: set[uuid.UUID] = set()
    for li in lines:
        cid = getattr(li, "catalog_item_id", None)
        if cid is not None:
            item_ids.add(uuid.UUID(str(cid)))
    items = await fetch_catalog_items_map(db, business_id, item_ids)
    for li in lines:
        cid = getattr(li, "catalog_item_id", None)
        if cid is None:
            continue
        cid_u = uuid.UUID(str(cid))
        item = items.get(cid_u)
        if not item:
            continue
        raw_qty = Decimal(getattr(li, "received_qty", None) or getattr(li, "qty", 0) or 0)
        qty = line_qty_for_stock_commit(li, item)
        if raw_qty > 0 and qty <= 0:
            skipped.append(
                {
                    "catalog_item_id": cid_u,
                    "name": item.name,
                    "unit": catalog_stock_unit(item),
                    "line_unit": getattr(li, "unit", None),
                    "needs_unit_setup": True,
                    "old_qty": catalog_stock_qty(item),
                    "new_qty": catalog_stock_qty(item),
                    "delta": Decimal(0),
                }
            )
            continue
        if qty <= 0:
            continue
        totals[cid_u] += qty
    return dict(totals), skipped


async def _apply_catalog_stock_deltas(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    deltas: dict[uuid.UUID, Decimal],
    *,
    reason: str,
    adjustment_type: str = "purchase",
    touch_last_purchase_at: bool = False,
) -> list[dict]:
    """Apply signed qty deltas; rejects if on-hand would go negative."""
    if not deltas:
        return []
    ur = await db.execute(select(User).where(User.id == user_id))
    user = ur.scalar_one_or_none()
    display = (user.name or user.username or user.email) if user else "System"
    updates: list[dict] = []
    for cid, delta in deltas.items():
        if delta == 0:
            continue
        r = await db.execute(
            select(CatalogItem).where(
                CatalogItem.id == cid,
                CatalogItem.business_id == business_id,
                CatalogItem.deleted_at.is_(None),
            )
        )
        item = r.scalar_one_or_none()
        if not item:
            continue
        old_qty = catalog_stock_qty(item)
        new_qty = old_qty + delta
        if new_qty < 0:
            raise ValueError(
                f"Stock cannot be negative for {item.name or item.id} "
                f"(on hand {old_qty}, adjustment {delta})"
            )
        unit = item.stock_unit or item.default_unit or item.selling_unit
        db.add(
            StockAdjustmentLog(
                business_id=business_id,
                item_id=item.id,
                old_qty=old_qty,
                new_qty=new_qty,
                adjustment_type=adjustment_type,
                reason=reason,
                updated_by=user_id,
                updated_by_name=display,
            )
        )
        item.current_stock = new_qty
        item.last_stock_updated_at = datetime.now(timezone.utc)
        item.last_stock_updated_by = display
        if touch_last_purchase_at and delta > 0:
            item.last_purchase_at = datetime.now(timezone.utc)
        updates.append(
            {
                "catalog_item_id": item.id,
                "name": item.name,
                "unit": unit,
                "old_qty": old_qty,
                "new_qty": new_qty,
                "delta": delta,
            }
        )
    return updates


async def purchase_delivery_stock_already_applied(
    db: AsyncSession,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
) -> bool:
    """True if stock was already incremented for this purchase (idempotent delivery).

    Checks stock_movements first; falls back to legacy adjustment_log rows.
    """
    marker = f"trade_purchase:{purchase_id}"
    r2 = await db.execute(
        select(func.count())
        .select_from(StockMovement)
        .where(
            StockMovement.business_id == business_id,
            StockMovement.idempotency_key.like(f"{marker}:%"),
        )
    )
    if int(r2.scalar_one() or 0) > 0:
        return True
    from app.models.trade_purchase import TradePurchase

    tp_r = await db.execute(
        select(TradePurchase.human_id).where(
            TradePurchase.id == purchase_id,
            TradePurchase.business_id == business_id,
        )
    )
    human = tp_r.scalar_one_or_none()
    if not human:
        return False
    label = str(human).strip()
    r3 = await db.execute(
        select(func.count())
        .select_from(StockAdjustmentLog)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.adjustment_type == "purchase",
            StockAdjustmentLog.reason.ilike(f"%{label}%"),
        )
    )
    return int(r3.scalar_one() or 0) > 0


async def apply_confirmed_purchase_stock(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    lines: list,
    *,
    purchase_human_id: str | None = None,
    purchase_id: uuid.UUID | None = None,
    actor: User | None = None,
) -> list[dict]:
    """Increment catalog stock when a purchase delivery is committed."""
    if purchase_id is None or actor is None:
        raise ValueError("purchase_id and actor are required for delivery commit")

    if await purchase_delivery_stock_already_applied(db, business_id, purchase_id):
        return []

    by_item, skipped = await _qty_by_catalog_item_with_skips(db, business_id, lines)
    if not by_item and not skipped:
        return list(skipped)

    label = purchase_human_id or str(purchase_id)
    reason = f"Purchase received ({label})".strip()

    from app.services.stock_movement_service import apply_stock_movement_with_retry

    updates: list[dict] = list(skipped)
    for cid, delta in by_item.items():
        if delta <= 0:
            continue
        idem = f"trade_purchase:{purchase_id}:{cid}"
        result = await apply_stock_movement_with_retry(
            db,
            business_id=business_id,
            item_id=cid,
            user=actor,
            movement_kind="delivery_receive",
            mode="delta",
            qty=delta,
            reason=reason,
            source_type="trade_purchase",
            source_id=purchase_id,
            idempotency_key=idem,
            metadata={"purchase_id": str(purchase_id), "human_id": label},
        )
        item = result.item
        unit = item.stock_unit or item.default_unit or item.selling_unit
        if result.duplicate:
            continue
        if delta > 0:
            item.last_purchase_at = datetime.now(timezone.utc)
        updates.append(
            {
                "catalog_item_id": item.id,
                "name": item.name,
                "unit": unit,
                "old_qty": result.movement.qty_before,
                "new_qty": result.movement.qty_after,
                "delta": delta,
                "needs_unit_setup": False,
            }
        )
    return updates


async def revert_confirmed_purchase_stock(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    lines: list,
    *,
    purchase_human_id: str | None = None,
    purchase_id: uuid.UUID | None = None,
    actor: User | None = None,
) -> list[dict]:
    """Decrement stock for a previously delivered purchase via movement ledger."""
    if purchase_id is None:
        raise ValueError("purchase_id is required for stock reversal")
    if actor is None:
        ur = await db.execute(select(User).where(User.id == user_id))
        actor = ur.scalar_one_or_none()
    if actor is None:
        raise ValueError("actor user not found for stock reversal")

    by_item = await _qty_by_catalog_item(db, business_id, lines)
    if not by_item:
        return []

    from app.services.stock_movement_service import apply_stock_movement_with_retry

    label = purchase_human_id or str(purchase_id)
    reason = f"Purchase reversed ({label})".strip()
    updates: list[dict] = []
    for cid, qty in by_item.items():
        if qty <= 0:
            continue
        idem = f"revert:trade_purchase:{purchase_id}:{cid}"
        result = await apply_stock_movement_with_retry(
            db,
            business_id=business_id,
            item_id=cid,
            user=actor,
            movement_kind="delivery_revoke",
            mode="delta",
            qty=-qty,
            reason=reason,
            source_type="trade_purchase",
            source_id=purchase_id,
            idempotency_key=idem,
            metadata={"purchase_id": str(purchase_id), "human_id": label},
        )
        if result.duplicate:
            continue
        item = result.item
        unit = item.stock_unit or item.default_unit or item.selling_unit
        updates.append(
            {
                "catalog_item_id": item.id,
                "name": item.name,
                "unit": unit,
                "old_qty": result.movement.qty_before,
                "new_qty": result.movement.qty_after,
                "delta": -qty,
            }
        )
    return updates


async def sync_confirmed_purchase_stock_diff(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    old_lines: list,
    new_lines: list,
    *,
    purchase_human_id: str | None = None,
    purchase_id: uuid.UUID | None = None,
    actor: User | None = None,
) -> list[dict]:
    """Apply qty delta when editing a stock-committed purchase.

    Uses ``line_qty_for_stock_commit`` (staff ``received_qty`` when set) per line.
    """
    old_map = await _qty_by_catalog_item(db, business_id, old_lines)
    new_map = await _qty_by_catalog_item(db, business_id, new_lines)
    all_ids = set(old_map) | set(new_map)
    deltas: dict[uuid.UUID, Decimal] = {}
    for cid in all_ids:
        delta = new_map.get(cid, Decimal(0)) - old_map.get(cid, Decimal(0))
        if delta != 0:
            deltas[cid] = delta
    if not deltas:
        return []
    if purchase_id is None:
        raise ValueError("purchase_id is required for committed purchase sync")
    if actor is None:
        ur = await db.execute(select(User).where(User.id == user_id))
        actor = ur.scalar_one_or_none()
    if actor is None:
        raise ValueError("actor user not found for purchase sync")

    from app.services.stock_movement_service import apply_stock_movement_with_retry

    label = purchase_human_id or str(purchase_id)
    reason = f"Purchase adjusted ({label})"
    updates: list[dict] = []
    for cid, delta in deltas.items():
        idem = f"adjust:trade_purchase:{purchase_id}:{cid}:{delta}"
        result = await apply_stock_movement_with_retry(
            db,
            business_id=business_id,
            item_id=cid,
            user=actor,
            movement_kind="delivery_adjustment",
            mode="delta",
            qty=delta,
            reason=reason,
            source_type="trade_purchase",
            source_id=purchase_id,
            idempotency_key=idem,
            metadata={"purchase_id": str(purchase_id), "human_id": label},
        )
        if result.duplicate:
            continue
        item = result.item
        if delta > 0:
            item.last_purchase_at = datetime.now(timezone.utc)
        unit = item.stock_unit or item.default_unit or item.selling_unit
        updates.append(
            {
                "catalog_item_id": item.id,
                "name": item.name,
                "unit": unit,
                "old_qty": result.movement.qty_before,
                "new_qty": result.movement.qty_after,
                "delta": delta,
            }
        )
    return updates
