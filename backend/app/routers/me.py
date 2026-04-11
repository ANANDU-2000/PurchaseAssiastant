import uuid
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import Business, Membership, User

router = APIRouter(prefix="/v1/me", tags=["me"])


class BusinessBrief(BaseModel):
    id: uuid.UUID
    name: str
    role: str

    model_config = {"from_attributes": False}


@router.get("/businesses", response_model=list[BusinessBrief])
async def my_businesses(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    q = await db.execute(
        select(Membership, Business)
        .join(Business, Business.id == Membership.business_id)
        .where(Membership.user_id == user.id)
    )
    rows = q.all()
    return [
        BusinessBrief(id=b.id, name=b.name, role=m.role)
        for m, b in rows
    ]
