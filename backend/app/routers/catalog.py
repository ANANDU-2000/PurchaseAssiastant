import logging
import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import and_, desc, func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import load_only

from app.database import get_db
from app.db_schema_compat import catalog_items_has_type_id_column
from app.deps import require_membership, require_owner_membership
from app.models import (
    CatalogItem,
    CatalogVariant,
    CategoryType,
    EntryLineItem,
    ItemCategory,
    Membership,
    TradePurchase,
    TradePurchaseLine,
)
from app.models.contacts import Supplier
from app.models.supplier_item_default import SupplierItemDefault
from app.models.entry import Entry

router = APIRouter(prefix="/v1/businesses/{business_id}", tags=["catalog"])

logger = logging.getLogger(__name__)

GENERAL_TYPE_NAME = "General"


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


class CategoryTypeCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)


class CategoryTypeUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=255)


class CategoryTypeOut(BaseModel):
    id: uuid.UUID
    category_id: uuid.UUID
    name: str

    model_config = {"from_attributes": True}


_UNIT_PATTERN = "^(kg|box|piece|bag|tin)$"


class CatalogItemCreate(BaseModel):
    category_id: uuid.UUID
    type_id: uuid.UUID | None = None
    name: str = Field(min_length=1, max_length=512)
    default_unit: str = Field(pattern=_UNIT_PATTERN)
    default_kg_per_bag: float | None = Field(default=None, gt=0)
    default_purchase_unit: str | None = Field(default=None, pattern=_UNIT_PATTERN)
    default_sale_unit: str | None = Field(default=None, pattern=_UNIT_PATTERN)
    hsn_code: str | None = Field(default=None, max_length=32)
    tax_percent: float | None = Field(default=None, ge=0, le=100)
    default_landing_cost: float | None = Field(default=None, ge=0)
    default_selling_cost: float | None = Field(default=None, ge=0)

    @field_validator("name", mode="before")
    @classmethod
    def _strip_required_str(cls, v: object) -> object:
        if isinstance(v, str):
            return v.strip()
        return v

    @field_validator("name")
    @classmethod
    def _name_nonempty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("name must not be empty or whitespace")
        return " ".join(v.split())

    @field_validator("hsn_code", mode="before")
    @classmethod
    def _hsn_optional(cls, v: object) -> object:
        if v is None:
            return None
        if isinstance(v, str):
            t = v.strip()
            return t if t else None
        return v


class CatalogItemUpdate(BaseModel):
    category_id: uuid.UUID | None = None
    type_id: uuid.UUID | None = None
    name: str | None = Field(default=None, min_length=1, max_length=512)
    default_unit: str | None = Field(default=None, pattern=_UNIT_PATTERN)
    default_kg_per_bag: float | None = Field(default=None, gt=0)
    default_purchase_unit: str | None = Field(default=None, pattern=_UNIT_PATTERN)
    default_sale_unit: str | None = Field(default=None, pattern=_UNIT_PATTERN)
    hsn_code: str | None = Field(default=None, min_length=1, max_length=32)
    tax_percent: float | None = Field(default=None, ge=0, le=100)
    default_landing_cost: float | None = Field(default=None, ge=0)
    default_selling_cost: float | None = Field(default=None, ge=0)

    @field_validator("name", "hsn_code", mode="before")
    @classmethod
    def _strip_update_str(cls, v: object) -> object:
        if v is None:
            return v
        if isinstance(v, str):
            t = v.strip()
            return t if t else None
        return v

    @field_validator("name")
    @classmethod
    def _name_if_set(cls, v: str | None) -> str | None:
        if v is None:
            return v
        if not v.strip():
            raise ValueError("name must not be empty or whitespace")
        return " ".join(v.split())


class CatalogItemOut(BaseModel):
    id: uuid.UUID
    category_id: uuid.UUID
    type_id: uuid.UUID | None = None
    type_name: str | None = None
    name: str
    default_unit: str | None
    default_kg_per_bag: float | None = None
    default_purchase_unit: str | None = None
    default_sale_unit: str | None = None
    hsn_code: str | None = None
    tax_percent: float | None = None
    default_landing_cost: float | None = None
    default_selling_cost: float | None = None
    last_purchase_price: float | None = None

    model_config = {"from_attributes": True}


class SupplierPurchaseDefaultsOut(BaseModel):
    catalog_item_id: uuid.UUID
    supplier_id: uuid.UUID
    last_price: float | None = None
    last_discount: float | None = None
    last_payment_days: int | None = None
    purchase_count: int = 0
    item_hsn_code: str | None = None
    item_tax_percent: float | None = None
    item_default_unit: str | None = None
    item_default_kg_per_bag: float | None = None
    item_default_landing_cost: float | None = None
    item_default_purchase_unit: str | None = None


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


class TradeSupplierPriceRow(BaseModel):
    supplier_id: uuid.UUID
    supplier_name: str
    landing_cost: float
    unit: str
    last_purchase_date: date
    is_best: bool = False


class CatalogItemTradeSupplierPricesOut(BaseModel):
    """Latest trade purchase line per supplier + last five landed prices (any supplier)."""

    catalog_item_id: uuid.UUID
    suppliers: list[TradeSupplierPriceRow] = Field(default_factory=list)
    last_five_landing_prices: list[float] = Field(default_factory=list)
    avg_landing_from_trade: float | None = None


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
    type_id: uuid.UUID | None,
    name: str,
    exclude_id: uuid.UUID | None = None,
    *,
    has_type_col: bool = True,
) -> bool:
    q = select(CatalogItem.id).where(
        CatalogItem.business_id == business_id,
        CatalogItem.category_id == category_id,
        func.lower(CatalogItem.name) == _norm_name(name),
    )
    if has_type_col:
        if type_id is not None:
            q = q.where(CatalogItem.type_id == type_id)
        else:
            q = q.where(CatalogItem.type_id.is_(None))
    if exclude_id is not None:
        q = q.where(CatalogItem.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


async def _type_name_dup(
    db: AsyncSession,
    category_id: uuid.UUID,
    name: str,
    exclude_id: uuid.UUID | None = None,
) -> bool:
    q = select(CategoryType.id).where(
        CategoryType.category_id == category_id,
        func.lower(CategoryType.name) == _norm_name(name),
    )
    if exclude_id is not None:
        q = q.where(CategoryType.id != exclude_id)
    r = await db.execute(q)
    return r.first() is not None


async def _get_or_create_general_type_id(
    db: AsyncSession, business_id: uuid.UUID, category_id: uuid.UUID
) -> uuid.UUID:
    r = await db.execute(
        select(CategoryType.id).where(
            CategoryType.category_id == category_id,
            func.lower(CategoryType.name) == _norm_name(GENERAL_TYPE_NAME),
        )
    )
    row = r.first()
    if row is not None:
        return row[0]
    cr = await db.execute(
        select(ItemCategory.id).where(
            ItemCategory.id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if cr.first() is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="category_id not found in this business")
    ct = CategoryType(category_id=category_id, name=GENERAL_TYPE_NAME)
    db.add(ct)
    await db.flush()
    return ct.id


class _UnsetSentinel:
    __slots__ = ()


_UNSET = _UnsetSentinel()

# Columns safe to load when catalog_items.type_id is missing (older DBs).
_CATALOG_ITEM_CORE = (
    CatalogItem.id,
    CatalogItem.business_id,
    CatalogItem.category_id,
    CatalogItem.name,
    CatalogItem.default_unit,
    CatalogItem.default_kg_per_bag,
    CatalogItem.hsn_code,
    CatalogItem.tax_percent,
    CatalogItem.default_landing_cost,
    CatalogItem.default_selling_cost,
    CatalogItem.default_purchase_unit,
    CatalogItem.default_sale_unit,
    CatalogItem.last_purchase_price,
    CatalogItem.created_at,
)


def _catalog_item_out(
    i: CatalogItem,
    type_name: str | None = None,
    *,
    type_id: uuid.UUID | None | _UnsetSentinel = _UNSET,
) -> CatalogItemOut:
    tid = i.type_id if type_id is _UNSET else type_id
    return CatalogItemOut(
        id=i.id,
        category_id=i.category_id,
        type_id=tid,
        type_name=type_name,
        name=i.name,
        default_unit=i.default_unit,
        default_kg_per_bag=float(i.default_kg_per_bag) if i.default_kg_per_bag is not None else None,
        default_purchase_unit=getattr(i, "default_purchase_unit", None),
        default_sale_unit=getattr(i, "default_sale_unit", None),
        hsn_code=getattr(i, "hsn_code", None),
        tax_percent=float(i.tax_percent) if getattr(i, "tax_percent", None) is not None else None,
        default_landing_cost=float(i.default_landing_cost)
        if getattr(i, "default_landing_cost", None) is not None
        else None,
        default_selling_cost=float(i.default_selling_cost)
        if getattr(i, "default_selling_cost", None) is not None
        else None,
        last_purchase_price=float(i.last_purchase_price)
        if getattr(i, "last_purchase_price", None) is not None
        else None,
    )


async def _verify_type_in_category(
    db: AsyncSession,
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    type_id: uuid.UUID,
) -> None:
    r = await db.execute(
        select(CategoryType.id)
        .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
        .where(
            CategoryType.id == type_id,
            CategoryType.category_id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if r.first() is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="type_id not found for this category")


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
    await db.flush()
    db.add(CategoryType(category_id=c.id, name=GENERAL_TYPE_NAME))
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


# --- Category types (Category → Type → item) ---


@router.get(
    "/item-categories/{category_id}/category-types",
    response_model=list[CategoryTypeOut],
)
async def list_category_types(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
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
    r = await db.execute(
        select(CategoryType)
        .where(CategoryType.category_id == category_id)
        .order_by(func.lower(CategoryType.name))
    )
    rows = r.scalars().all()
    return [CategoryTypeOut(id=t.id, category_id=t.category_id, name=t.name) for t in rows]


@router.post(
    "/item-categories/{category_id}/category-types",
    response_model=CategoryTypeOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_category_type(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CategoryTypeCreate,
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
    if await _type_name_dup(db, category_id, body.name):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="A type with this name already exists in this category",
        )
    t = CategoryType(category_id=category_id, name=body.name.strip())
    db.add(t)
    await db.commit()
    await db.refresh(t)
    return CategoryTypeOut(id=t.id, category_id=t.category_id, name=t.name)


@router.patch(
    "/item-categories/{category_id}/category-types/{type_id}",
    response_model=CategoryTypeOut,
)
async def update_category_type(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    type_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CategoryTypeUpdate,
):
    del _m
    r = await db.execute(
        select(CategoryType)
        .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
        .where(
            CategoryType.id == type_id,
            CategoryType.category_id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    t = r.scalar_one_or_none()
    if t is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Type not found")
    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        if await _type_name_dup(db, category_id, data["name"], exclude_id=type_id):
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="A type with this name already exists in this category",
            )
        t.name = data["name"].strip()
    await db.commit()
    await db.refresh(t)
    return CategoryTypeOut(id=t.id, category_id=t.category_id, name=t.name)


@router.delete(
    "/item-categories/{category_id}/category-types/{type_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_category_type(
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    type_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    r = await db.execute(
        select(CategoryType)
        .join(ItemCategory, ItemCategory.id == CategoryType.category_id)
        .where(
            CategoryType.id == type_id,
            CategoryType.category_id == category_id,
            ItemCategory.business_id == business_id,
        )
    )
    t = r.scalar_one_or_none()
    if t is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Type not found")
    if await catalog_items_has_type_id_column(db):
        ic = await db.execute(
            select(func.count(CatalogItem.id)).where(CatalogItem.type_id == type_id)
        )
        if int(ic.scalar() or 0) > 0:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="Cannot delete a type that still has catalog items — move or delete items first",
            )
    await db.delete(t)
    await db.commit()


@router.get("/catalog-items", response_model=list[CatalogItemOut])
async def list_catalog_items(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    category_id: uuid.UUID | None = Query(None, description="Filter by category"),
    type_id: uuid.UUID | None = Query(None, description="Filter by category type"),
):
    del _m
    try:
        has_type_col = await catalog_items_has_type_id_column(db)
        if has_type_col:
            q = (
                select(CatalogItem, CategoryType.name)
                .outerjoin(CategoryType, CategoryType.id == CatalogItem.type_id)
                .where(CatalogItem.business_id == business_id)
            )
            if category_id is not None:
                q = q.where(CatalogItem.category_id == category_id)
            if type_id is not None:
                q = q.where(CatalogItem.type_id == type_id)
            q = q.order_by(func.lower(CatalogItem.name))
            r = await db.execute(q)
            return [_catalog_item_out(i, tn) for i, tn in r.all()]

        q = (
            select(CatalogItem)
            .options(load_only(*_CATALOG_ITEM_CORE))
            .where(CatalogItem.business_id == business_id)
        )
        if category_id is not None:
            q = q.where(CatalogItem.category_id == category_id)
        q = q.order_by(func.lower(CatalogItem.name))
        r = await db.execute(q)
        return [_catalog_item_out(i, None, type_id=None) for i in r.scalars().all()]
    except SQLAlchemyError:
        logger.exception(
            "list_catalog_items failed business_id=%s category_id=%s type_id=%s",
            business_id,
            category_id,
            type_id,
        )
        raise


@router.post("/catalog-items", response_model=CatalogItemOut, status_code=status.HTTP_201_CREATED)
async def create_catalog_item(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: CatalogItemCreate,
):
    del _m
    has_type_col = await catalog_items_has_type_id_column(db)
    rc = await db.execute(
        select(ItemCategory.id).where(
            ItemCategory.id == body.category_id,
            ItemCategory.business_id == business_id,
        )
    )
    if rc.first() is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="category_id not found in this business")
    resolved_type: uuid.UUID
    if body.type_id is not None:
        await _verify_type_in_category(db, business_id, body.category_id, body.type_id)
        resolved_type = body.type_id
    else:
        resolved_type = await _get_or_create_general_type_id(db, business_id, body.category_id)
    if await _item_dup(
        db, business_id, body.category_id, resolved_type, body.name, has_type_col=has_type_col
    ):
        dup_q = select(CatalogItem.id).where(
            CatalogItem.business_id == business_id,
            CatalogItem.category_id == body.category_id,
            func.lower(CatalogItem.name) == _norm_name(body.name),
        )
        if has_type_col:
            dup_q = dup_q.where(CatalogItem.type_id == resolved_type)
        er = await db.execute(dup_q)
        eid = er.scalar_one()
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "message": "An item with this name already exists for this category and type",
                "existing_item_id": str(eid),
            },
        )
    dkg = body.default_kg_per_bag if body.default_unit == "bag" else None
    purchase_u = body.default_purchase_unit or body.default_unit
    i = CatalogItem(
        business_id=business_id,
        category_id=body.category_id,
        type_id=resolved_type,
        name=body.name.strip(),
        default_unit=body.default_unit,
        default_kg_per_bag=dkg,
        default_purchase_unit=purchase_u,
        default_sale_unit=body.default_sale_unit,
        hsn_code=(body.hsn_code or "").strip() or None,
        tax_percent=body.tax_percent,
        default_landing_cost=body.default_landing_cost,
        default_selling_cost=body.default_selling_cost,
    )
    db.add(i)
    await db.commit()
    await db.refresh(i)
    tn = None
    if i.type_id is not None:
        tr = await db.execute(select(CategoryType.name).where(CategoryType.id == i.type_id))
        tn = tr.scalar_one_or_none()
    return _catalog_item_out(i, tn)


@router.get("/catalog-items/{item_id}", response_model=CatalogItemOut)
async def get_catalog_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    try:
        has_type_col = await catalog_items_has_type_id_column(db)
        if has_type_col:
            r = await db.execute(
                select(CatalogItem, CategoryType.name)
                .outerjoin(CategoryType, CategoryType.id == CatalogItem.type_id)
                .where(
                    CatalogItem.id == item_id,
                    CatalogItem.business_id == business_id,
                )
            )
            row = r.one_or_none()
            if row is None:
                raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
            i, tn = row
            return _catalog_item_out(i, tn)

        r = await db.execute(
            select(CatalogItem)
            .options(load_only(*_CATALOG_ITEM_CORE))
            .where(
                CatalogItem.id == item_id,
                CatalogItem.business_id == business_id,
            )
        )
        i = r.scalar_one_or_none()
        if i is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
        return _catalog_item_out(i, None, type_id=None)
    except SQLAlchemyError:
        logger.exception("get_catalog_item failed business_id=%s item_id=%s", business_id, item_id)
        raise


@router.get(
    "/catalog-items/{item_id}/supplier-purchase-defaults",
    response_model=SupplierPurchaseDefaultsOut,
)
async def supplier_purchase_defaults(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    supplier_id: uuid.UUID = Query(...),
):
    del _m
    ir = await db.execute(
        select(CatalogItem).where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
    )
    item = ir.scalar_one_or_none()
    if item is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    sr = await db.execute(
        select(Supplier.id).where(Supplier.id == supplier_id, Supplier.business_id == business_id)
    )
    if sr.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Supplier not found")
    dr = await db.execute(
        select(SupplierItemDefault).where(
            SupplierItemDefault.business_id == business_id,
            SupplierItemDefault.supplier_id == supplier_id,
            SupplierItemDefault.catalog_item_id == item_id,
        )
    )
    d = dr.scalar_one_or_none()
    return SupplierPurchaseDefaultsOut(
        catalog_item_id=item.id,
        supplier_id=supplier_id,
        last_price=float(d.last_price) if d and d.last_price is not None else None,
        last_discount=float(d.last_discount) if d and d.last_discount is not None else None,
        last_payment_days=d.last_payment_days if d else None,
        purchase_count=int(d.purchase_count or 0) if d else 0,
        item_hsn_code=item.hsn_code,
        item_tax_percent=float(item.tax_percent) if item.tax_percent is not None else None,
        item_default_unit=item.default_unit,
        item_default_kg_per_bag=float(item.default_kg_per_bag) if item.default_kg_per_bag is not None else None,
        item_default_landing_cost=float(item.default_landing_cost)
        if item.default_landing_cost is not None
        else None,
        item_default_purchase_unit=item.default_purchase_unit or item.default_unit,
    )


@router.get(
    "/catalog-items/{item_id}/trade-supplier-prices",
    response_model=CatalogItemTradeSupplierPricesOut,
)
async def catalog_item_trade_supplier_prices(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    """Latest landed price per supplier from trade purchases; last five prices; trade-only average."""
    del _m
    ir = await db.execute(
        select(CatalogItem.id).where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
    )
    if ir.first() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")

    line_rows = (
        select(
            TradePurchase.supplier_id,
            Supplier.name,
            TradePurchaseLine.landing_cost,
            TradePurchaseLine.unit,
            TradePurchase.purchase_date,
            TradePurchaseLine.id,
        )
        .select_from(TradePurchaseLine)
        .join(TradePurchase, TradePurchaseLine.trade_purchase_id == TradePurchase.id)
        .join(Supplier, Supplier.id == TradePurchase.supplier_id)
        .where(
            TradePurchase.business_id == business_id,
            TradePurchaseLine.catalog_item_id == item_id,
            TradePurchase.supplier_id.isnot(None),
            TradePurchase.status.in_(("saved", "confirmed")),
        )
        .order_by(desc(TradePurchase.purchase_date), desc(TradePurchaseLine.id))
    )
    lr = await db.execute(line_rows)
    all_rows = lr.all()

    seen_suppliers: set[uuid.UUID] = set()
    supplier_rows: list[tuple] = []
    landing_for_avg: list[float] = []
    last_five_prices: list[float] = []

    for row in all_rows:
        sid, sname, lc, unit, pdate, lid = row
        lc_f = float(lc) if lc is not None else None
        if lc_f is None:
            continue
        landing_for_avg.append(lc_f)
        if len(last_five_prices) < 5:
            last_five_prices.append(lc_f)
        if sid in seen_suppliers:
            continue
        seen_suppliers.add(sid)
        supplier_rows.append(
            (sid, sname, lc_f, unit, pdate, lid),
        )

    best_landing: float | None = None
    if supplier_rows:
        best_landing = min(r[2] for r in supplier_rows)

    suppliers_out: list[TradeSupplierPriceRow] = []
    for sid, sname, lc_f, unit, pdate, _lid in sorted(supplier_rows, key=lambda r: (r[2], r[0].hex)):
        suppliers_out.append(
            TradeSupplierPriceRow(
                supplier_id=sid,
                supplier_name=sname,
                landing_cost=lc_f,
                unit=unit,
                last_purchase_date=pdate,
                is_best=best_landing is not None and abs(lc_f - best_landing) < 1e-9,
            )
        )
    # Sort display: best first, then by price
    suppliers_out.sort(key=lambda s: (not s.is_best, s.landing_cost, s.supplier_name))

    avg_landing: float | None = None
    if landing_for_avg:
        avg_landing = sum(landing_for_avg) / len(landing_for_avg)

    return CatalogItemTradeSupplierPricesOut(
        catalog_item_id=item_id,
        suppliers=suppliers_out,
        last_five_landing_prices=last_five_prices,
        avg_landing_from_trade=avg_landing,
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
    has_type_col = await catalog_items_has_type_id_column(db)
    stmt = select(CatalogItem).where(
        CatalogItem.id == item_id,
        CatalogItem.business_id == business_id,
    )
    if not has_type_col:
        stmt = stmt.options(load_only(*_CATALOG_ITEM_CORE))
    r = await db.execute(stmt)
    i = r.scalar_one_or_none()
    if i is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Item not found")
    data = body.model_dump(exclude_unset=True)
    cid = i.category_id
    tid: uuid.UUID | None = i.type_id if has_type_col else None
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
        if has_type_col and "type_id" not in data:
            i.type_id = await _get_or_create_general_type_id(db, business_id, cid)
            tid = i.type_id
    if has_type_col and "type_id" in data:
        if data["type_id"] is None:
            i.type_id = await _get_or_create_general_type_id(db, business_id, cid)
        else:
            await _verify_type_in_category(db, business_id, cid, data["type_id"])
            i.type_id = data["type_id"]
        tid = i.type_id
    if "name" in data and data["name"] is not None:
        if await _item_dup(
            db, business_id, cid, tid, data["name"], exclude_id=item_id, has_type_col=has_type_col
        ):
            dup_q = select(CatalogItem.id).where(
                CatalogItem.business_id == business_id,
                CatalogItem.category_id == cid,
                func.lower(CatalogItem.name) == _norm_name(data["name"]),
                CatalogItem.id != item_id,
            )
            if has_type_col:
                dup_q = dup_q.where(CatalogItem.type_id == tid)
            er = await db.execute(dup_q)
            oid = er.scalar_one()
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail={
                    "message": "An item with this name already exists for this category and type",
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
    if "default_purchase_unit" in data:
        i.default_purchase_unit = data["default_purchase_unit"]
    if "default_sale_unit" in data:
        i.default_sale_unit = data["default_sale_unit"]
    if "hsn_code" in data:
        i.hsn_code = data["hsn_code"].strip() if data["hsn_code"] else None
    if "tax_percent" in data:
        i.tax_percent = data["tax_percent"]
    if "default_landing_cost" in data:
        i.default_landing_cost = data["default_landing_cost"]
    if "default_selling_cost" in data:
        i.default_selling_cost = data["default_selling_cost"]
    await db.commit()
    if not has_type_col:
        rr = await db.execute(
            select(CatalogItem)
            .options(load_only(*_CATALOG_ITEM_CORE))
            .where(CatalogItem.id == item_id, CatalogItem.business_id == business_id)
        )
        i_out = rr.scalar_one()
        return _catalog_item_out(i_out, None, type_id=None)
    await db.refresh(i)
    tn = None
    if i.type_id is not None:
        tr = await db.execute(select(CategoryType.name).where(CategoryType.id == i.type_id))
        tn = tr.scalar_one_or_none()
    return _catalog_item_out(i, tn)


@router.delete("/catalog-items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_catalog_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _owner
    has_type_col = await catalog_items_has_type_id_column(db)
    stmt = select(CatalogItem).where(
        CatalogItem.id == item_id,
        CatalogItem.business_id == business_id,
    )
    if not has_type_col:
        stmt = stmt.options(load_only(*_CATALOG_ITEM_CORE))
    r = await db.execute(stmt)
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
