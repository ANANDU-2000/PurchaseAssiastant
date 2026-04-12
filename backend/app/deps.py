import uuid
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.models import Membership, User
from app.services.jwt_tokens import decode_access_token

security = HTTPBearer(auto_error=False)


def require_ai_enabled(settings: Annotated[Settings, Depends(get_settings)]) -> None:
    if not settings.enable_ai:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="AI parse is disabled")


def require_realtime_enabled(settings: Annotated[Settings, Depends(get_settings)]) -> None:
    if not settings.enable_realtime:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Realtime is disabled")


async def get_current_user(
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> User:
    if not creds or creds.scheme.lower() != "bearer":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated")
    uid = decode_access_token(creds.credentials, settings)
    if not uid:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token")
    result = await db.execute(select(User).where(User.id == uid))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User not found")
    return user


async def charge_ai_stub_turn(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> User:
    """Gate AI routes: feature flag + monthly token budget (stub accounting)."""
    if not settings.enable_ai:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="AI is disabled for this deployment")
    budget = user.ai_monthly_token_budget
    used = user.ai_tokens_used_month or 0
    if budget is not None and budget > 0 and used >= budget:
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            detail="Monthly AI limit reached — use manual entry or ask an owner to raise the cap.",
        )
    user.ai_tokens_used_month = used + 48
    await db.commit()
    await db.refresh(user)
    return user


async def require_membership(
    business_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Membership:
    q = await db.execute(
        select(Membership).where(
            Membership.business_id == business_id,
            Membership.user_id == user.id,
        )
    )
    m = q.scalar_one_or_none()
    if not m:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not a member of this business")
    return m


async def require_owner_membership(
    membership: Annotated[Membership, Depends(require_membership)],
) -> Membership:
    if membership.role != "owner":
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Owner role required")
    return membership


async def require_super_admin(
    user: Annotated[User, Depends(get_current_user)],
) -> User:
    if not user.is_super_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Super admin only")
    return user
