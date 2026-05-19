import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import desc, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.deps import get_current_user, require_membership
from app.models import (
    CatalogItem,
    CategoryType,
    ItemCategory,
    Membership,
    Supplier,
    TradePurchase,
    TradePurchaseLine,
    User,
)
from app.models.notification import AppNotification
from app.models.reorder_list import ReorderListEntry
from app.models.stock_adjustment import StockAdjustmentLog
from app.schemas.stock import (
    BarcodeBatchIn,
    BarcodeBatchOut,
    BarcodeLabelOut,
    BarcodeLookupOut,
    StockAdjustmentOut,
    StockDetailOut,
    StockListItemOut,
    StockListOut,
    StockPatchIn,
    RecentPurchaseOut,
    ReorderListEntryOut,
    ReorderListOut,
    ReorderListPatchIn,
)
from app.services.stock_inventory import catalog_reorder, catalog_stock_qty, stock_status

router = APIRouter(prefix="/v1/businesses/{business_id}/stock", tags=["stock"])

StatusFilter = Literal["all", "low", "critical", "out"]
SortBy = Literal["name", "stock_asc", "stock_desc", "recent"]


def _user_display(user: User) -> str:
    if user.name and user.name.strip():
        return user.name.strip()
    return user.username or user.email


async def _supplier_name(db: AsyncSession, item: CatalogItem) -> str | None:
    if item.last_supplier_id:
        r = await db.execute(select(Supplier.name).where(Supplier.id == item.last_supplier_id))
        n = r.scalar_one_or_none()
        if n:
            return n
    return None


def _item_to_list_row(
    item: CatalogItem,
    category_name: str | None,
    subcategory_name: str | None,
    supplier_name: str | None,
) -> StockListItemOut:
    cur = catalog_stock_qty(item)
    ro = catalog_reorder(item)
    unit = item.stock_unit or item.default_unit or item.selling_unit
    return StockListItemOut(
        id=item.id,
        item_code=item.item_code,
        name=item.name,
        category_name=category_name,
        subcategory_name=subcategory_name,
        current_stock=cur,
        reorder_level=ro,
        unit=unit,
        rack_location=item.rack_location,
        supplier_name=supplier_name,
        stock_status=stock_status(cur, ro),
        last_stock_updated_at=item.last_stock_updated_at,
        last_stock_updated_by=item.last_stock_updated_by,
    )


def _sort_stock_rows(
    rows: list[tuple[CatalogItem, str | None, str | None]],
    sort: SortBy,
) -> None:
    if sort == "stock_asc":
        rows.sort(key=lambda t: catalog_stock_qty(t[0]))
    elif sort == "stock_desc":
        rows.sort(key=lambda t: catalog_stock_qty(t[0]), reverse=True)
    elif sort == "recent":
        rows.sort(
            key=lambda t: t[0].last_stock_updated_at
            or datetime.min.replace(tzinfo=timezone.utc),
            reverse=True,
        )
    else:
        rows.sort(key=lambda t: (t[0].name or "").lower())


async def _query_items(
    db: AsyncSession,
    business_id: uuid.UUID,
    *,
    q: str,
    category: str,
    subcategory: str,
    status_val: StatusFilter,
    sort: SortBy,
    page: int,
    per_page: int,
):
    stmt = (
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    if q.strip():
        like = f"%{q.strip().lower()}%"
        stmt = stmt.where(
            or_(
                func.lower(CatalogItem.name).like(like),
                func.lower(func.coalesce(CatalogItem.item_code, "")).like(like),
            )
        )
    if category.strip():
        stmt = stmt.where(func.lower(ItemCategory.name) == category.strip().lower())
    if subcategory.strip():
        stmt = stmt.where(func.lower(CategoryType.name) == subcategory.strip().lower())

    rows = (await db.execute(stmt)).all()
    out: list[tuple[CatalogItem, str | None, str | None]] = []
    for item, cat_name, type_name in rows:
        cur = catalog_stock_qty(item)
        ro = catalog_reorder(item)
        st = stock_status(cur, ro)
        if status_val != "all" and st != status_val:
            continue
        out.append((item, cat_name, type_name))

    _sort_stock_rows(out, sort)
    total = len(out)
    start = (page - 1) * per_page
    page_rows = out[start : start + per_page]
    return total, page_rows


@router.get("/list", response_model=StockListOut)
async def list_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    q: str = Query(""),
    category: str = Query(""),
    subcategory: str = Query(""),
    status: StatusFilter = Query("all"),
    sort: SortBy = Query("name"),
):
    total, rows = await _query_items(
        db,
        business_id,
        q=q,
        category=category,
        subcategory=subcategory,
        status_val=status,
        sort=sort,
        page=page,
        per_page=per_page,
    )
    items: list[StockListItemOut] = []
    for item, cat_name, type_name in rows:
        sup = await _supplier_name(db, item)
        items.append(_item_to_list_row(item, cat_name, type_name, sup))
    return StockListOut(items=items, total=total, page=page, per_page=per_page)


@router.get("/search", response_model=StockListOut)
async def search_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
    q: str = Query(""),
    category: str = Query(""),
    subcategory: str = Query(""),
    status: StatusFilter = Query("all"),
    sort: SortBy = Query("name"),
):
    return await list_stock(
        business_id,
        db,
        _m,
        page=page,
        per_page=per_page,
        q=q,
        category=category,
        subcategory=subcategory,
        status=status,
        sort=sort,
    )


@router.get("/low", response_model=StockListOut)
async def low_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
):
    total, rows = await _query_items(
        db,
        business_id,
        q="",
        category="",
        subcategory="",
        status_val="all",
        sort="stock_asc",
        page=1,
        per_page=10_000,
    )
    filtered: list[tuple[CatalogItem, str | None, str | None, Decimal]] = []
    for item, cat_name, type_name in rows:
        cur = catalog_stock_qty(item)
        ro = catalog_reorder(item)
        if ro > 0 and cur < ro:
            ratio = cur / ro if ro > 0 else Decimal("1")
            filtered.append((item, cat_name, type_name, ratio))
    filtered.sort(key=lambda x: x[3])
    total = len(filtered)
    start = (page - 1) * per_page
    page_slice = filtered[start : start + per_page]
    items: list[StockListItemOut] = []
    for item, cat_name, type_name, _ in page_slice:
        sup = await _supplier_name(db, item)
        items.append(_item_to_list_row(item, cat_name, type_name, sup))
    return StockListOut(items=items, total=total, page=page, per_page=per_page)


@router.get("/critical", response_model=StockListOut)
async def critical_stock(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    page: int = Query(1, ge=1),
    per_page: int = Query(50, ge=1, le=200),
):
    return await list_stock(
        business_id,
        db,
        _m,
        page=page,
        per_page=per_page,
        status="critical",
    )


@router.get("/barcode/lookup", response_model=BarcodeLookupOut)
async def barcode_lookup(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    code: str = Query(..., min_length=1),
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.item_code == code.strip(),
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    return BarcodeLookupOut(
        id=item.id,
        name=item.name,
        item_code=item.item_code,
        current_stock=catalog_stock_qty(item),
        reorder_level=catalog_reorder(item),
        unit=item.stock_unit or item.default_unit,
    )


@router.get("/audit/recent", response_model=list[StockAdjustmentOut])
async def recent_adjustments_all(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    limit: int = Query(5, ge=1, le=50),
):
    r = await db.execute(
        select(StockAdjustmentLog)
        .where(StockAdjustmentLog.business_id == business_id)
        .order_by(desc(StockAdjustmentLog.updated_at))
        .limit(limit)
    )
    return [StockAdjustmentOut.model_validate(x) for x in r.scalars().all()]


@router.get("/audit/{item_id}", response_model=list[StockAdjustmentOut])
async def audit_for_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(StockAdjustmentLog)
        .where(
            StockAdjustmentLog.business_id == business_id,
            StockAdjustmentLog.item_id == item_id,
        )
        .order_by(desc(StockAdjustmentLog.updated_at))
        .limit(50)
    )
    return [StockAdjustmentOut.model_validate(x) for x in r.scalars().all()]


async def _barcode_label(
    db: AsyncSession, business_id: uuid.UUID, item: CatalogItem
) -> BarcodeLabelOut:
    cat_name: str | None = None
    if item.category_id:
        cr = await db.execute(select(ItemCategory.name).where(ItemCategory.id == item.category_id))
        cat_name = cr.scalar_one_or_none()
    purchases = await _recent_purchases(db, item.id, limit=1)
    lp = purchases[0] if purchases else None
    return BarcodeLabelOut(
        id=item.id,
        item_code=item.item_code,
        item_name=item.name,
        category_name=cat_name,
        unit=item.stock_unit or item.default_unit,
        current_stock=catalog_stock_qty(item),
        last_purchase_date=lp.purchase_date if lp else None,
        last_purchase_qty=lp.qty if lp else None,
        last_purchase_unit=lp.unit if lp else None,
        last_purchase_rate=lp.rate if lp else None,
    )


@router.get("/barcode/{item_id}", response_model=BarcodeLabelOut)
async def barcode_label(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    return await _barcode_label(db, business_id, item)


@router.post("/barcode/batch", response_model=BarcodeBatchOut)
async def barcode_batch(
    business_id: uuid.UUID,
    body: BarcodeBatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.business_id == business_id,
            CatalogItem.id.in_(body.item_ids),
            CatalogItem.deleted_at.is_(None),
        )
    )
    items = {i.id: i for i in r.scalars().all()}
    labels: list[BarcodeLabelOut] = []
    for iid in body.item_ids:
        item = items.get(iid)
        if item:
            labels.append(await _barcode_label(db, business_id, item))
    return BarcodeBatchOut(labels=labels)


async def _recent_purchases(db: AsyncSession, item_id: uuid.UUID, limit: int = 5) -> list[RecentPurchaseOut]:
    r = await db.execute(
        select(TradePurchaseLine, TradePurchase, Supplier.name)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .outerjoin(Supplier, TradePurchase.supplier_id == Supplier.id)
        .where(TradePurchaseLine.catalog_item_id == item_id)
        .order_by(desc(TradePurchase.purchase_date))
        .limit(limit)
    )
    out: list[RecentPurchaseOut] = []
    for line, tp, sup_name in r.all():
        pd = tp.purchase_date
        if pd is not None and not isinstance(pd, datetime):
            from datetime import date as date_cls

            if isinstance(pd, date_cls):
                pd = datetime.combine(pd, datetime.min.time(), tzinfo=timezone.utc)
        out.append(
            RecentPurchaseOut(
                purchase_date=pd,
                qty=line.qty,
                unit=line.unit,
                rate=getattr(line, "landing_cost", None) or getattr(line, "purchase_rate", None),
                supplier_name=sup_name,
            )
        )
    return out


@router.get("/{item_id}", response_model=StockDetailOut)
async def get_stock_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    row = r.one_or_none()
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    item, cat_name, type_name = row
    sup = await _supplier_name(db, item)
    base = _item_to_list_row(item, cat_name, type_name, sup)
    purchases = await _recent_purchases(db, item_id)
    return StockDetailOut(**base.model_dump(), recent_purchases=purchases)


@router.patch("/{item_id}", response_model=StockDetailOut)
async def patch_stock_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: StockPatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    membership: Annotated[Membership, Depends(require_membership)],
):
    if membership.role not in ("owner", "manager", "staff", "super_admin"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Access denied")
    r = await db.execute(
        select(CatalogItem)
        .options(selectinload(CatalogItem.category))
        .where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    old_qty = catalog_stock_qty(item)
    new_qty = Decimal(body.new_qty)
    display = _user_display(user)
    log = StockAdjustmentLog(
        business_id=business_id,
        item_id=item_id,
        old_qty=old_qty,
        new_qty=new_qty,
        adjustment_type=body.adjustment_type,
        reason=body.reason,
        updated_by=user.id,
        updated_by_name=display,
    )
    item.current_stock = new_qty
    item.last_stock_updated_at = datetime.now(timezone.utc)
    item.last_stock_updated_by = display
    db.add(log)
    await db.commit()
    await db.refresh(item)

    return await get_stock_item(business_id, item_id, db, membership)


@router.post("/{item_id}/notify-owner", status_code=status.HTTP_201_CREATED)
async def notify_owner_about_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    """Staff/manager alert: ping business owners about this catalog item."""
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    mems = await db.execute(
        select(Membership.user_id, Membership.role).where(
            Membership.business_id == business_id,
            Membership.role.in_(("owner", "manager")),
        )
    )
    targets = [(row[0], row[1]) for row in mems.all() if row[0] != user.id]
    if not targets:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="No owner/manager to notify")

    display = _user_display(user)
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    cur = catalog_stock_qty(item)
    ro = catalog_reorder(item)
    inserted = 0
    for uid, role in targets:
        dedupe = f"notify_owner:{item_id}:{uid}:{day}"
        ex = await db.execute(
            select(AppNotification.id).where(
                AppNotification.business_id == business_id,
                AppNotification.dedupe_key == dedupe,
            ).limit(1)
        )
        if ex.scalar_one_or_none() is not None:
            continue
        db.add(
            AppNotification(
                id=uuid.uuid4(),
                business_id=business_id,
                user_id=uid,
                kind="staff_alert",
                title="Stock attention needed",
                body=f"{display} flagged {item.name} ({cur} on hand, reorder {ro})",
                payload={
                    "item_id": str(item_id),
                    "from_user_id": str(user.id),
                    "from_user_name": display,
                    "target_role": role,
                },
                dedupe_key=dedupe,
            )
        )
        inserted += 1
    if inserted:
        await db.commit()
    return {"ok": True, "notifications_created": inserted}


@router.post("/{item_id}/reorder", status_code=status.HTTP_201_CREATED)
async def add_item_to_reorder_list(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
    )
    item = r.scalar_one_or_none()
    if not item:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    ex = await db.execute(
        select(ReorderListEntry).where(
            ReorderListEntry.business_id == business_id,
            ReorderListEntry.item_id == item_id,
            ReorderListEntry.status == "pending",
        ).limit(1)
    )
    row = ex.scalar_one_or_none()
    display = _user_display(user)
    if row is not None:
        row.added_by = user.id
        row.added_by_name = display
        row.updated_at = datetime.now(timezone.utc)
    else:
        db.add(
            ReorderListEntry(
                id=uuid.uuid4(),
                business_id=business_id,
                item_id=item_id,
                added_by=user.id,
                added_by_name=display,
                status="pending",
            )
        )
    await db.commit()
    return {"ok": True, "item_id": str(item_id), "status": "pending"}


@router.get("/reorder", response_model=ReorderListOut)
async def list_reorder_entries(
    business_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    status: str = "pending",
):
    st = (status or "pending").strip().lower()
    if st not in ("pending", "ordered", "done", "all"):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid status filter")

    q = (
        select(ReorderListEntry, CatalogItem)
        .join(CatalogItem, CatalogItem.id == ReorderListEntry.item_id)
        .where(
            ReorderListEntry.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
        .order_by(ReorderListEntry.created_at.desc())
    )
    if st != "all":
        q = q.where(ReorderListEntry.status == st)
    rows = (await db.execute(q)).all()
    items: list[ReorderListEntryOut] = []
    for entry, item in rows:
        cur = catalog_stock_qty(item)
        ro = catalog_reorder(item)
        items.append(
            ReorderListEntryOut(
                id=entry.id,
                item_id=item.id,
                item_name=item.name,
                item_code=item.item_code,
                current_stock=cur,
                reorder_level=ro,
                unit=item.default_unit,
                status=entry.status,
                added_by_name=entry.added_by_name,
                created_at=entry.created_at,
                updated_at=entry.updated_at,
            )
        )
    return ReorderListOut(items=items, total=len(items))


@router.patch("/reorder/{entry_id}", response_model=ReorderListEntryOut)
async def patch_reorder_entry(
    business_id: uuid.UUID,
    entry_id: uuid.UUID,
    body: ReorderListPatchIn,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(ReorderListEntry, CatalogItem)
        .join(CatalogItem, CatalogItem.id == ReorderListEntry.item_id)
        .where(
            ReorderListEntry.id == entry_id,
            ReorderListEntry.business_id == business_id,
        )
    )
    row = r.first()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Reorder entry not found")
    entry, item = row
    entry.status = body.status
    entry.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(entry)
    return ReorderListEntryOut(
        id=entry.id,
        item_id=item.id,
        item_name=item.name,
        item_code=item.item_code,
        current_stock=catalog_stock_qty(item),
        reorder_level=catalog_reorder(item),
        unit=item.default_unit,
        status=entry.status,
        added_by_name=entry.added_by_name,
        created_at=entry.created_at,
        updated_at=entry.updated_at,
    )


@router.delete("/reorder/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_reorder_entry(
    business_id: uuid.UUID,
    entry_id: uuid.UUID,
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    r = await db.execute(
        select(ReorderListEntry).where(
            ReorderListEntry.id == entry_id,
            ReorderListEntry.business_id == business_id,
        )
    )
    entry = r.scalar_one_or_none()
    if entry is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Reorder entry not found")
    await db.delete(entry)
    await db.commit()
