"""Unified search: catalog items, suppliers, entries (substring + fuzzy fallback)."""

from __future__ import annotations

import logging
import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy import and_, exists, func, or_, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.db_schema_compat import catalog_items_has_type_id_column
from app.database import get_db
from app.deps import require_membership
from app.models import CatalogItem, CategoryType, Entry, EntryLineItem, ItemCategory, Membership, Supplier
from app.schemas.entries import EntryLineOut, EntryOut
from app.services.fuzzy_catalog import rank_ids_by_token_sort

router = APIRouter(prefix="/v1/businesses/{business_id}", tags=["search"])
logger = logging.getLogger(__name__)

_PAIR_CAP = 5000


def _line_to_out(line: EntryLineItem) -> EntryLineOut:
    return EntryLineOut(
        id=line.id,
        catalog_item_id=line.catalog_item_id,
        catalog_variant_id=line.catalog_variant_id,
        item_name=line.item_name,
        category=line.category,
        qty=float(line.qty),
        unit=line.unit,
        bags=float(line.bags) if line.bags is not None else None,
        kg_per_bag=float(line.kg_per_bag) if line.kg_per_bag is not None else None,
        qty_kg=float(line.qty_kg) if line.qty_kg is not None else None,
        buy_price=float(line.buy_price),
        landing_cost=float(line.landing_cost),
        selling_price=float(line.selling_price) if line.selling_price is not None else None,
        profit=float(line.profit) if line.profit is not None else None,
        stock_note=line.stock_note.strip() if line.stock_note else None,
    )


def _entry_to_out(entry: Entry) -> EntryOut:
    tc = float(entry.transport_cost) if entry.transport_cost is not None else None
    ca = float(entry.commission_amount) if entry.commission_amount is not None else None
    pl = entry.place.strip() if entry.place else None
    return EntryOut(
        id=entry.id,
        business_id=entry.business_id,
        entry_date=entry.entry_date,
        supplier_id=entry.supplier_id,
        broker_id=entry.broker_id,
        invoice_no=entry.invoice_no,
        place=pl,
        transport_cost=tc,
        commission_amount=ca,
        lines=[_line_to_out(li) for li in entry.lines],
    )


class UnifiedSearchOut(BaseModel):
    catalog_items: list[dict[str, Any]] = Field(default_factory=list)
    suppliers: list[dict[str, Any]] = Field(default_factory=list)
    entries: list[dict[str, Any]] = Field(default_factory=list)
    fuzzy_catalog_used: bool = False
    fuzzy_suppliers_used: bool = False


def _hydrate_catalog_rows(rows: list[tuple[Any, ...]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for row in rows:
        icode: str | None
        if len(row) == 11:
            _id, name, cat, tname, du, dkg, hsn, icode, tax, dlc, lpp = row
        elif len(row) == 10:
            _id, name, cat, tname, du, dkg, hsn, tax, dlc, lpp = row
            icode = None
        else:
            _id, name, cat, tname, du, dkg, hsn, tax, dlc, lpp = (
                row[0],
                row[1],
                row[2],
                None,
                row[3],
                row[4],
                row[5],
                row[6],
                row[7],
                row[8],
            )
            icode = None
        icode_s = str(icode).strip() if icode is not None and str(icode).strip() else None
        out.append(
            {
                "id": str(_id),
                "name": name,
                "category_name": cat,
                "type_name": tname,
                "default_unit": du,
                "default_kg_per_bag": float(dkg) if dkg is not None else None,
                "hsn_code": hsn,
                "item_code": icode_s,
                "tax_percent": float(tax) if tax is not None else None,
                "default_landing_cost": float(dlc) if dlc is not None else None,
                "last_purchase_price": float(lpp) if lpp is not None else None,
            }
        )
    return out


@router.get("/search", response_model=UnifiedSearchOut)
async def unified_search(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    q: str = Query(..., min_length=1, max_length=200),
):
    del _m

    try:
        needle = q.strip().lower()
        if len(needle) < 1:
            return UnifiedSearchOut()

        ic = ItemCategory
        ct = CategoryType
        has_type = await catalog_items_has_type_id_column(db)
        extra_cols = (
            CatalogItem.default_unit,
            CatalogItem.default_kg_per_bag,
            CatalogItem.hsn_code,
            CatalogItem.item_code,
            CatalogItem.tax_percent,
            CatalogItem.default_landing_cost,
            CatalogItem.last_purchase_price,
        )
        item_name_cat_hsn = or_(
            func.lower(CatalogItem.name).contains(needle),
            func.lower(ic.name).contains(needle),
            and_(
                CatalogItem.hsn_code.isnot(None),
                func.lower(CatalogItem.hsn_code).contains(needle),
            ),
            and_(
                CatalogItem.item_code.isnot(None),
                func.lower(CatalogItem.item_code).contains(needle),
            ),
        )
        if has_type:
            sq_items = (
                select(
                    CatalogItem.id,
                    CatalogItem.name,
                    ic.name.label("category_name"),
                    ct.name.label("type_name"),
                    *extra_cols,
                )
                .join(ic, ic.id == CatalogItem.category_id)
                .outerjoin(ct, ct.id == CatalogItem.type_id)
                .where(
                    CatalogItem.business_id == business_id,
                    item_name_cat_hsn,
                )
                .order_by(func.lower(CatalogItem.name))
                .limit(40)
            )
        else:
            sq_items = (
                select(
                    CatalogItem.id,
                    CatalogItem.name,
                    ic.name.label("category_name"),
                    *extra_cols,
                )
                .join(ic, ic.id == CatalogItem.category_id)
                .where(
                    CatalogItem.business_id == business_id,
                    item_name_cat_hsn,
                )
                .order_by(func.lower(CatalogItem.name))
                .limit(40)
            )
        ir = await db.execute(sq_items)
        catalog_rows = list(ir.all())
        if not has_type:
            catalog_rows = [(*r[:3], None, *r[3:]) for r in catalog_rows]
        fuzzy_catalog_used = False
        if not catalog_rows:
            pairs_r = await db.execute(
                select(CatalogItem.id, CatalogItem.name).where(
                    CatalogItem.business_id == business_id
                ).limit(_PAIR_CAP)
            )
            pairs = [(row[0], row[1]) for row in pairs_r.all() if row[1]]
            fuzzy_cut = 40 if len(needle) < 2 else 52
            ranked = rank_ids_by_token_sort(needle, pairs, limit=40, score_cutoff=fuzzy_cut)
            if ranked:
                fuzzy_catalog_used = True
                ids = [uid for uid, _sc in ranked]
                if has_type:
                    sq_h = (
                        select(
                            CatalogItem.id,
                            CatalogItem.name,
                            ic.name.label("category_name"),
                            ct.name.label("type_name"),
                            *extra_cols,
                        )
                        .join(ic, ic.id == CatalogItem.category_id)
                        .outerjoin(ct, ct.id == CatalogItem.type_id)
                        .where(CatalogItem.id.in_(ids))
                    )
                else:
                    sq_h = (
                        select(
                            CatalogItem.id,
                            CatalogItem.name,
                            ic.name.label("category_name"),
                            *extra_cols,
                        )
                        .join(ic, ic.id == CatalogItem.category_id)
                        .where(CatalogItem.id.in_(ids))
                    )
                hr = await db.execute(sq_h)
                by_id = {row[0]: row for row in hr.all()}
                catalog_rows = []
                for i in ids:
                    if i not in by_id:
                        continue
                    row = by_id[i]
                    if has_type:
                        catalog_rows.append(row)
                    else:
                        catalog_rows.append((*row[:3], None, *row[3:]))

        catalog_items = _hydrate_catalog_rows(catalog_rows)

        sup_match = or_(
            func.lower(Supplier.name).contains(needle),
            and_(
                Supplier.gst_number.isnot(None),
                func.lower(Supplier.gst_number).contains(needle),
            ),
        )
        sq_sup = (
            select(Supplier.id, Supplier.name)
            .where(
                Supplier.business_id == business_id,
                sup_match,
            )
            .order_by(func.lower(Supplier.name))
            .limit(12)
        )
        sr = await db.execute(sq_sup)
        sup_rows = list(sr.all())
        fuzzy_suppliers_used = False
        if not sup_rows:
            pairs_r = await db.execute(
                select(Supplier.id, Supplier.name).where(Supplier.business_id == business_id).limit(_PAIR_CAP)
            )
            pairs = [(row[0], row[1]) for row in pairs_r.all() if row[1]]
            sup_fuzzy_cut = 40 if len(needle) < 2 else 52
            ranked = rank_ids_by_token_sort(needle, pairs, limit=12, score_cutoff=sup_fuzzy_cut)
            if ranked:
                fuzzy_suppliers_used = True
                ids = [uid for uid, _sc in ranked]
                hr = await db.execute(select(Supplier.id, Supplier.name).where(Supplier.id.in_(ids)))
                by_id = {row[0]: row for row in hr.all()}
                sup_rows = [by_id[i] for i in ids if i in by_id]
        suppliers = [{"id": str(row[0]), "name": row[1]} for row in sup_rows]

        line_match = exists(
            select(EntryLineItem.id).where(
                EntryLineItem.entry_id == Entry.id,
                func.lower(EntryLineItem.item_name).contains(needle),
            )
        )
        sq_ent = (
            select(Entry)
            .where(Entry.business_id == business_id, line_match)
            .options(selectinload(Entry.lines))
            .order_by(Entry.entry_date.desc(), Entry.created_at.desc())
            .limit(12)
        )
        er = await db.execute(sq_ent)
        entries = [e for e in er.scalars().unique().all()]
        entries_out = [_entry_to_out(e).model_dump(mode="json") for e in entries]

        return UnifiedSearchOut(
            catalog_items=catalog_items,
            suppliers=suppliers,
            entries=entries_out,
            fuzzy_catalog_used=fuzzy_catalog_used,
            fuzzy_suppliers_used=fuzzy_suppliers_used,
        )
    except SQLAlchemyError:
        logger.exception("unified_search failed business_id=%s q=%s", business_id, q)
        return UnifiedSearchOut()
