"""Fuzzy name matching for duplicate prevention (rapidfuzz, token_sort_ratio)."""

from __future__ import annotations

import uuid

from rapidfuzz import fuzz, process
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

from app.models import CatalogItem, CatalogVariant, ItemCategory, Supplier

FUZZY_THRESHOLD = 70


def best_token_sort_match(query: str, candidates: list[str]) -> tuple[str | None, int]:
    """Return (best_candidate, score) if score >= threshold, else (None, best_score)."""
    q = query.lower().strip()
    if not q or not candidates:
        return None, 0
    best: str | None = None
    best_score = 0
    for c in candidates:
        if not c:
            continue
        s = int(fuzz.token_sort_ratio(q, c.lower()))
        if s > best_score:
            best_score = s
            best = c
    if best is not None and best_score >= FUZZY_THRESHOLD:
        return best, best_score
    return None, best_score


async def fuzzy_find_similar_supplier_name(
    db: AsyncSession, business_id: uuid.UUID, name: str
) -> str | None:
    r = await db.execute(select(Supplier.name).where(Supplier.business_id == business_id))
    names = [row[0] for row in r.all() if row[0]]
    matched, _ = best_token_sort_match(name, names)
    return matched


async def fuzzy_find_similar_category_name(
    db: AsyncSession, business_id: uuid.UUID, name: str
) -> str | None:
    r = await db.execute(select(ItemCategory.name).where(ItemCategory.business_id == business_id))
    names = [row[0] for row in r.all() if row[0]]
    matched, _ = best_token_sort_match(name, names)
    return matched


async def fuzzy_find_similar_catalog_item_name_in_category(
    db: AsyncSession,
    business_id: uuid.UUID,
    category_id: uuid.UUID,
    item_name: str,
) -> str | None:
    r = await db.execute(
        select(CatalogItem.name).where(
            CatalogItem.business_id == business_id,
            CatalogItem.category_id == category_id,
        )
    )
    names = [row[0] for row in r.all() if row[0]]
    matched, _ = best_token_sort_match(item_name, names)
    return matched


async def fuzzy_find_similar_variant_name_for_item(
    db: AsyncSession,
    business_id: uuid.UUID,
    catalog_item_id: uuid.UUID,
    variant_name: str,
) -> str | None:
    r = await db.execute(
        select(CatalogVariant.name).where(
            CatalogVariant.business_id == business_id,
            CatalogVariant.catalog_item_id == catalog_item_id,
        )
    )
    names = [row[0] for row in r.all() if row[0]]
    matched, _ = best_token_sort_match(variant_name, names)
    return matched


async def fuzzy_find_catalog_item_for_entry_line(
    db: AsyncSession,
    business_id: uuid.UUID,
    item_name: str,
) -> CatalogItem | None:
    """Best catalog_items row by fuzzy name match for auto-linking entry lines (no IDs)."""
    r = await db.execute(
        select(CatalogItem)
        .options(joinedload(CatalogItem.category))
        .where(CatalogItem.business_id == business_id)
    )
    items = r.scalars().all()
    if not items:
        return None
    best: CatalogItem | None = None
    best_score = 0
    q = item_name.lower().strip()
    for it in items:
        s = int(fuzz.token_sort_ratio(q, it.name.lower()))
        if s > best_score:
            best_score = s
            best = it
    if best is not None and best_score >= FUZZY_THRESHOLD:
        return best
    return None


def rank_ids_by_token_sort(
    query: str,
    rows: list[tuple[uuid.UUID, str]],
    *,
    limit: int = 12,
    score_cutoff: int = 55,
) -> list[tuple[uuid.UUID, int]]:
    """Return (id, score) for fuzzy name matches, best first. Empty query → []."""
    q = query.lower().strip()
    if not q or not rows:
        return []
    names = [r[1] for r in rows]
    extracted = process.extract(
        q,
        names,
        scorer=fuzz.token_sort_ratio,
        limit=limit,
        score_cutoff=score_cutoff,
    )
    out: list[tuple[uuid.UUID, int]] = []
    seen: set[uuid.UUID] = set()
    for _match, score, idx in extracted:
        uid = rows[idx][0]
        if uid in seen:
            continue
        seen.add(uid)
        out.append((uid, int(score)))
    return out
