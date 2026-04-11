import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import require_membership, require_owner_membership
from app.models import CatalogItem, EntryLineItem, ItemCategory, Membership
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
    default_unit: str | None = Field(default=None, pattern="^(kg|box|piece)$")


class CatalogItemUpdate(BaseModel):
    category_id: uuid.UUID | None = None
    name: str | None = Field(default=None, min_length=1, max_length=512)
    default_unit: str | None = Field(default=None, pattern="^(kg|box|piece)$")


class CatalogItemOut(BaseModel):
    id: uuid.UUID
    category_id: uuid.UUID
    name: str
    default_unit: str | None

    model_config = {"from_attributes": True}


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
    body: ItemCategoryCreate,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
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
    body: ItemCategoryUpdate,
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
        )
        for i in rows
    ]


@router.post("/catalog-items", response_model=CatalogItemOut, status_code=status.HTTP_201_CREATED)
async def create_catalog_item(
    business_id: uuid.UUID,
    body: CatalogItemCreate,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
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
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="An item with this name already exists in this category",
        )
    i = CatalogItem(
        business_id=business_id,
        category_id=body.category_id,
        name=body.name.strip(),
        default_unit=body.default_unit,
    )
    db.add(i)
    await db.commit()
    await db.refresh(i)
    return CatalogItemOut(
        id=i.id,
        category_id=i.category_id,
        name=i.name,
        default_unit=i.default_unit,
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
    )


@router.patch("/catalog-items/{item_id}", response_model=CatalogItemOut)
async def update_catalog_item(
    business_id: uuid.UUID,
    item_id: uuid.UUID,
    body: CatalogItemUpdate,
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
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                detail="An item with this name already exists in this category",
            )
        i.name = data["name"].strip()
    if "default_unit" in data:
        i.default_unit = data["default_unit"]
    await db.commit()
    await db.refresh(i)
    return CatalogItemOut(
        id=i.id,
        category_id=i.category_id,
        name=i.name,
        default_unit=i.default_unit,
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
    await db.delete(i)
    await db.commit()
