import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import require_membership, require_owner_membership
from app.models import CatalogItem, CatalogVariant, EntryLineItem, ItemCategory, Membership
from app.models.entry import Entry

router = APIRouter(prefix="/v1/businesses/{business_id}", tags=["catalog"])


def _norm_name(s: str) -> str:
    return " ".join(s.lower().strip().split())


class ItemCategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)


class ItemCategoryUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)


class ItemCategoryOut(BaseModel):
    id: uuid.UUID
    name: str

    model_config = {"from_attributes": True}


class CatalogItemCreate(BaseModel):
    category_id: uuid.UUID
    name: str = Field(min_length=1, max_length=512)
    default_unit: str | None = Field(default=None, pattern="^(kg|box|piece|bag)$")
    default_kg_per_bag: float | None = Field(default=None, gt=0)


class CatalogItemUpdate(BaseModel):
    category_id: uuid.UUID | None = None
    name: str | None = Field(default=None, min_length=1, max_length=512)
    default_unit: str | None = Field(default=None, pattern="^(kg|box|piece|bag)$")
    default_kg_per_bag: float | None = Field(default=None, gt=0)


class CatalogItemOut(BaseModel):
    id: uuid.UUID
    category_id: uuid.UUID
    name: str
    default_unit: str | None
    default_kg_per_bag: float | None = None

    model_config = {"from_attributes": True}


class CatalogVariantCreate(BaseModel):
    name: str = Field(min_length=1, max_length=512)
    default_kg_per_bag: float | None = Field(default=None, gt=0)


class CatalogVariantUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=512)
    default_kg_per_bag: float | None = Field(default=None, gt=0)


class CatalogVariantOut(BaseModel):
    id: uuid.UUID
    catalog_item_id: uuid.UUID
    name: str
    default_kg_per_bag: float | None

    model_config = {"from_attributes": True}


class CatalogItemInsightsOut(BaseModel):
    line_count: int
    entry_count: int
    total_profit: float
    avg_landing: float | None
    avg_selling: float | None
    last_entry_date: date | None
    profit_margin_pct: float | None


class CategoryInsightsOut(BaseModel):
    item_count: int
    linked_line_count: int
    total_profit: float
    top_item_name: str | None
    top_item_profit: float | None
    worst_item_name: str | None
    worst_item_profit: float | None


class CatalogItemLineRow(BaseModel):
    entry_id: uuid.UUID
    entry_date: date
    qty: float
    unit: str
    landing_cost: float
    selling_price: float | None
    profit: float | None


def _entry_date_filter(business_id: uuid.UUID, from_date: date, to_date: date):
    return and_(
        Entry.business_id == business_id,
        Entry.entry_date >= from_date,
        Entry.entry_date <= to_date,
    )


async def _category_dup(
    db: AsyncSession, business_id: uuid.UUID, name: str, exclude_id: uuid.UUID | None = None
) -> bool:
    q = select(ItemCategory.id).where(
        ItemCategory.business_id == business_id,
        func.lower(ItemCategory.name) == _norm_name(name),
    )
    if exclude_id is not None:
        q = q.where(ItemCategory.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


async def _item_dup(
    db: AsyncSession,
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    name: str,
    exclude_id: uuid.UUID | None = None,
) -> bool:
    q = select(CatalogItem.id).where(
        CatalogItem.business_id == business_id,
        CatalogItem.category_id == category_id,
        func.lower(CatalogItem.name) == _norm_name(name),
    )
    if exclude_id is not None:
        q = q.where(CatalogItem.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


async def _variant_dup(
    db: AsyncSession,
    business_id: uuid.UUID,
    catalog_item_id: uuid.UUID,
    name: str,
    exclude_id: uuid.UUID | None = None,
) -> bool:
    q = select(CatalogVariant.id).where(
        CatalogVariant.business_id == business_id,
        CatalogVariant.catalog_item_id == catalog_item_id,
        func.lower(CatalogVariant.name) == _norm_name(name),
    )
    if exclude_id is not None:
        q = q.where(CatalogVariant.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


@router.get("/item-categories", response_model=list[ItemCategoryOut])
async def list_item_categories(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(
        select(ItemCategory)
        .where(ItemCategory.business_id == business_id)
        .order_by(func.lower(ItemCategory.name))
    )
    rows = r.scalars().all()
    return [ItemCategoryOut(id=c.id, name=c.name) for c in rows]


@router.post("/item-categories", response_model=ItemCategoryOut, status_code=status.HTTP_201_CREATED)
async def create_item_category(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: ItemCategoryCreate,
):
    del _m
    if await _category_dup(db, business_id, body.name):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="A category with this name already exists",
        )
    c = ItemCategory(business_id=business_id, name=body.name.strip())
    db.add(c)
    await db.commit()
    await db.refresh(c)
    return ItemCategoryOut(id=c.id, name=c.name)


@router.get("/item-categories/{category_id}", response_model=ItemCategoryOut)
async def get_item_category(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(
        select(ItemCategory).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    c = r.scalar_one_or_none()
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Category not found")
    return ItemCategoryOut(id=c.id, name=c.name)


@router.patch("/item-categories/{category_id}", response_model=ItemCategoryOut)
async def update_item_category(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: ItemCategoryUpdate,
):
    del _m
    r = await db.execute(
        select(ItemCategory).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    c = r.scalar_one_or_none()
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Category not found")
    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        if await _category_dup(db, business_id, data["name"], exclude_id=category_id):
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="A category with this name already exists",
            )
        c.name = data["name"].strip()
    await db.commit()
    await db.refresh(c)
    return ItemCategoryOut(id=c.id, name=c.name)


@router.delete("/item-categories/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_item_category(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    r = await db.execute(
        select(ItemCategory).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    c = r.scalar_one_or_none()
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Category not found")
    ic = await db.execute(
        select(func.count(CatalogItem.id)).where(CatalogItem.category_id == category_id)
    )
    if int(ic.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a category that still has catalog items — delete or move items first",
        )
    await db.delete(c)
    await db.commit()


@router.get("/catalog-items", response_model=list[CatalogItemOut])
async def list_catalog_items(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    category_id: uuid.UUID | None = Query(None, description="Filter by category"),
):
    del _m
    q = select(CatalogItem).where(CatalogItem.business_id == business_id)
    if category_id is not None:
        q = q.where(CatalogItem.category_id == category_id)
    q = q.order_by(func.lower(CatalogItem.name))
    r = await db.execute(q)
    rows = r.scalars().all()
    return [
        CatalogItemOut(
            id=i.id,
            category_id=i.category_id,
            name=i.name,
            default_unit=i.default_unit,
            default_kg_per_bag=float(i.default_kg_per_bag) if i.default_kg_per_bag is not None else None,
        )
        for i in rows
    ]


@router.post("/catalog-items", response_model=CatalogItemOut, status_code=status.HTTP_201_CREATED)
async def create_catalog_item(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CatalogItemCreate,
):
    del _m
    rc = await db.execute(
        select(ItemCategory.id).where(
            ItemCategory.id == body.category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if rc.first() is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="category_id not found in this business")
    if await _item_dup(db, business_id, body.category_id, body.name):
        er = await db.execute(
            select(CatalogItem.id).where(
                CatalogItem.business_id == business_id,
                CatalogItem.category_id == body.category_id,
                func.lower(CatalogItem.name) == _norm_name(body.name),
            )
        )
        eid = er.scalar_one()
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "message": "An item with this name already exists in this category",
                "existing_item_id": str(eid),
            },
        )
    dkg = body.default_kg_per_bag if body.default_unit == "bag" else None
    i = CatalogItem(
        business_id=business_id,
        category_id=body.category_id,
        name=body.name.strip(),
        default_unit=body.default_unit,
        default_kg_per_bag=dkg,
    )
    db.add(i)
    await db.commit()
    await db.refresh(i)
    return CatalogItemOut(
        id=i.id,
        category_id=i.category_id,
        name=i.name,
        default_unit=i.default_unit,
        default_kg_per_bag=float(i.default_kg_per_bag) if i.default_kg_per_bag is not None else None,
    )


@router.get("/catalog-items/{item_id}", response_model=CatalogItemOut)
async def get_catalog_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
        )
    )
    i = r.scalar_one_or_none()
    if i is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    return CatalogItemOut(
        id=i.id,
        category_id=i.category_id,
        name=i.name,
        default_unit=i.default_unit,
        default_kg_per_bag=float(i.default_kg_per_bag) if i.default_kg_per_bag is not None else None,
    )


@router.get("/catalog-items/{item_id}/insights", response_model=CatalogItemInsightsOut)
async def catalog_item_insights(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    ir = await db.execute(
        select(CatalogItem.id).where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
    )
    if ir.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    bf = _entry_date_filter(business_id, from_date, to_date)
    base = (
        select(
            func.count(EntryLineItem.id),
            func.count(func.distinct(EntryLineItem.entry_id)),
            func.coalesce(func.sum(EntryLineItem.profit), 0),
            func.avg(EntryLineItem.landing_cost),
            func.avg(EntryLineItem.selling_price),
            func.max(Entry.entry_date),
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(
            bf,
            EntryLineItem.catalog_item_id == item_id,
        )
    )
    r = await db.execute(base)
    row = r.one()
    line_count = int(row[0] or 0)
    entry_count = int(row[1] or 0)
    total_profit = float(row[2] or 0)
    avg_landing = float(row[3]) if row[3] is not None else None
    avg_selling = float(row[4]) if row[4] is not None else None
    last_entry_date = row[5]

    profit_margin_pct: float | None = None
    if line_count > 0:
        rev_r = await db.execute(
            select(func.coalesce(func.sum(EntryLineItem.qty * EntryLineItem.selling_price), 0))
            .select_from(EntryLineItem)
            .join(Entry, Entry.id == EntryLineItem.entry_id)
            .where(
                bf,
                EntryLineItem.catalog_item_id == item_id,
                EntryLineItem.selling_price.isnot(None),
            )
        )
        total_rev = float(rev_r.scalar() or 0)
        if total_rev > 0:
            profit_margin_pct = (total_profit / total_rev) * 100.0

    return CatalogItemInsightsOut(
        line_count=line_count,
        entry_count=entry_count,
        total_profit=total_profit,
        avg_landing=avg_landing,
        avg_selling=avg_selling,
        last_entry_date=last_entry_date,
        profit_margin_pct=profit_margin_pct,
    )


@router.get("/catalog-items/{item_id}/lines", response_model=list[CatalogItemLineRow])
async def catalog_item_lines(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    del _m
    ir = await db.execute(
        select(CatalogItem.id).where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
    )
    if ir.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    bf = _entry_date_filter(business_id, from_date, to_date)
    q = (
        select(
            Entry.id,
            Entry.entry_date,
            EntryLineItem.qty,
            EntryLineItem.unit,
            EntryLineItem.landing_cost,
            EntryLineItem.selling_price,
            EntryLineItem.profit,
        )
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(
            bf,
            EntryLineItem.catalog_item_id == item_id,
        )
        .order_by(Entry.entry_date.desc(), Entry.id.desc())
        .limit(limit)
        .offset(offset)
    )
    r = await db.execute(q)
    rows = r.all()
    return [
        CatalogItemLineRow(
            entry_id=row[0],
            entry_date=row[1],
            qty=float(row[2]),
            unit=row[3],
            landing_cost=float(row[4]),
            selling_price=float(row[5]) if row[5] is not None else None,
            profit=float(row[6]) if row[6] is not None else None,
        )
        for row in rows
    ]


@router.get("/item-categories/{category_id}/insights", response_model=CategoryInsightsOut)
async def category_insights(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    from_date: date = Query(..., alias="from"),
    to_date: date = Query(..., alias="to"),
):
    del _m
    cr = await db.execute(
        select(ItemCategory.id).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if cr.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Category not found")

    ic = await db.execute(
        select(func.count(CatalogItem.id)).where(
            CatalogItem.business_id == business_id,
            CatalogItem.category_id == category_id,
        )
    )
    item_count = int(ic.scalar() or 0)

    bf = _entry_date_filter(business_id, from_date, to_date)
    cat_item_ids = (
        select(CatalogItem.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.category_id == category_id,
        )
        .scalar_subquery()
    )

    lc = await db.execute(
        select(func.count(EntryLineItem.id))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(
            bf,
            EntryLineItem.catalog_item_id.in_(cat_item_ids),
        )
    )
    linked_line_count = int(lc.scalar() or 0)

    tp = await db.execute(
        select(func.coalesce(func.sum(EntryLineItem.profit), 0))
        .select_from(EntryLineItem)
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(
            bf,
            EntryLineItem.catalog_item_id.in_(cat_item_ids),
        )
    )
    total_profit = float(tp.scalar() or 0)

    per_item = await db.execute(
        select(CatalogItem.id, CatalogItem.name, func.coalesce(func.sum(EntryLineItem.profit), 0))
        .select_from(CatalogItem)
        .join(
            EntryLineItem,
            and_(
                EntryLineItem.catalog_item_id == CatalogItem.id,
            ),
        )
        .join(Entry, Entry.id == EntryLineItem.entry_id)
        .where(
            bf,
            CatalogItem.category_id == category_id,
            CatalogItem.business_id == business_id,
        )
        .group_by(CatalogItem.id, CatalogItem.name)
    )
    agg = [(row[0], row[1], float(row[2] or 0)) for row in per_item.all()]
    top_name = top_profit = worst_name = worst_profit = None
    if agg:
        best = max(agg, key=lambda x: x[2])
        worst = min(agg, key=lambda x: x[2])
        top_name, top_profit = best[1], best[2]
        worst_name, worst_profit = worst[1], worst[2]

    return CategoryInsightsOut(
        item_count=item_count,
        linked_line_count=linked_line_count,
        total_profit=total_profit,
        top_item_name=top_name,
        top_item_profit=top_profit,
        worst_item_name=worst_name,
        worst_item_profit=worst_profit,
    )


@router.patch("/catalog-items/{item_id}", response_model=CatalogItemOut)
async def update_catalog_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CatalogItemUpdate,
):
    del _m
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
        )
    )
    i = r.scalar_one_or_none()
    if i is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    data = body.model_dump(exclude_unset=True)
    cid = data.get("category_id", i.category_id)
    if "category_id" in data and data["category_id"] is not None:
        rc = await db.execute(
            select(ItemCategory.id).where(
                ItemCategory.id == data["category_id"],
                ItemCategory.business_id == business_id,
            )
        )
        if rc.first() is None:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="category_id not found")
        i.category_id = data["category_id"]
        cid = i.category_id
    if "name" in data and data["name"] is not None:
        if await _item_dup(db, business_id, cid, data["name"], exclude_id=item_id):
            er = await db.execute(
                select(CatalogItem.id).where(
                    CatalogItem.business_id == business_id,
                    CatalogItem.category_id == cid,
                    func.lower(CatalogItem.name) == _norm_name(data["name"]),
                    CatalogItem.id != item_id,
                )
            )
            oid = er.scalar_one()
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail={
                    "message": "An item with this name already exists in this category",
                    "existing_item_id": str(oid),
                },
            )
        i.name = data["name"].strip()
    if "default_unit" in data:
        i.default_unit = data["default_unit"]
        if i.default_unit != "bag":
            i.default_kg_per_bag = None
    if "default_kg_per_bag" in data:
        if i.default_unit == "bag":
            i.default_kg_per_bag = data["default_kg_per_bag"]
        else:
            i.default_kg_per_bag = None
    await db.commit()
    await db.refresh(i)
    return CatalogItemOut(
        id=i.id,
        category_id=i.category_id,
        name=i.name,
        default_unit=i.default_unit,
        default_kg_per_bag=float(i.default_kg_per_bag) if i.default_kg_per_bag is not None else None,
    )


@router.delete("/catalog-items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_catalog_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    r = await db.execute(
        select(CatalogItem).where(
            CatalogItem.id == item_id,
            CatalogItem.business_id == business_id,
        )
    )
    i = r.scalar_one_or_none()
    if i is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    ec = await db.execute(
        select(func.count(EntryLineItem.id)).where(EntryLineItem.catalog_item_id == item_id)
    )
    if int(ec.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a catalog item that is linked to purchase entry lines",
        )
    vr = await db.execute(select(CatalogVariant.id).where(CatalogVariant.catalog_item_id == item_id))
    vids = [row[0] for row in vr.all()]
    if vids:
        ec2 = await db.execute(
            select(func.count(EntryLineItem.id)).where(EntryLineItem.catalog_variant_id.in_(vids))
        )
        if int(ec2.scalar() or 0) > 0:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="Cannot delete a catalog item whose variants are linked to purchase entry lines",
            )
    await db.delete(i)
    await db.commit()


# --- Variants (Category → Item → Variant) ---


@router.get("/catalog-items/{item_id}/variants", response_model=list[CatalogVariantOut])
async def list_catalog_variants(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    r = await db.execute(
        select(CatalogVariant)
        .where(
            CatalogVariant.business_id == business_id,
            CatalogVariant.catalog_item_id == item_id,
        )
        .order_by(func.lower(CatalogVariant.name))
    )
    rows = r.scalars().all()
    return [
        CatalogVariantOut(
            id=v.id,
            catalog_item_id=v.catalog_item_id,
            name=v.name,
            default_kg_per_bag=float(v.default_kg_per_bag) if v.default_kg_per_bag is not None else None,
        )
        for v in rows
    ]


@router.post("/catalog-items/{item_id}/variants", response_model=CatalogVariantOut, status_code=status.HTTP_201_CREATED)
async def create_catalog_variant(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CatalogVariantCreate,
):
    del _m
    ir = await db.execute(
        select(CatalogItem.id).where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
    )
    if ir.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Catalog item not found")
    if await _variant_dup(db, business_id, item_id, body.name):
        raise HTTPException(status.HTTP_409_CONFLICT, detail="A variant with this name already exists for this item")
    v = CatalogVariant(
        business_id=business_id,
        catalog_item_id=item_id,
        name=body.name.strip(),
        default_kg_per_bag=body.default_kg_per_bag,
    )
    db.add(v)
    await db.commit()
    await db.refresh(v)
    return CatalogVariantOut(
        id=v.id,
        catalog_item_id=v.catalog_item_id,
        name=v.name,
        default_kg_per_bag=float(v.default_kg_per_bag) if v.default_kg_per_bag is not None else None,
    )


@router.patch("/catalog-variants/{variant_id}", response_model=CatalogVariantOut)
async def update_catalog_variant(
    business_id: uuid.UUID,
    variant_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CatalogVariantUpdate,
):
    del _m
    r = await db.execute(
        select(CatalogVariant).where(
            CatalogVariant.id == variant_id,
            CatalogVariant.business_id == business_id,
        )
    )
    v = r.scalar_one_or_none()
    if v is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Variant not found")
    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        if await _variant_dup(db, business_id, v.catalog_item_id, data["name"], exclude_id=variant_id):
            raise HTTPException(status.HTTP_409_CONFLICT, detail="A variant with this name already exists for this item")
        v.name = data["name"].strip()
    if "default_kg_per_bag" in data:
        v.default_kg_per_bag = data["default_kg_per_bag"]
    await db.commit()
    await db.refresh(v)
    return CatalogVariantOut(
        id=v.id,
        catalog_item_id=v.catalog_item_id,
        name=v.name,
        default_kg_per_bag=float(v.default_kg_per_bag) if v.default_kg_per_bag is not None else None,
    )


@router.delete("/catalog-variants/{variant_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_catalog_variant(
    business_id: uuid.UUID,
    variant_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    r = await db.execute(
        select(CatalogVariant).where(
            CatalogVariant.id == variant_id,
            CatalogVariant.business_id == business_id,
        )
    )
    v = r.scalar_one_or_none()
    if v is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Variant not found")
    ec = await db.execute(
        select(func.count(EntryLineItem.id)).where(EntryLineItem.catalog_variant_id == variant_id)
    )
    if int(ec.scalar() or 0) > 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="Cannot delete a variant that is linked to purchase entry lines",
        )
    await db.delete(v)
    await db.commit()
