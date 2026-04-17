"""Business logic for trade purchases (human IDs, duplicates, totals)."""

from __future__ import annotations

import json
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import CatalogItem, SupplierItemDefault, TradePurchase, TradePurchaseDraft, TradePurchaseLine
from app.schemas.trade_purchases import (
    TradeDuplicateCheckRequest,
    TradeDuplicateCheckResponse,
    TradeDraftOut,
    TradePurchaseCreateRequest,
    TradePurchaseLineIn,
    TradePurchaseLineOut,
    TradePurchaseOut,
)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


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
) -> str:
    d = float(discount or 0)
    t = float(tax_percent or 0)
    return f"{name.strip().lower()}|{qty:.4f}|{float(landing):.4f}|{d:.4f}|{t:.4f}"


def _fingerprint_lines_from_lines(lines: list[TradePurchaseLine]) -> str:
    parts = sorted(
        _line_fp(
            li.item_name,
            float(li.qty),
            float(li.landing_cost),
            float(li.discount) if li.discount is not None else None,
            float(li.tax_percent) if li.tax_percent is not None else None,
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
        )
        for li in lines
    )
    return "|".join(parts)


def _line_money(li: TradePurchaseLineIn) -> Decimal:
    base = _dec(li.qty) * _dec(li.landing_cost)
    ld = _dec(li.discount) if li.discount is not None else Decimal("0")
    after_disc = base * (Decimal("1") - min(ld, Decimal("100")) / Decimal("100"))
    tax = _dec(li.tax_percent) if li.tax_percent is not None else Decimal("0")
    return after_disc * (Decimal("1") + min(tax, Decimal("1000")) / Decimal("100"))


def compute_totals(req: TradePurchaseCreateRequest) -> tuple[Decimal, Decimal]:
    qty_sum = sum(_dec(li.qty) for li in req.lines)
    amt_sum = sum(_line_money(li) for li in req.lines)
    header_disc = _dec(req.discount) if req.discount is not None else Decimal("0")
    if header_disc > 0:
        amt_sum = amt_sum * (Decimal("1") - min(header_disc, Decimal("100")) / Decimal("100"))
    freight = _dec(req.freight_amount) if req.freight_amount is not None else Decimal("0")
    if req.freight_type == "included":
        freight = Decimal("0")
    amt_sum += freight
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
        if row is None:
            db.add(
                SupplierItemDefault(
                    business_id=business_id,
                    supplier_id=body.supplier_id,
                    catalog_item_id=li.catalog_item_id,
                    last_price=float(li.landing_cost),
                    last_discount=float(li.discount) if li.discount is not None else None,
                    last_payment_days=body.payment_days,
                    purchase_count=1,
                )
            )
        else:
            row.purchase_count = int(row.purchase_count or 0) + 1
            row.last_price = float(li.landing_cost)
            if li.discount is not None:
                row.last_discount = float(li.discount)
            if body.payment_days is not None:
                row.last_payment_days = body.payment_days


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
    db: AsyncSession, business_id: uuid.UUID, limit: int = 100
) -> list[TradePurchaseOut]:
    res = await db.execute(
        select(TradePurchase)
        .where(TradePurchase.business_id == business_id)
        .options(selectinload(TradePurchase.lines))
        .order_by(TradePurchase.purchase_date.desc(), TradePurchase.created_at.desc())
        .limit(min(limit, 500))
    )
    return [trade_purchase_to_out(p) for p in res.scalars().unique().all()]


async def get_trade_purchase(
    db: AsyncSession, business_id: uuid.UUID, purchase_id: uuid.UUID
) -> TradePurchaseOut | None:
    res = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchase.id == purchase_id,
        )
        .options(selectinload(TradePurchase.lines))
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
    human_id = await next_human_id(db, business_id)
    qty_sum, amt_sum = compute_totals(body)
    tp = TradePurchase(
        business_id=business_id,
        user_id=user_id,
        human_id=human_id,
        purchase_date=body.purchase_date,
        supplier_id=body.supplier_id,
        broker_id=body.broker_id,
        payment_days=body.payment_days,
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
        status="confirmed",
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
                selling_cost=li.selling_cost,
                discount=li.discount,
                tax_percent=li.tax_percent,
            )
        )
    await _sync_purchase_memory(db, business_id, body)
    await db.commit()
    res = await db.execute(
        select(TradePurchase)
        .where(TradePurchase.id == tp.id)
        .options(selectinload(TradePurchase.lines))
    )
    loaded = res.scalar_one()
    return trade_purchase_to_out(loaded)


def trade_purchase_to_out(tp: TradePurchase) -> TradePurchaseOut:
    lines = [
        TradePurchaseLineOut(
            id=li.id,
            catalog_item_id=li.catalog_item_id,
            item_name=li.item_name,
            qty=float(li.qty),
            unit=li.unit,
            landing_cost=float(li.landing_cost),
            selling_cost=float(li.selling_cost) if li.selling_cost is not None else None,
            discount=float(li.discount) if li.discount is not None else None,
            tax_percent=float(li.tax_percent) if li.tax_percent is not None else None,
        )
        for li in tp.lines
    ]
    return TradePurchaseOut(
        id=tp.id,
        human_id=tp.human_id,
        purchase_date=tp.purchase_date,
        supplier_id=tp.supplier_id,
        broker_id=tp.broker_id,
        payment_days=tp.payment_days,
        discount=float(tp.discount) if tp.discount is not None else None,
        commission_percent=float(tp.commission_percent) if tp.commission_percent is not None else None,
        delivered_rate=float(tp.delivered_rate) if tp.delivered_rate is not None else None,
        billty_rate=float(tp.billty_rate) if tp.billty_rate is not None else None,
        freight_amount=float(tp.freight_amount) if tp.freight_amount is not None else None,
        freight_type=getattr(tp, "freight_type", None),
        total_qty=float(tp.total_qty) if tp.total_qty is not None else None,
        total_amount=float(tp.total_amount),
        status=tp.status,
        created_at=tp.created_at,
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
