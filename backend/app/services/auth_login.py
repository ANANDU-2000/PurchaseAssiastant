"""Resolve login email to a User row."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User


def normalize_login_email(email: str) -> str:
    return (email or "").strip().lower()


async def resolve_user_by_email(db: AsyncSession, email: str) -> User | None:
    normalized = normalize_login_email(email)
    if not normalized or "@" not in normalized:
        return None
    r = await db.execute(select(User).where(User.email == normalized))
    return r.scalar_one_or_none()
