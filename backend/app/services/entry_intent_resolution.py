"""Map transactional parser `data` dict → EntryCreateRequest and resolve supplier/broker IDs (in-app assistant + legacy parsers)."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Broker, Supplier
from app.schemas.entries import EntryCreateRequest, EntryLineInput
from app.services.entry_intent_resolution_v2 import EntityFieldResolver


def ist_today() -> date:
    ist = datetime.now(timezone.utc) + timedelta(hours=5, minutes=30)
    return ist.date()


def _parse_float(v: object) -> float | None:
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    s = str(v).strip().replace(",", "")
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _parse_date(v: object) -> date | None:
    if v is None:
        return None
    if isinstance(v, date) and not isinstance(v, datetime):
        return v
    s = str(v).strip()[:10]
    try:
        return date.fromisoformat(s)
    except ValueError:
        return None


async def find_supplier_id_by_name(
    db: AsyncSession,
    business_id: uuid.UUID,
    name: str | None,
) -> uuid.UUID | None:
    if not name or not str(name).strip():
        return None
    needle = str(name).strip()
    r = await db.execute(
        select(Supplier.id).where(
            Supplier.business_id == business_id,
            Supplier.name.ilike(f"%{needle}%"),
        )
    )
    row = r.first()
    return row[0] if row else None


async def find_broker_id_by_name(
    db: AsyncSession,
    business_id: uuid.UUID,
    name: str | None,
) -> uuid.UUID | None:
    if not name or not str(name).strip():
        return None
    needle = str(name).strip()
    r = await db.execute(
        select(Broker.id).where(
            Broker.business_id == business_id,
            Broker.name.ilike(f"%{needle}%"),
        )
    )
    row = r.first()
    return row[0] if row else None


def merge_kv_into_create_data(base: dict[str, Any], kv: dict[str, str]) -> dict[str, Any]:
    """Merge follow-up key:value lines into parser ``data`` (multi-turn draft)."""
    out = dict(base)
    for k, v in kv.items():
        lk = str(k).strip().lower().replace(" ", "_")
        if lk in ("item", "name", "product"):
            out["item"] = v
        elif lk in ("qty", "quantity"):
            out["qty"] = v
        elif lk == "unit":
            out["unit"] = v
        elif lk in ("buy", "buy_price", "rate", "bp"):
            out["buy_price"] = v
        elif lk in ("land", "landing", "landing_cost", "lc"):
            out["landing_cost"] = v
        elif lk in ("sell", "selling_price", "selling"):
            out["selling_price"] = v
        elif lk == "supplier":
            out["supplier_name"] = v
        elif lk == "broker":
            out["broker_name"] = v
        elif lk in ("date", "entry_date"):
            out["entry_date"] = v
    return out


async def build_entry_create_request(
    db: AsyncSession,
    business_id: uuid.UUID,
    data: dict[str, object],
) -> tuple[EntryCreateRequest | None, list[str]]:
    """
    Build a single-line EntryCreateRequest from parser data.
    Returns (request, missing_fields) — missing_fields non-empty means cannot preview.
    """
    # Keep raw keys (buy_price vs landing_cost) before alias merge — resolver maps
    # several rate aliases onto `landing_cost` only, which would hide invalid buy_price.
    raw = {str(k): v for k, v in data.items()}
    data = EntityFieldResolver.resolve_entity_fields(dict(data))

    item = (
        data.get("item_name")
        or data.get("item")
        or raw.get("item")
        or raw.get("item_name")
    )
    if not item or not str(item).strip():
        return None, ["item"]

    qty = _parse_float(data.get("qty")) if data.get("qty") is not None else _parse_float(raw.get("qty"))
    unit = (str(data.get("unit") or raw.get("unit") or "kg")).lower().strip()
    if unit not in ("kg", "box", "piece", "bag"):
        unit = "kg"

    buy = _parse_float(raw.get("buy_price"))
    land = _parse_float(raw.get("landing_cost"))
    sell = _parse_float(data.get("selling_price")) if data.get("selling_price") is not None else _parse_float(
        raw.get("selling_price")
    )

    # Reject explicit non-positive buy rate before aliasing to landing_cost.
    if raw.get("buy_price") is not None and buy is not None and buy <= 0:
        return None, ["buy_price"]

    # Single rate field: landing and "buy" are the same for trade/entry lines.
    if buy is not None and buy > 0 and (land is None or land <= 0):
        land = buy
    if land is not None and land > 0 and (buy is None or buy <= 0):
        buy = land

    missing: list[str] = []
    if qty is None or qty <= 0:
        missing.append("qty")
    if (buy is None or buy <= 0) and (land is None or land <= 0):
        missing.append("landing_cost")
    if missing:
        return None, missing

    ed = (
        _parse_date(data.get("entry_date"))
        or _parse_date(raw.get("entry_date"))
        or ist_today()
    )

    sup_nm = data.get("supplier_name") or raw.get("supplier_name")
    br_nm = data.get("broker_name") or raw.get("broker_name")
    sup_id = await find_supplier_id_by_name(db, business_id, sup_nm if sup_nm else None)
    br_id = await find_broker_id_by_name(db, business_id, br_nm if br_nm else None)

    line = EntryLineInput(
        item_name=str(item).strip(),
        category=None,
        qty=qty,
        unit=unit,  # type: ignore[arg-type]
        buy_price=buy,
        landing_cost=land,
        selling_price=sell,
    )

    return (
        EntryCreateRequest(
            entry_date=ed,
            supplier_id=sup_id,
            broker_id=br_id,
            confirm=False,
            lines=[line],
        ),
        [],
    )
