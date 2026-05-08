"""Post-match safety gate: demote auto item matches when pack weight / unit channel disagrees.

Guards against severe ERP failures (e.g. wholesale \"Sugar 50kg\" bag line fuzzy-matched to a
retail 1kg SKU). Pure helpers + a small async applier used from ``pipeline._match_items``.
"""

from __future__ import annotations

import re
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CatalogItem
from app.services.scanner_v2.types import ItemRow

# Last kg token wins for strings like "BRAND ICING SUGAR 1KG".
_KG_HINT = re.compile(r"(?i)(?<!\d)(\d+(?:\.\d+)?)\s*(?:kg|k\s*g)\b")


def extract_kg_hint_from_text(text: str | None) -> Decimal | None:
    if not text:
        return None
    matches = list(_KG_HINT.finditer(text.strip()))
    if not matches:
        return None
    return Decimal(matches[-1].group(1))


def catalog_pack_kg_hint(item: CatalogItem) -> Decimal | None:
    if item.default_kg_per_bag is not None:
        return Decimal(str(item.default_kg_per_bag))
    return extract_kg_hint_from_text(item.name)


def _norm_unit(u: str | None) -> str:
    return (u or "").strip().lower()


def unit_channel_conflict(line_unit: str, catalog: CatalogItem) -> bool:
    """True when scanned unit implies a different wholesale/retail channel than catalog defaults."""
    lu = (line_unit or "").strip().upper()
    du = _norm_unit(catalog.default_unit)
    pu = _norm_unit(getattr(catalog, "default_purchase_unit", None))
    eff = du or pu
    if lu == "BAG" and eff in ("piece", "pcs", "pkt", "packet"):
        return True
    if lu in ("PCS", "PIECE") and eff == "bag":
        return True
    return False


def pack_kg_substantially_differs(a: Decimal, b: Decimal) -> bool:
    tol = max(Decimal("1"), min(abs(a), abs(b)) * Decimal("0.15"))
    return abs(a - b) > tol


def should_demote_item_match(*, row: ItemRow, catalog: CatalogItem) -> bool:
    if row.match_state != "auto" or row.matched_catalog_item_id is None:
        return False

    if unit_channel_conflict(row.unit_type, catalog):
        return True

    line_hint = row.weight_per_unit_kg or extract_kg_hint_from_text(row.raw_name)
    cat_hint = catalog_pack_kg_hint(catalog)
    if line_hint is not None and cat_hint is not None:
        return pack_kg_substantially_differs(line_hint, cat_hint)

    return False


async def apply_pack_gates_to_item_rows(
    db: AsyncSession,
    business_id: uuid.UUID,
    rows: list[ItemRow],
) -> list[ItemRow]:
    """Demote unsafe auto matches to ``needs_confirmation`` (keep candidates for UI)."""
    ids: list[uuid.UUID] = []
    for r in rows:
        if r.match_state == "auto" and r.matched_catalog_item_id is not None:
            ids.append(r.matched_catalog_item_id)
    if not ids:
        return rows

    stmt = select(CatalogItem).where(
        CatalogItem.business_id == business_id,
        CatalogItem.id.in_(ids),
    )
    res = await db.execute(stmt)
    by_id: dict[uuid.UUID, CatalogItem] = {x.id: x for x in res.scalars().all()}

    out: list[ItemRow] = []
    for r in rows:
        cid = r.matched_catalog_item_id
        if r.match_state != "auto" or cid is None:
            out.append(r)
            continue
        cat = by_id.get(cid)
        if cat is None or not should_demote_item_match(row=r, catalog=cat):
            out.append(r)
            continue
        out.append(
            r.model_copy(
                update={
                    "matched_catalog_item_id": None,
                    "matched_name": None,
                    "match_state": "needs_confirmation",
                    "confidence": min(float(r.confidence), 0.69),
                }
            )
        )
    return out
