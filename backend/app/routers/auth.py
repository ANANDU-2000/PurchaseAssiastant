import re
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.models import Business, Membership, User
from app.schemas.auth import (
    GoogleAuthRequest,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenPair,
)
from app.services.google_oauth import verify_google_id_token_async
from app.services.jwt_tokens import create_access_token, create_refresh_token, decode_refresh_token
from app.services.passwords import hash_password, verify_password

router = APIRouter(prefix="/v1/auth", tags=["auth"])


def _username_from_google(email: str, sub: str) -> str:
    local = email.split("@", 1)[0].lower()
    s = re.sub(r"[^a-z0-9_]", "_", local)
    s = re.sub(r"_+", "_", s).strip("_")
    tail = re.sub(r"[^a-z0-9_]", "", sub)[-8:]
    combined = f"{s}_{tail}" if s else f"g_{tail}"
    return combined[:64]


async def _allocate_username(db: AsyncSession, email: str, sub: str) -> str:
    base = _username_from_google(email, sub)
    check = await db.execute(select(User.id).where(User.username == base))
    if not check.first():
        return base
    suffix = uuid.uuid4().hex[:8]
    return f"{base[: 64 - len(suffix) - 1]}_{suffix}"[:64]


@router.post("/register", response_model=TokenPair)
async def register(
    body: RegisterRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    ex = await db.execute(
        select(User.id).where(or_(User.email == body.email, User.username == body.username))
    )
    if ex.first():
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail="An account with this email or username already exists",
        )

    pwd_hash = hash_password(body.password)
    user = User(
        email=body.email,
        username=body.username,
        password_hash=pwd_hash,
        phone=None,
        name=None,
    )
    if settings.superadmin_bootstrap_email and body.email == settings.superadmin_bootstrap_email.strip().lower():
        user.is_super_admin = True

    db.add(user)
    await db.flush()

    biz = Business(name="My business")
    db.add(biz)
    await db.flush()
    db.add(Membership(user_id=user.id, business_id=biz.id, role="owner"))

    await db.commit()
    await db.refresh(user)

    access = create_access_token(user.id, settings)
    refresh = create_refresh_token(user.id, settings)
    return TokenPair(
        access_token=access,
        refresh_token=refresh,
        expires_in=settings.jwt_access_ttl_minutes * 60,
    )


@router.post("/login", response_model=TokenPair)
async def login(
    body: LoginRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    q = await db.execute(select(User).where(User.email == body.email))
    user = q.scalar_one_or_none()
    if (
        not user
        or user.password_hash is None
        or not verify_password(body.password, user.password_hash)
    ):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid email or password")

    access = create_access_token(user.id, settings)
    refresh = create_refresh_token(user.id, settings)
    return TokenPair(
        access_token=access,
        refresh_token=refresh,
        expires_in=settings.jwt_access_ttl_minutes * 60,
    )


@router.post("/google", response_model=TokenPair)
async def auth_google(
    body: GoogleAuthRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    audiences = settings.google_oauth_client_id_list()
    if not audiences:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Google Sign-In is not configured (set GOOGLE_OAUTH_CLIENT_IDS)",
        )
    try:
        claims = await verify_google_id_token_async(body.id_token, audiences)
    except ValueError as e:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail=str(e)) from e

    sub = claims.get("sub")
    email = (claims.get("email") or "").strip().lower()
    if not sub or not email:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Google account has no email")
    if claims.get("email_verified") is False:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Google email is not verified")

    r_sub = await db.execute(select(User).where(User.google_sub == sub))
    user = r_sub.scalar_one_or_none()
    if not user:
        r_email = await db.execute(select(User).where(User.email == email))
        user = r_email.scalar_one_or_none()
        if user:
            if user.google_sub is None:
                user.google_sub = sub
            elif user.google_sub != sub:
                raise HTTPException(
                    status.HTTP_409_CONFLICT,
                    detail="This email is already linked to a different sign-in method",
                )
            await db.commit()
            await db.refresh(user)
        else:
            uname = await _allocate_username(db, email, sub)
            user = User(
                email=email,
                username=uname,
                password_hash=None,
                phone=None,
                name=claims.get("name"),
                google_sub=sub,
            )
            if settings.superadmin_bootstrap_email and email == settings.superadmin_bootstrap_email.strip().lower():
                user.is_super_admin = True
            db.add(user)
            await db.flush()
            biz = Business(name="My business")
            db.add(biz)
            await db.flush()
            db.add(Membership(user_id=user.id, business_id=biz.id, role="owner"))
            await db.commit()
            await db.refresh(user)

    access = create_access_token(user.id, settings)
    refresh = create_refresh_token(user.id, settings)
    return TokenPair(
        access_token=access,
        refresh_token=refresh,
        expires_in=settings.jwt_access_ttl_minutes * 60,
    )


@router.post("/refresh", response_model=TokenPair)
async def refresh_token(
    body: RefreshRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    uid = decode_refresh_token(body.refresh_token, settings)
    if not uid:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
    result = await db.execute(select(User).where(User.id == uid))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, detail="User not found")
    access = create_access_token(user.id, settings)
    refresh = create_refresh_token(user.id, settings)
    return TokenPair(
        access_token=access,
        refresh_token=refresh,
        expires_in=settings.jwt_access_ttl_minutes * 60,
    )
