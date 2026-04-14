import uuid
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import get_current_user, require_owner_membership
from app.models import Business, Membership, User

_MAX_LOGO_BYTES = 2 * 1024 * 1024
_LOGO_TYPES = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}

router = APIRouter(prefix="/v1/me", tags=["me"])


class UserProfileOut(BaseModel):
    id: uuid.UUID
    email: str
    username: str
    name: str | None = None

    model_config = {"from_attributes": False}


class UserProfilePatch(BaseModel):
    name: str | None = Field(None, max_length=255)


@router.get("/profile", response_model=UserProfileOut)
async def get_my_profile(user: Annotated[User, Depends(get_current_user)]):
    return UserProfileOut(
        id=user.id,
        email=user.email,
        username=user.username,
        name=user.name,
    )


@router.patch("/profile", response_model=UserProfileOut)
async def patch_my_profile(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: UserProfilePatch,
):
    if body.name is not None:
        t = body.name.strip()
        user.name = t if t else None
    await db.commit()
    await db.refresh(user)
    return UserProfileOut(
        id=user.id,
        email=user.email,
        username=user.username,
        name=user.name,
    )


class BusinessBrief(BaseModel):
    id: uuid.UUID
    name: str
    role: str
    branding_title: str | None = None
    branding_logo_url: str | None = None

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
        BusinessBrief(
            id=b.id,
            name=b.name,
            role=m.role,
            branding_title=b.branding_title,
            branding_logo_url=b.branding_logo_url,
        )
        for m, b in rows
    ]


class BusinessBrandingPatch(BaseModel):
    branding_title: str | None = Field(None, max_length=128)
    branding_logo_url: str | None = Field(None, max_length=512)


@router.patch("/businesses/{business_id}/branding", response_model=BusinessBrief)
async def patch_my_business_branding(
    business_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: BusinessBrandingPatch,
):
    """Owner: set optional display name + logo URL for this workspace (data stays isolated by business_id)."""
    if _owner.business_id != business_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Not owner of this business")
    r = await db.execute(select(Business).where(Business.id == business_id))
    b = r.scalar_one_or_none()
    if not b:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Business not found")
    data = body.model_dump(exclude_unset=True)
    if "branding_title" in data:
        t = data["branding_title"]
        b.branding_title = (t.strip() or None) if isinstance(t, str) else t
    if "branding_logo_url" in data:
        u = data["branding_logo_url"]
        b.branding_logo_url = (u.strip() or None) if isinstance(u, str) else u
    await db.commit()
    await db.refresh(b)
    return BusinessBrief(
        id=b.id,
        name=b.name,
        role="owner",
        branding_title=b.branding_title,
        branding_logo_url=b.branding_logo_url,
    )


def _branding_storage_dir() -> Path:
    return Path(__file__).resolve().parents[2] / "static" / "branding"


@router.post("/businesses/{business_id}/branding/logo", response_model=BusinessBrief)
async def upload_business_logo(
    business_id: uuid.UUID,
    _owner: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    file: UploadFile = File(...),
):
    """Owner: upload a logo (JPEG/PNG/WebP, max 2MB). Stored under /static/branding/."""
    if _owner.business_id != business_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Not owner of this business")
    ct = (file.content_type or "").split(";")[0].strip().lower()
    if ct not in _LOGO_TYPES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Use JPEG, PNG, or WebP")
    raw = await file.read()
    if len(raw) > _MAX_LOGO_BYTES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Logo must be 2MB or smaller")
    dest_dir = _branding_storage_dir()
    dest_dir.mkdir(parents=True, exist_ok=True)
    ext = _LOGO_TYPES[ct]
    fname = f"{business_id}{ext}"
    dest = dest_dir / fname
    dest.write_bytes(raw)
    base = settings.app_url.rstrip("/")
    public_url = f"{base}/static/branding/{fname}"
    r = await db.execute(select(Business).where(Business.id == business_id))
    b = r.scalar_one_or_none()
    if not b:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Business not found")
    b.branding_logo_url = public_url
    await db.commit()
    await db.refresh(b)
    return BusinessBrief(
        id=b.id,
        name=b.name,
        role="owner",
        branding_title=b.branding_title,
        branding_logo_url=b.branding_logo_url,
    )
