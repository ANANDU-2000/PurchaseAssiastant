"""Wholesale trade purchase API (PUR-YYYY-XXXX), parallel to legacy entries."""

from __future__ import annotations

import logging
import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, require_membership
from app.models import Membership, User
from app.schemas.trade_purchases import (
    TradeDraftUpsertRequest,
    TradeDraftOut,
    TradeDuplicateCheckRequest,
    TradeDuplicateCheckResponse,
    TradeMarkPaidRequest,
    TradeNextHumanIdOut,
    TradePurchaseCreateRequest,
    TradePurchaseOut,
    TradePurchasePaymentPatch,
    TradePurchaseUpdateRequest,
)
from app.services import trade_purchase_service as tps

router = APIRouter(prefix="/v1/businesses/{business_id}/trade-purchases", tags=["trade-purchases"])
_log = logging.getLogger(__name__)

_ALLOWED_TRADE_LIST_STATUSES = frozenset({"draft", "due_soon", "overdue", "paid"})


def _normalize_trade_list_status(status: str | None) -> str | None:
    """Map query `status` to a value the list service understands, or None (= all). Never 422."""
    if status is None:
        return None
    s = status.strip().lower()
    if not s or s in ("all", "undefined", "null"):
        return None
    if s in _ALLOWED_TRADE_LIST_STATUSES:
        return s
    return None


@router.get("/draft", response_model=TradeDraftOut)
async def read_trade_draft(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    d = await tps.get_draft(db, business_id, user.id)
    if not d:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="No draft")
    return d


@router.put("/draft", response_model=TradeDraftOut)
async def upsert_trade_draft(
    business_id: uuid.UUID,
    body: TradeDraftUpsertRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    return await tps.upsert_draft(db, business_id, user.id, body.step, body.payload)


@router.delete("/draft", status_code=status.HTTP_204_NO_CONTENT)
async def delete_trade_draft(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    await tps.delete_draft(db, business_id, user.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/check-duplicate", response_model=TradeDuplicateCheckResponse)
async def check_trade_duplicate(
    business_id: uuid.UUID,
    body: TradeDuplicateCheckRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del user
    return await tps.check_duplicate(db, business_id, body)


@router.get("/next-human-id", response_model=TradeNextHumanIdOut)
async def next_trade_human_id(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del user
    hid = await tps.next_human_id(db, business_id)
    return TradeNextHumanIdOut(human_id=hid)


@router.get("", response_model=list[TradePurchaseOut])
async def list_trade_purchases(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0, le=10_000),
    status: str | None = Query(
        None,
        description="draft|due_soon|overdue|paid; omit or 'all' / unknown = no status filter",
    ),
    q: str | None = Query(None, max_length=200),
    supplier_id: uuid.UUID | None = Query(None),
    broker_id: uuid.UUID | None = Query(None),
    catalog_item_id: uuid.UUID | None = Query(
        None, description="Only purchases that include a line for this catalog item"
    ),
    purchase_from: date | None = Query(
        None, description="Inclusive lower bound on purchase_date (calendar date)"
    ),
    purchase_to: date | None = Query(
        None, description="Inclusive upper bound on purchase_date (calendar date)"
    ),
):
    del user
    limit_v = max(1, min(limit, 50))
    offset_v = max(0, min(offset, 10_000))
    status_norm = _normalize_trade_list_status(status)
    _log.debug(
        "list_trade_purchases business_id=%s limit=%s offset=%s status_raw=%r status_norm=%r q=%s",
        business_id,
        limit_v,
        offset_v,
        status,
        status_norm,
        (q or "").strip()[:80] or None,
    )
    return await tps.list_trade_purchases(
        db,
        business_id,
        limit=limit_v,
        offset=offset_v,
        status_filter=status_norm,
        q=q,
        supplier_id=supplier_id,
        broker_id=broker_id,
        catalog_item_id=catalog_item_id,
        purchase_from=purchase_from,
        purchase_to=purchase_to,
    )


@router.get("/last-defaults")
async def last_trade_purchase_defaults(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    catalog_item_id: uuid.UUID = Query(...),
    supplier_id: uuid.UUID | None = Query(None),
    broker_id: uuid.UUID | None = Query(None),
):
    del user, _m
    return await tps.last_purchase_defaults(
        db,
        business_id,
        catalog_item_id=catalog_item_id,
        supplier_id=supplier_id,
        broker_id=broker_id,
    )


@router.post("", response_model=TradePurchaseOut, status_code=status.HTTP_201_CREATED)
async def create_trade_purchase(
    business_id: uuid.UUID,
    body: TradePurchaseCreateRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    try:
        return await tps.create_trade_purchase(db, business_id, user.id, body)
    except tps.TradePurchaseValidationError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=e.details) from e
    except tps.TradePurchaseDuplicateError as e:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "code": e.code,
                "message": e.message,
                "existing_id": str(e.existing_id),
                "existing_human_id": e.existing_human_id,
            },
        ) from e
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e


@router.patch("/{purchase_id}/payment", response_model=TradePurchaseOut)
async def patch_trade_purchase_payment(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchasePaymentPatch,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del user
    try:
        out = await tps.patch_trade_purchase_payment(db, business_id, purchase_id, body)
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return out


@router.post("/{purchase_id}/mark-paid", response_model=TradePurchaseOut)
async def mark_trade_purchase_paid(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    body: TradeMarkPaidRequest = TradeMarkPaidRequest(),
):
    del user
    try:
        out = await tps.mark_trade_purchase_paid(db, business_id, purchase_id, body)
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return out


@router.post("/{purchase_id}/cancel", response_model=TradePurchaseOut)
async def cancel_trade_purchase(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del user
    out = await tps.cancel_trade_purchase(db, business_id, purchase_id)
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return out


@router.put("/{purchase_id}", response_model=TradePurchaseOut)
async def update_trade_purchase(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    body: TradePurchaseUpdateRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del user
    try:
        out = await tps.update_trade_purchase(db, business_id, purchase_id, body)
    except tps.TradePurchaseValidationError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, detail=e.details) from e
    except tps.TradePurchaseDuplicateError as e:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail={
                "code": e.code,
                "message": e.message,
                "existing_id": str(e.existing_id),
                "existing_human_id": e.existing_human_id,
            },
        ) from e
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return out


@router.delete("/{purchase_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_trade_purchase(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del user
    ok = await tps.delete_trade_purchase(db, business_id, purchase_id)
    if not ok:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/{purchase_id}", response_model=TradePurchaseOut)
async def get_trade_purchase(
    business_id: uuid.UUID,
    purchase_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
):
    del user
    out = await tps.get_trade_purchase(db, business_id, purchase_id)
    if not out:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Purchase not found")
    return out
