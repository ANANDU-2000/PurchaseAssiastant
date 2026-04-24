"""Business logic for trade purchases (human IDs, duplicates, totals)."""

from __future__ import annotations

import json
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import CatalogItem, SupplierItemDefault, TradePurchase, TradePurchaseDraft, TradePurchaseLine
from app.schemas.trade_purchases import (
    TradeDuplicateCheckRequest,
    TradeDuplicateCheckResponse,
    TradeDraftOut,
    TradeMarkPaidRequest,
    TradePurchaseCreateRequest,
    TradePurchaseLineIn,
    TradePurchaseLineOut,
    TradePurchaseOut,
    TradePurchasePaymentPatch,
    TradePurchaseUpdateRequest,
)
from app.services.purchase_status import compute_status


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _trade_purchase_load_opts() -> tuple:
    return (
        selectinload(TradePurchase.lines).selectinload(TradePurchaseLine.catalog_item),
        selectinload(TradePurchase.supplier_row),
        selectinload(TradePurchase.broker_row),
    )


def _due_date_from(purchase_date: date, payment_days: int | None) -> date | None:
    if payment_days is None:
        return None
    return purchase_date + timedelta(days=int(payment_days))


def _dec(x: float | Decimal | None) -> Decimal:
    if x is None:
        return Decimal("0")
    if isinstance(x, Decimal):
        return x
    return Decimal(str(x))


def _line_fp(
    name: str,
    qty: float,
    landing: float,
    discount: float | None,
    tax_percent: float | None,
    kg_per_unit: float | None = None,
    per_kg: float | None = None,
) -> str:
    d = float(discount or 0)
    t = float(tax_percent or 0)
    kpu = float(kg_per_unit) if kg_per_unit is not None else 0.0
    pk = float(per_kg) if per_kg is not None else 0.0
    return f"{name.strip().lower()}|{qty:.4f}|{float(landing):.4f}|{d:.4f}|{t:.4f}|{kpu:.4f}|{pk:.4f}"


def _fingerprint_lines_from_lines(lines: list[TradePurchaseLine]) -> str:
    parts = sorted(
        _line_fp(
            li.item_name,
            float(li.qty),
            float(li.landing_cost),
            float(li.discount) if li.discount is not None else None,
            float(li.tax_percent) if li.tax_percent is not None else None,
            float(li.kg_per_unit) if getattr(li, "kg_per_unit", None) is not None else None,
            float(li.landing_cost_per_kg) if getattr(li, "landing_cost_per_kg", None) is not None else None,
        )
        for li in lines
    )
    return "|".join(parts)


def _fingerprint_lines_from_in(lines: list[TradePurchaseLineIn]) -> str:
    parts = sorted(
        _line_fp(
            li.item_name,
            float(li.qty),
            float(li.landing_cost),
            float(li.discount) if li.discount is not None else None,
            float(li.tax_percent) if li.tax_percent is not None else None,
            float(li.kg_per_unit) if li.kg_per_unit is not None else None,
            float(li.landing_cost_per_kg) if li.landing_cost_per_kg is not None else None,
        )
        for li in lines
    )
    return "|".join(parts)


def _line_gross_base(li: TradePurchaseLineIn) -> Decimal:
    if li.kg_per_unit is not None and li.landing_cost_per_kg is not None:
        return _dec(li.qty) * _dec(li.kg_per_unit) * _dec(li.landing_cost_per_kg)
    return _dec(li.qty) * _dec(li.landing_cost)


def _line_money(li: TradePurchaseLineIn) -> Decimal:
    base = _line_gross_base(li)
    ld = _dec(li.discount) if li.discount is not None else Decimal("0")
    after_disc = base * (Decimal("1") - min(ld, Decimal("100")) / Decimal("100"))
    tax = _dec(li.tax_percent) if li.tax_percent is not None else Decimal("0")
    return after_disc * (Decimal("1") + min(tax, Decimal("1000")) / Decimal("100"))


def compute_totals(req: TradePurchaseCreateRequest) -> tuple[Decimal, Decimal]:
    qty_sum = sum(_dec(li.qty) for li in req.lines)
    amt_sum = sum(_line_money(li) for li in req.lines)
    header_disc = _dec(req.discount) if req.discount is not None else Decimal("0")
    after_header = amt_sum
    if header_disc > 0:
        after_header = amt_sum * (Decimal("1") - min(header_disc, Decimal("100")) / Decimal("100"))
    amt_sum = after_header
    freight = _dec(req.freight_amount) if req.freight_amount is not None else Decimal("0")
    if req.freight_type == "included":
        freight = Decimal("0")
    amt_sum += freight
    comm = _dec(req.commission_percent) if req.commission_percent is not None else Decimal("0")
    if comm > 0:
        amt_sum += after_header * min(comm, Decimal("100")) / Decimal("100")
    return qty_sum, amt_sum


async def _sync_purchase_memory(
    db: AsyncSession,
    business_id: uuid.UUID,
    body: TradePurchaseCreateRequest,
) -> None:
    """Update item master last price and supplier-item default rows."""
    for li in body.lines:
        if li.catalog_item_id is None:
            continue
        ir = await db.execute(
            select(CatalogItem).where(
                CatalogItem.id == li.catalog_item_id,
                CatalogItem.business_id == business_id,
            )
        )
        item = ir.scalar_one_or_none()
        if item is not None:
            item.last_purchase_price = float(li.landing_cost)
        if body.supplier_id is None:
            continue
        dr = await db.execute(
            select(SupplierItemDefault).where(
                SupplierItemDefault.business_id == business_id,
                SupplierItemDefault.supplier_id == body.supplier_id,
                SupplierItemDefault.catalog_item_id == li.catalog_item_id,
            )
        )
        row = dr.scalar_one_or_none()
        line_pd = li.payment_days if li.payment_days is not None else body.payment_days
        if row is None:
            db.add(
                SupplierItemDefault(
                    business_id=business_id,
                    supplier_id=body.supplier_id,
                    catalog_item_id=li.catalog_item_id,
                    last_price=float(li.landing_cost),
                    last_discount=float(li.discount) if li.discount is not None else None,
                    last_payment_days=line_pd,
                    purchase_count=1,
                )
            )
        else:
            row.purchase_count = int(row.purchase_count or 0) + 1
            row.last_price = float(li.landing_cost)
            if li.discount is not None:
                row.last_discount = float(li.discount)
            if line_pd is not None:
                row.last_payment_days = line_pd


async def next_human_id(db: AsyncSession, business_id: uuid.UUID) -> str:
    year = date.today().year
    prefix = f"PUR-{year}-"
    q = await db.execute(
        select(TradePurchase.human_id).where(
            TradePurchase.business_id == business_id,
            TradePurchase.human_id.like(f"{prefix}%"),
        )
    )
    best = 0
    for (hid,) in q.all():
        if not isinstance(hid, str) or not hid.startswith(prefix):
            continue
        tail = hid.removeprefix(prefix)
        try:
            best = max(best, int(tail))
        except ValueError:
            continue
    return f"{prefix}{best + 1:04d}"


async def check_duplicate(
    db: AsyncSession,
    business_id: uuid.UUID,
    body: TradeDuplicateCheckRequest,
) -> TradeDuplicateCheckResponse:
    want_fp = _fingerprint_lines_from_in(body.lines)
    target_total = _dec(body.total_amount)

    q = select(TradePurchase).where(
        TradePurchase.business_id == business_id,
        TradePurchase.purchase_date == body.purchase_date,
    )
    if body.supplier_id is not None:
        q = q.where(TradePurchase.supplier_id == body.supplier_id)
    else:
        q = q.where(TradePurchase.supplier_id.is_(None))
    q = q.options(selectinload(TradePurchase.lines))
    res = await db.execute(q)
    for p in res.scalars().unique().all():
        if abs(_dec(p.total_amount) - target_total) > Decimal("1.0"):
            continue
        got_fp = _fingerprint_lines_from_lines(list(p.lines))
        if got_fp == want_fp:
            return TradeDuplicateCheckResponse(
                duplicate=True,
                message="A purchase with the same lines and total already exists for this date.",
                existing_id=p.id,
                existing_human_id=p.human_id,
            )
    return TradeDuplicateCheckResponse(
        duplicate=False, message=None, existing_id=None, existing_human_id=None
    )


async def list_trade_purchases(
    db: AsyncSession,
    business_id: uuid.UUID,
    limit: int = 100,
    *,
    status_filter: str | None = None,
    q: str | None = None,
    supplier_id: uuid.UUID | None = None,
    broker_id: uuid.UUID | None = None,
) -> list[TradePurchaseOut]:
    """List purchases; optional status_filter: all|draft|due_soon|overdue|paid and search q."""
    has_entity_filter = supplier_id is not None or broker_id is not None
    if has_entity_filter:
        fetch_cap = min(max(limit, 1), 500)
    else:
        fetch_cap = (
            min(max(limit * 5, limit), 500)
            if (status_filter and status_filter != "all") or q
            else min(limit, 500)
        )
    stmt = (
        select(TradePurchase)
        .where(TradePurchase.business_id == business_id)
        .options(*_trade_purchase_load_opts())
        .order_by(TradePurchase.purchase_date.desc(), TradePurchase.created_at.desc())
    )
    if supplier_id is not None:
        stmt = stmt.where(TradePurchase.supplier_id == supplier_id)
    if broker_id is not None:
        stmt = stmt.where(TradePurchase.broker_id == broker_id)
    stmt = stmt.limit(fetch_cap)
    res = await db.execute(stmt)
    rows = [trade_purchase_to_out(p) for p in res.scalars().unique().all()]
    sf = (status_filter or "all").strip().lower()
    if sf == "draft":
        rows = [r for r in rows if (r.status or "").lower() in ("draft", "saved")]
    elif sf == "due_soon":
        rows = [r for r in rows if r.derived_status == "due_soon"]
    elif sf == "overdue":
        rows = [r for r in rows if r.derived_status == "overdue"]
    elif sf == "paid":
        rows = [r for r in rows if r.derived_status == "paid"]
    needle = (q or "").strip().lower()
    if needle:
        out: list[TradePurchaseOut] = []
        for r in rows:
            if needle in (r.human_id or "").lower():
                out.append(r)
                continue
            if needle in (r.supplier_name or "").lower():
                out.append(r)
                continue
            if needle in (r.broker_name or "").lower():
                out.append(r)
                continue
            for li in r.lines:
                if needle in (li.item_name or "").lower():
                    out.append(r)
                    break
        rows = out
    return rows[: min(limit, 500)]


async def get_trade_purchase(
    db: AsyncSession, business_id: uuid.UUID, purchase_id: uuid.UUID
) -> TradePurchaseOut | None:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(*_trade_purchase_load_opts())
    )
    p = res.scalar_one_or_none()
    return trade_purchase_to_out(p) if p else None


async def create_trade_purchase(
    db: AsyncSession,
    business_id: uuid.UUID,
    user_id: uuid.UUID,
    body: TradePurchaseCreateRequest,
) -> TradePurchaseOut:
    if not body.lines:
        raise ValueError("At least one line item is required")
    initial_status = body.status if body.status in ("draft", "saved", "confirmed") else "confirmed"
    if initial_status == "confirmed":
        if body.supplier_id is None:
            raise ValueError("confirmed purchase requires supplier_id")
        for i, li in enumerate(body.lines):
            if li.landing_cost <= 0:
                raise ValueError(f"line {i + 1}: landing cost must be greater than 0")
    human_id = await next_human_id(db, business_id)
    qty_sum, amt_sum = compute_totals(body)
    due = _due_date_from(body.purchase_date, body.payment_days)
    inv = (body.invoice_number.strip() if body.invoice_number else None) or None
    tp = TradePurchase(
        business_id=business_id,
        user_id=user_id,
        human_id=human_id,
        invoice_number=inv,
        purchase_date=body.purchase_date,
        supplier_id=body.supplier_id,
        broker_id=body.broker_id,
        payment_days=body.payment_days,
        due_date=due,
        paid_amount=0.0,
        paid_at=None,
        discount=float(body.discount) if body.discount is not None else None,
        commission_percent=float(body.commission_percent)
        if body.commission_percent is not None
        else None,
        delivered_rate=float(body.delivered_rate) if body.delivered_rate is not None else None,
        billty_rate=float(body.billty_rate) if body.billty_rate is not None else None,
        freight_amount=float(body.freight_amount) if body.freight_amount is not None else None,
        freight_type=body.freight_type,
        total_qty=float(qty_sum),
        total_amount=float(amt_sum),
        status=initial_status,
    )
    db.add(tp)
    await db.flush()
    for li in body.lines:
        db.add(
            TradePurchaseLine(
                trade_purchase_id=tp.id,
                catalog_item_id=li.catalog_item_id,
                item_name=li.item_name,
                qty=li.qty,
                unit=li.unit,
                landing_cost=li.landing_cost,
                kg_per_unit=li.kg_per_unit,
                landing_cost_per_kg=li.landing_cost_per_kg,
                selling_cost=li.selling_cost,
                discount=li.discount,
                tax_percent=li.tax_percent,
                payment_days=li.payment_days,
                hsn_code=(li.hsn_code.strip() if (li.hsn_code and li.hsn_code.strip()) else None),
                description=(li.description.strip() if (li.description and li.description.strip()) else None),
            )
        )
    await _sync_purchase_memory(db, business_id, body)
    await db.commit()
    res = await db.execute(
        select(TradePurchase)
        .where(TradePurchase.id == tp.id)
        .options(*_trade_purchase_load_opts())
    )
    loaded = res.scalar_one()
    return trade_purchase_to_out(loaded)


async def update_trade_purchase(
    db: AsyncSession,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchaseUpdateRequest,
) -> TradePurchaseOut | None:
    if not body.lines:
        raise ValueError("At least one line item is required")
    new_status = body.status if body.status in ("draft", "saved", "confirmed") else "confirmed"
    if new_status == "confirmed":
        if body.supplier_id is None:
            raise ValueError("confirmed purchase requires supplier_id")
        for i, li in enumerate(body.lines):
            if li.landing_cost <= 0:
                raise ValueError(f"line {i + 1}: landing cost must be greater than 0")
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(selectinload(TradePurchase.lines))
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return None
    if (tp.status or "").lower() == "cancelled":
        raise ValueError("Cannot edit a cancelled purchase")
    qty_sum, amt_sum = compute_totals(body)
    tp.purchase_date = body.purchase_date
    tp.invoice_number = (body.invoice_number.strip() if body.invoice_number else None) or None
    tp.supplier_id = body.supplier_id
    tp.broker_id = body.broker_id
    tp.payment_days = body.payment_days
    tp.due_date = _due_date_from(body.purchase_date, body.payment_days)
    tp.discount = float(body.discount) if body.discount is not None else None
    tp.commission_percent = float(body.commission_percent) if body.commission_percent is not None else None
    tp.delivered_rate = float(body.delivered_rate) if body.delivered_rate is not None else None
    tp.billty_rate = float(body.billty_rate) if body.billty_rate is not None else None
    tp.freight_amount = float(body.freight_amount) if body.freight_amount is not None else None
    tp.freight_type = body.freight_type
    tp.total_qty = float(qty_sum)
    tp.total_amount = float(amt_sum)
    if body.status in ("draft", "saved", "confirmed"):
        tp.status = body.status
    await db.execute(delete(TradePurchaseLine).where(TradePurchaseLine.trade_purchase_id == tp.id))
    await db.flush()
    for li in body.lines:
        db.add(
            TradePurchaseLine(
                trade_purchase_id=tp.id,
                catalog_item_id=li.catalog_item_id,
                item_name=li.item_name,
                qty=li.qty,
                unit=li.unit,
                landing_cost=li.landing_cost,
                selling_cost=li.selling_cost,
                discount=li.discount,
                tax_percent=li.tax_percent,
                payment_days=li.payment_days,
                hsn_code=(li.hsn_code.strip() if (li.hsn_code and li.hsn_code.strip()) else None),
                description=(li.description.strip() if (li.description and li.description.strip()) else None),
            )
        )
    # Re-sync paid vs new total: clamp paid_amount
    total_dec = _dec(tp.total_amount)
    paid_dec = _dec(tp.paid_amount)
    if paid_dec > total_dec:
        tp.paid_amount = float(total_dec)
    tp.updated_at = utcnow()
    await _sync_purchase_memory(db, business_id, body)
    await db.commit()
    res2 = await db.execute(
        select(TradePurchase)
        .where(TradePurchase.id == tp.id)
        .options(*_trade_purchase_load_opts())
    )
    return trade_purchase_to_out(res2.scalar_one())


async def patch_trade_purchase_payment(
    db: AsyncSession,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchasePaymentPatch,
) -> TradePurchaseOut | None:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(*_trade_purchase_load_opts())
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return None
    if (tp.status or "").lower() in ("cancelled", "draft"):
        raise ValueError("Payment not allowed for this purchase state")
    total = _dec(tp.total_amount)
    paid = min(max(_dec(body.paid_amount), Decimal("0")), total)
    tp.paid_amount = float(paid)
    tp.paid_at = body.paid_at or utcnow()
    tp.updated_at = utcnow()
    derived = compute_status(
        stored_status=tp.status or "confirmed",
        total_amount=total,
        paid_amount=paid,
        due_date=tp.due_date,
    )
    if (tp.status or "").lower() not in ("draft", "cancelled"):
        tp.status = derived
    await db.commit()
    return await get_trade_purchase(db, business_id, purchase_id)


async def mark_trade_purchase_paid(
    db: AsyncSession,
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradeMarkPaidRequest,
) -> TradePurchaseOut | None:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(*_trade_purchase_load_opts())
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return None
    if (tp.status or "").lower() in ("cancelled", "draft"):
        raise ValueError("Payment not allowed for this purchase state")
    total = _dec(tp.total_amount)
    if body.paid_amount is None:
        new_paid = total
    else:
        new_paid = min(max(_dec(body.paid_amount), Decimal("0")), total)
    tp.paid_amount = float(new_paid)
    tp.paid_at = body.paid_at or utcnow()
    tp.updated_at = utcnow()
    derived = compute_status(
        stored_status=tp.status or "confirmed",
        total_amount=total,
        paid_amount=_dec(tp.paid_amount),
        due_date=tp.due_date,
    )
    tp.status = derived
    await db.commit()
    return await get_trade_purchase(db, business_id, purchase_id)


async def cancel_trade_purchase(
    db: AsyncSession, business_id: uuid.UUID, purchase_id: uuid.UUID
) -> TradePurchaseOut | None:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(*_trade_purchase_load_opts())
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return None
    tp.status = "cancelled"
    tp.updated_at = utcnow()
    await db.commit()
    return await get_trade_purchase(db, business_id, purchase_id)


async def delete_trade_purchase(
    db: AsyncSession, business_id: uuid.UUID, purchase_id: uuid.UUID
) -> bool:
    res = await db.execute(
        select(TradePurchase).where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
    )
    tp = res.scalar_one_or_none()
    if not tp:
        return False
    await db.delete(tp)
    await db.commit()
    return True


def _line_hsn(li: TradePurchaseLine) -> str | None:
    raw = getattr(li, "hsn_code", None)
    if raw is not None and str(raw).strip():
        return str(raw).strip()
    ci = getattr(li, "catalog_item", None)
    if ci is None:
        return None
    h = getattr(ci, "hsn_code", None)
    if h is None:
        return None
    s = str(h).strip()
    return s or None


def _catalog_item_unit_hints(li: TradePurchaseLine) -> tuple[str | None, float | None, str | None]:
    ci = getattr(li, "catalog_item", None)
    if ci is None:
        return None, None, None
    du = getattr(ci, "default_unit", None)
    dpu = getattr(ci, "default_purchase_unit", None)
    kpb = getattr(ci, "default_kg_per_bag", None)
    du_s = str(du).strip().lower() if du is not None and str(du).strip() else None
    dpu_s = str(dpu).strip().lower() if dpu is not None and str(dpu).strip() else None
    kpb_f = float(kpb) if kpb is not None else None
    return du_s, kpb_f, dpu_s


def trade_purchase_to_out(tp: TradePurchase) -> TradePurchaseOut:
    lines = []
    for li in tp.lines:
        du_s, kpb_f, dpu_s = _catalog_item_unit_hints(li)
        lines.append(
            TradePurchaseLineOut(
                id=li.id,
                catalog_item_id=li.catalog_item_id,
                item_name=li.item_name,
                qty=float(li.qty),
                unit=li.unit,
                landing_cost=float(li.landing_cost),
                kg_per_unit=float(li.kg_per_unit) if getattr(li, "kg_per_unit", None) is not None else None,
                landing_cost_per_kg=float(li.landing_cost_per_kg)
                if getattr(li, "landing_cost_per_kg", None) is not None
                else None,
                selling_cost=float(li.selling_cost) if li.selling_cost is not None else None,
                discount=float(li.discount) if li.discount is not None else None,
                tax_percent=float(li.tax_percent) if li.tax_percent is not None else None,
                payment_days=getattr(li, "payment_days", None),
                hsn_code=_line_hsn(li),
                description=getattr(li, "description", None),
                default_unit=du_s,
                default_kg_per_bag=kpb_f,
                default_purchase_unit=dpu_s,
            )
        )
    total_dec = _dec(tp.total_amount)
    paid_dec = _dec(getattr(tp, "paid_amount", None))
    remaining = float(max(total_dec - paid_dec, Decimal("0")))
    stored = tp.status or "confirmed"
    due = getattr(tp, "due_date", None)
    derived = compute_status(
        stored_status=stored,
        total_amount=total_dec,
        paid_amount=paid_dec,
        due_date=due,
    )
    sup_name: str | None = None
    bro_name: str | None = None
    supplier_gst: str | None = None
    supplier_address: str | None = None
    supplier_phone: str | None = None
    supplier_whatsapp: str | None = None
    broker_phone: str | None = None
    broker_location: str | None = None
    sr = getattr(tp, "supplier_row", None)
    if sr is not None:
        sup_name = getattr(sr, "name", None)
        supplier_gst = getattr(sr, "gst_number", None) or None
        supplier_address = getattr(sr, "address", None) or None
        supplier_phone = getattr(sr, "phone", None) or None
        supplier_whatsapp = getattr(sr, "whatsapp_number", None) or None
    br = getattr(tp, "broker_row", None)
    if br is not None:
        bro_name = getattr(br, "name", None)
        broker_phone = getattr(br, "phone", None) or None
        broker_location = getattr(br, "location", None) or None
    items_count = len(tp.lines) if tp.lines is not None else 0
    return TradePurchaseOut(
        id=tp.id,
        human_id=tp.human_id,
        invoice_number=getattr(tp, "invoice_number", None),
        purchase_date=tp.purchase_date,
        supplier_id=tp.supplier_id,
        broker_id=tp.broker_id,
        payment_days=tp.payment_days,
        due_date=due,
        paid_amount=float(paid_dec),
        paid_at=getattr(tp, "paid_at", None),
        discount=float(tp.discount) if tp.discount is not None else None,
        commission_percent=float(tp.commission_percent) if tp.commission_percent is not None else None,
        delivered_rate=float(tp.delivered_rate) if tp.delivered_rate is not None else None,
        billty_rate=float(tp.billty_rate) if tp.billty_rate is not None else None,
        freight_amount=float(tp.freight_amount) if tp.freight_amount is not None else None,
        freight_type=getattr(tp, "freight_type", None),
        total_qty=float(tp.total_qty) if tp.total_qty is not None else None,
        total_amount=float(tp.total_amount),
        status=stored,
        remaining=remaining,
        derived_status=derived,
        items_count=items_count,
        supplier_name=sup_name,
        broker_name=bro_name,
        supplier_gst=supplier_gst,
        supplier_address=supplier_address,
        supplier_phone=supplier_phone,
        supplier_whatsapp=supplier_whatsapp,
        broker_phone=broker_phone,
        broker_location=broker_location,
        created_at=tp.created_at,
        updated_at=getattr(tp, "updated_at", None),
        lines=lines,
    )


async def get_draft(db: AsyncSession, business_id: uuid.UUID, user_id: uuid.UUID) -> TradeDraftOut | None:
    q = await db.execute(
        select(TradePurchaseDraft).where(
            TradePurchaseDraft.business_id == business_id,
            TradePurchaseDraft.user_id == user_id,
        )
    )
    d = q.scalar_one_or_none()
    if not d:
        return None
    try:
        payload = json.loads(d.payload_json or "{}")
    except json.JSONDecodeError:
        payload = {}
    return TradeDraftOut(step=d.step, payload=payload, updated_at=d.updated_at)


async def upsert_draft(
    db: AsyncSession, business_id: uuid.UUID, user_id: uuid.UUID, step: int, payload: dict
) -> TradeDraftOut:
    q = await db.execute(
        select(TradePurchaseDraft).where(
            TradePurchaseDraft.business_id == business_id,
            TradePurchaseDraft.user_id == user_id,
        )
    )
    d = q.scalar_one_or_none()
    body = json.dumps(payload, default=str)
    if d:
        d.step = step
        d.payload_json = body
        d.updated_at = utcnow()
    else:
        d = TradePurchaseDraft(
            business_id=business_id,
            user_id=user_id,
            step=step,
            payload_json=body,
        )
        db.add(d)
    await db.commit()
    await db.refresh(d)
    try:
        pl = json.loads(d.payload_json)
    except json.JSONDecodeError:
        pl = {}
    return TradeDraftOut(step=d.step, payload=pl, updated_at=d.updated_at)


async def delete_draft(db: AsyncSession, business_id: uuid.UUID, user_id: uuid.UUID) -> None:
    await db.execute(
        delete(TradePurchaseDraft).where(
            TradePurchaseDraft.business_id == business_id,
            TradePurchaseDraft.user_id == user_id,
        )
    )
    await db.commit()
