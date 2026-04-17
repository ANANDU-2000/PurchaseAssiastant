import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import require_membership, require_owner_membership
from app.models import Broker, BrokerSupplierLink, Entry, EntryLineItem, Membership, Supplier

router = APIRouter(prefix="/v1/businesses/{business_id}", tags=["contacts"])


def _norm_name(s: str) -> str:
    return s.strip().lower()


class SupplierPrefsIn(BaseModel):
    """Preferred categories, subcategory (type) ids, and catalog item ids for search / AI."""

    category_ids: list[uuid.UUID] = Field(default_factory=list)
    type_ids: list[uuid.UUID] = Field(default_factory=list)
    item_ids: list[uuid.UUID] = Field(default_factory=list)


class SupplierCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    phone: str | None = None
    whatsapp_number: str | None = Field(default=None, max_length=32)
    location: str | None = None
    broker_id: uuid.UUID | None = None
    broker_ids: list[uuid.UUID] | None = None
    gst_number: str | None = Field(default=None, max_length=20)
    address: str | None = None
    notes: str | None = None
    default_payment_days: int | None = Field(default=None, ge=0, le=3650)
    default_discount: float | None = Field(default=None, ge=0)
    default_delivered_rate: float | None = Field(default=None, ge=0)
    default_billty_rate: float | None = Field(default=None, ge=0)
    freight_type: str | None = Field(default=None, max_length=16)
    ai_memory_enabled: bool = False
    preferences: SupplierPrefsIn | None = None


class SupplierOut(BaseModel):
    id: uuid.UUID
    name: str
    phone: str | None = None
    whatsapp_number: str | None = None
    location: str | None = None
    broker_id: uuid.UUID | None = None
    gst_number: str | None = None
    address: str | None = None
    notes: str | None = None
    default_payment_days: int | None = None
    default_discount: float | None = None
    default_delivered_rate: float | None = None
    default_billty_rate: float | None = None
    freight_type: str | None = None
    ai_memory_enabled: bool = False
    preferences_json: str | None = None

    model_config = {"from_attributes": True}


class SupplierUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    phone: str | None = None
    whatsapp_number: str | None = Field(default=None, max_length=32)
    location: str | None = None
    broker_id: uuid.UUID | None = None
    gst_number: str | None = Field(default=None, max_length=20)
    address: str | None = None
    notes: str | None = None
    default_payment_days: int | None = Field(default=None, ge=0, le=3650)
    default_discount: float | None = Field(default=None, ge=0)
    default_delivered_rate: float | None = Field(default=None, ge=0)
    default_billty_rate: float | None = Field(default=None, ge=0)
    freight_type: str | None = Field(default=None, max_length=16)
    ai_memory_enabled: bool | None = None
    preferences: SupplierPrefsIn | None = None


async def _supplier_dup(
    db: AsyncSession, business_id: uuid.UUID, name: str, exclude_id: uuid.UUID | None = None
) -> bool:
    q = select(Supplier.id).where(
        Supplier.business_id == business_id,
        func.lower(Supplier.name) == _norm_name(name),
    )
    if exclude_id is not None:
        q = q.where(Supplier.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


@router.get("/suppliers", response_model=list[SupplierOut])
async def list_suppliers(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(select(Supplier).where(Supplier.business_id == business_id))
    rows = r.scalars().all()
    return [SupplierOut.model_validate(s) for s in rows]


@router.post("/suppliers", response_model=SupplierOut, status_code=status.HTTP_201_CREATED)
async def create_supplier(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: SupplierCreate,
):
    del _m
    if await _supplier_dup(db, business_id, body.name):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="A supplier with this name already exists",
        )
    ft = body.freight_type
    if ft is not None and ft not in ("included", "separate"):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="freight_type must be 'included' or 'separate'",
        )

    merged_broker_ids: list[uuid.UUID] = []
    if body.broker_ids:
        merged_broker_ids.extend(body.broker_ids)
    if body.broker_id and body.broker_id not in merged_broker_ids:
        merged_broker_ids.insert(0, body.broker_id)
    dedup_brokers: list[uuid.UUID] = []
    for bid in merged_broker_ids:
        if bid not in dedup_brokers:
            dedup_brokers.append(bid)

    prefs_json: str | None = None
    if body.preferences is not None:
        prefs_json = body.preferences.model_dump_json()

    s = Supplier(
        business_id=business_id,
        name=body.name.strip(),
        phone=body.phone,
        whatsapp_number=body.whatsapp_number,
        location=body.location,
        broker_id=dedup_brokers[0] if dedup_brokers else body.broker_id,
        gst_number=body.gst_number,
        address=body.address,
        notes=body.notes,
        default_payment_days=body.default_payment_days,
        default_discount=body.default_discount,
        default_delivered_rate=body.default_delivered_rate,
        default_billty_rate=body.default_billty_rate,
        freight_type=ft,
        ai_memory_enabled=body.ai_memory_enabled,
        preferences_json=prefs_json,
    )
    db.add(s)
    await db.flush()

    for bid in dedup_brokers:
        ok = await db.scalar(
            select(Broker.id).where(Broker.id == bid, Broker.business_id == business_id)
        )
        if ok is None:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail=f"Broker not in this business: {bid}",
            )
        db.add(BrokerSupplierLink(broker_id=bid, supplier_id=s.id))

    await db.commit()
    await db.refresh(s)
    return SupplierOut.model_validate(s)


@router.patch("/suppliers/{supplier_id}", response_model=SupplierOut)
async def update_supplier(
    business_id: uuid.UUID,
    supplier_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: SupplierUpdate,
):
    del _m
    r = await db.execute(
        select(Supplier).where(Supplier.id == supplier_id, Supplier.business_id == business_id)
    )
    s = r.scalar_one_or_none()
    if s is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Supplier not found")
    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        if await _supplier_dup(db, business_id, data["name"], exclude_id=supplier_id):
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="A supplier with this name already exists",
            )
        s.name = data["name"].strip()
    if "phone" in data:
        s.phone = data["phone"]
    if "whatsapp_number" in data:
        v = data["whatsapp_number"]
        s.whatsapp_number = None if v is None or (isinstance(v, str) and not str(v).strip()) else str(v).strip()
    if "location" in data:
        s.location = data["location"]
    if "address" in data:
        s.address = data["address"]
    if "notes" in data:
        s.notes = data["notes"]
    if "freight_type" in data:
        fv = data["freight_type"]
        if fv is not None and fv not in ("included", "separate"):
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="freight_type must be 'included' or 'separate'",
            )
        s.freight_type = fv
    if "ai_memory_enabled" in data and data["ai_memory_enabled"] is not None:
        s.ai_memory_enabled = bool(data["ai_memory_enabled"])
    if "preferences" in data and data["preferences"] is not None:
        s.preferences_json = SupplierPrefsIn.model_validate(data["preferences"]).model_dump_json()
    if "broker_id" in data:
        s.broker_id = data["broker_id"]
    for k in (
        "gst_number",
        "default_payment_days",
        "default_discount",
        "default_delivered_rate",
        "default_billty_rate",
    ):
        if k in data:
            setattr(s, k, data[k])
    await db.commit()
    await db.refresh(s)
    return SupplierOut.model_validate(s)


@router.delete("/suppliers/{supplier_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_supplier(
    business_id: uuid.UUID,
    supplier_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    r = await db.execute(
        select(Supplier).where(Supplier.id == supplier_id, Supplier.business_id == business_id)
    )
    s = r.scalar_one_or_none()
    if s is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Supplier not found")
    ec = await db.execute(
        select(func.count(Entry.id)).where(
            Entry.business_id == business_id,
            Entry.supplier_id == supplier_id,
        )
    )
    if int(ec.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a supplier that has purchase entries",
        )
    await db.delete(s)
    await db.commit()


class BrokerOut(BaseModel):
    id: uuid.UUID
    name: str
    phone: str | None = None
    commission_type: str
    commission_value: float | None

    model_config = {"from_attributes": True}


class BrokerUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)
    phone: str | None = Field(default=None, max_length=15)
    commission_type: str | None = Field(default=None, pattern="^(percent|flat)$")
    commission_value: float | None = Field(default=None, ge=0)


async def _broker_dup(
    db: AsyncSession, business_id: uuid.UUID, name: str, exclude_id: uuid.UUID | None = None
) -> bool:
    q = select(Broker.id).where(
        Broker.business_id == business_id,
        func.lower(Broker.name) == _norm_name(name),
    )
    if exclude_id is not None:
        q = q.where(Broker.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


@router.get("/brokers", response_model=list[BrokerOut])
async def list_brokers(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(select(Broker).where(Broker.business_id == business_id))
    rows = r.scalars().all()
    return [BrokerOut.model_validate(b) for b in rows]


class BrokerCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    phone: str | None = Field(default=None, max_length=15)
    commission_type: str = Field(default="percent", pattern="^(percent|flat)$")
    commission_value: float | None = Field(default=None, ge=0)


@router.post("/brokers", response_model=BrokerOut, status_code=status.HTTP_201_CREATED)
async def create_broker(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: BrokerCreate,
):
    del _m
    if await _broker_dup(db, business_id, body.name):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="A broker with this name already exists",
        )
    b = Broker(
        business_id=business_id,
        name=body.name.strip(),
        phone=body.phone,
        commission_type=body.commission_type,
        commission_value=body.commission_value,
    )
    db.add(b)
    await db.commit()
    await db.refresh(b)
    return BrokerOut.model_validate(b)


@router.patch("/brokers/{broker_id}", response_model=BrokerOut)
async def update_broker(
    business_id: uuid.UUID,
    broker_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: BrokerUpdate,
):
    del _m
    r = await db.execute(
        select(Broker).where(Broker.id == broker_id, Broker.business_id == business_id)
    )
    b = r.scalar_one_or_none()
    if b is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Broker not found")
    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        if await _broker_dup(db, business_id, data["name"], exclude_id=broker_id):
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="A broker with this name already exists",
            )
        b.name = data["name"].strip()
    if "commission_type" in data and data["commission_type"] is not None:
        b.commission_type = data["commission_type"]
    if "commission_value" in data:
        b.commission_value = data["commission_value"]
    if "phone" in data:
        b.phone = data["phone"]
    await db.commit()
    await db.refresh(b)
    return BrokerOut.model_validate(b)


@router.delete("/brokers/{broker_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_broker(
    business_id: uuid.UUID,
    broker_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    r = await db.execute(
        select(Broker).where(Broker.id == broker_id, Broker.business_id == business_id)
    )
    b = r.scalar_one_or_none()
    if b is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Broker not found")
    ec = await db.execute(
        select(func.count(Entry.id)).where(
            Entry.business_id == business_id,
            Entry.broker_id == broker_id,
        )
    )
    if int(ec.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a broker linked to purchase entries",
        )
    sc = await db.execute(
        select(func.count(Supplier.id)).where(
            Supplier.business_id == business_id,
            Supplier.broker_id == broker_id,
        )
    )
    if int(sc.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a broker assigned to suppliers — reassign suppliers first",
        )
    await db.delete(b)
    await db.commit()


@router.get("/brokers/{broker_id}", response_model=BrokerOut)
async def get_broker(
    business_id: uuid.UUID,
    broker_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(
        select(Broker).where(Broker.id == broker_id, Broker.business_id == business_id)
    )
    b = r.scalar_one_or_none()
    if b is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Broker not found")
    return BrokerOut.model_validate(b)


@router.get("/suppliers/{supplier_id}", response_model=SupplierOut)
async def get_supplier(
    business_id: uuid.UUID,
    supplier_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(
        select(Supplier).where(Supplier.id == supplier_id, Supplier.business_id == business_id)
    )
    s = r.scalar_one_or_none()
    if s is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Supplier not found")
    return SupplierOut.model_validate(s)


def _date_filter(business_id: uuid.UUID, from_date: date, to_date: date):
    return (
        Entry.business_id == business_id,
        Entry.entry_date >= from_date,
        Entry.entry_date <= to_date,
    )


class SupplierMetricsOut(BaseModel):
    deals: int
    total_qty: float
    avg_landing: float
    total_profit: float
    purchase_amount: float
    profit_margin_pct: float


@router.get("/suppliers/{supplier_id}/metrics", response_model=SupplierMetricsOut)
async def supplier_metrics(
    business_id: uuid.UUID,
    supplier_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    r = await db.execute(
        select(Supplier).where(Supplier.id == supplier_id, Supplier.business_id == business_id)
    )
    if r.scalar_one_or_none() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Supplier not found")
    bf = _date_filter(business_id, from_date, to_date)
    q = (
        select(
            func.count(Entry.id.distinct()).label("deals"),
            func.coalesce(func.sum(EntryLineItem.qty), 0).label("tq"),
            func.coalesce(func.avg(EntryLineItem.landing_cost), 0).label("al"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
            func.coalesce(func.sum(EntryLineItem.qty * EntryLineItem.buy_price), 0).label("pam"),
        )
        .select_from(Entry)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .where(*bf, Entry.supplier_id == supplier_id)
    )
    row = (await db.execute(q)).one()
    deals = int(row[0] or 0)
    tq = float(row[1] or 0)
    al = float(row[2] or 0)
    tp = float(row[3] or 0)
    pam = float(row[4] or 0)
    margin = (tp / pam * 100.0) if pam > 0 else 0.0
    return SupplierMetricsOut(
        deals=deals,
        total_qty=tq,
        avg_landing=al,
        total_profit=tp,
        purchase_amount=pam,
        profit_margin_pct=margin,
    )


class BrokerMetricsOut(BaseModel):
    deals: int
    total_commission: float
    total_profit: float


@router.get("/brokers/{broker_id}/metrics", response_model=BrokerMetricsOut)
async def broker_metrics(
    business_id: uuid.UUID,
    broker_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    r = await db.execute(
        select(Broker).where(Broker.id == broker_id, Broker.business_id == business_id)
    )
    if r.scalar_one_or_none() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Broker not found")
    bf = _date_filter(business_id, from_date, to_date)
    q = (
        select(
            func.count(Entry.id.distinct()).label("deals"),
            func.coalesce(func.sum(Entry.commission_amount), 0).label("tc"),
            func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
        )
        .select_from(Entry)
        .join(EntryLineItem, EntryLineItem.entry_id == Entry.id)
        .where(*bf, Entry.broker_id == broker_id)
    )
    row = (await db.execute(q)).one()
    return BrokerMetricsOut(
        deals=int(row[0] or 0),
        total_commission=float(row[1] or 0),
        total_profit=float(row[2] or 0),
    )


class SearchOut(BaseModel):
    suppliers: list[SupplierOut]
    brokers: list[BrokerOut]
    item_names: list[str]
    categories: list[str]


@router.get("/contacts/search", response_model=SearchOut)
async def contacts_search(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    q: str = Query("", max_length=200),
    limit: int = Query(15, ge=1, le=50),
):
    del _m
    term = q.strip()
    if not term:
        return SearchOut(suppliers=[], brokers=[], item_names=[], categories=[])

    like = f"%{_norm_name(term)}%"
    # Suppliers
    rs = await db.execute(
        select(Supplier)
        .where(
            Supplier.business_id == business_id,
            func.lower(Supplier.name).like(like),
        )
        .limit(limit)
    )
    suppliers = [SupplierOut.model_validate(s) for s in rs.scalars().all()]
    rb = await db.execute(
        select(Broker)
        .where(
            Broker.business_id == business_id,
            func.lower(Broker.name).like(like),
        )
        .limit(limit)
    )
    brokers = [BrokerOut.model_validate(b) for b in rb.scalars().all()]
    ri = await db.execute(
        select(EntryLineItem.item_name)
        .distinct()
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(
            Entry.business_id == business_id,
            func.lower(EntryLineItem.item_name).like(like),
        )
        .limit(limit)
    )
    item_names = [row[0] for row in ri.all() if row[0]]
    rc = await db.execute(
        select(func.coalesce(EntryLineItem.category, "Uncategorized"))
        .distinct()
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(
            Entry.business_id == business_id,
            func.lower(func.coalesce(EntryLineItem.category, "Uncategorized")).like(like),
        )
        .limit(limit)
    )
    categories = [row[0] for row in rc.all() if row[0]]
    return SearchOut(
        suppliers=suppliers,
        brokers=brokers,
        item_names=item_names,
        categories=categories,
    )


class CategoryItemRow(BaseModel):
    item_name: str
    line_count: int
    total_profit: float
    total_qty: float


@router.get("/contacts/category-items", response_model=list[CategoryItemRow])
async def category_items(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    category: str = Query(..., min_length=1, max_length=255),
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    bf = _date_filter(business_id, from_date, to_date)
    if category != "Uncategorized":
        q = (
            select(
                EntryLineItem.item_name,
                func.count(EntryLineItem.id).label("lc"),
                func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
                func.coalesce(func.sum(EntryLineItem.qty), 0).label("tq"),
            )
            .select_from(EntryLineItem)
            .join(Entry, Entry.id == EntryLineItem.entry_id)
            .where(*bf, EntryLineItem.category == category)
            .group_by(EntryLineItem.item_name)
            .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        )
    else:
        q = (
            select(
                EntryLineItem.item_name,
                func.count(EntryLineItem.id).label("lc"),
                func.coalesce(func.sum(EntryLineItem.profit), 0).label("tp"),
                func.coalesce(func.sum(EntryLineItem.qty), 0).label("tq"),
            )
            .select_from(EntryLineItem)
            .join(Entry, Entry.id == EntryLineItem.entry_id)
            .where(*bf, EntryLineItem.category.is_(None))
            .group_by(EntryLineItem.item_name)
            .order_by(func.coalesce(func.sum(EntryLineItem.profit), 0).desc())
        )

    r = await db.execute(q)
    return [
        CategoryItemRow(
            item_name=row[0],
            line_count=int(row[1] or 0),
            total_profit=float(row[2] or 0),
            total_qty=float(row[3] or 0),
        )
        for row in r.all()
    ]
