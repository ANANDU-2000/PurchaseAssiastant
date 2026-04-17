"""Wholesale trade purchase API (PUR-YYYY-XXXX), parallel to legacy entries."""

from __future__ import annotations

import uuid
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
    TradePurchaseCreateRequest,
    TradePurchaseOut,
)
from app.services import trade_purchase_service as tps

router = APIRouter(prefix="/v1/businesses/{business_id}/trade-purchases", tags=["trade-purchases"])


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


@router.get("", response_model=list[TradePurchaseOut])
async def list_trade_purchases(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    limit: int = Query(50, ge=1, le=200),
):
    del user
    return await tps.list_trade_purchases(db, business_id, limit=limit)


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
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e


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
