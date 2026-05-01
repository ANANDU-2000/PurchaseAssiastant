import uuid
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import get_current_user, require_membership, require_owner_membership
from app.models import Business, Membership, User
from app.services.feature_flags import is_ocr_enabled
from app.services.default_workspace import bootstrap_user_workspace

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
    gst_number: str | None = None
    address: str | None = None
    phone: str | None = None
    contact_email: str | None = None

    model_config = {"from_attributes": False}


class BootstrapWorkspaceOut(BaseModel):
    business_id: uuid.UUID
    created_business: bool
    seeded: bool
    seed_stats: dict[str, int] | None = None


@router.post("/bootstrap-workspace", response_model=BootstrapWorkspaceOut)
async def post_bootstrap_workspace(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
):
    """Idempotent: ensure a workspace + default catalog/suppliers for this user (single-tenant mode)."""
    data = await bootstrap_user_workspace(db, user, settings)
    return BootstrapWorkspaceOut(**data)


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
            gst_number=b.gst_number,
            address=b.address,
            phone=b.phone,
            contact_email=b.contact_email,
        )
        for m, b in rows
    ]


class BusinessBrandingPatch(BaseModel):
    branding_title: str | None = Field(None, max_length=128)
    branding_logo_url: str | None = Field(None, max_length=512)
    gst_number: str | None = Field(None, max_length=20)
    address: str | None = None
    phone: str | None = Field(None, max_length=32)
    contact_email: str | None = Field(None, max_length=255)


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
    if "gst_number" in data:
        g = data["gst_number"]
        if g is None or (isinstance(g, str) and not g.strip()):
            b.gst_number = None
        elif isinstance(g, str):
            b.gst_number = g.strip().upper()
    if "address" in data:
        a = data["address"]
        b.address = (a.strip() or None) if isinstance(a, str) else a
    if "phone" in data:
        p = data["phone"]
        b.phone = (p.strip() or None) if isinstance(p, str) else p
    if "contact_email" in data:
        e = data["contact_email"]
        if e is None or (isinstance(e, str) and not e.strip()):
            b.contact_email = None
        elif isinstance(e, str):
            b.contact_email = e.strip().lower()
    await db.commit()
    await db.refresh(b)
    return BusinessBrief(
        id=b.id,
        name=b.name,
        role="owner",
        branding_title=b.branding_title,
        branding_logo_url=b.branding_logo_url,
        gst_number=b.gst_number,
        address=b.address,
        phone=b.phone,
        contact_email=b.contact_email,
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
        gst_number=b.gst_number,
        address=b.address,
        phone=b.phone,
        contact_email=b.contact_email,
    )


class ScanPurchaseLineOut(BaseModel):
    name: str
    qty: float
    unit: str
    rate: float


class ScanPurchaseResponse(BaseModel):
    text: str = ""
    confidence: float = 0.0
    supplier_name: str | None = None
    items: list[ScanPurchaseLineOut] = Field(default_factory=list)
    missing_fields: list[str] = Field(default_factory=list)
    requires_user_confirmation: bool = True
    auto_save_allowed: bool = False
    note: str = ""


@router.post("/scan-purchase", response_model=ScanPurchaseResponse)
async def scan_purchase_bill(
    business_id: Annotated[uuid.UUID, Query(..., description="Primary workspace for membership check")],
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    _m: Annotated[Membership, Depends(require_membership)],
    image: UploadFile = File(..., description="Bill photo (JPEG/PNG/WebP)"),
):
    """Multipart bill scan → structured preview only (never creates a purchase)."""
    del user
    raw = await image.read()
    if len(raw) == 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Empty upload")
    if len(raw) > 8_000_000:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Image too large (max ~8MB)")

    from app.services import ocr_parser as op
    from app.services import purchase_scan_service as pss

    text, conf = await pss.image_bytes_to_text(settings, raw)
    if not text.strip():
        text = op.normalize_scan_text(raw)

    line_strs = [ln.strip() for ln in text.splitlines() if ln.strip()]
    supplier_hint = op.extract_supplier_candidate(line_strs)
    items_raw, missing = op.extract_item_rows(text)
    items_out = [
        ScanPurchaseLineOut(name=e["name"], qty=float(e["qty"]), unit=e["unit"], rate=float(e["rate"]))
        for e in items_raw
    ]

    if not supplier_hint:
        missing.append("supplier_name")

    ocr_on = await is_ocr_enabled(db, settings)
    if not text.strip():
        missing.append("readable_text")

    uniq_missing: list[str] = []
    seen: set[str] = set()
    for m in missing:
        if m not in seen:
            seen.add(m)
            uniq_missing.append(m)

    if not ocr_on:
        return ScanPurchaseResponse(
            text=text[:5000],
            confidence=conf if conf > 0 else (0.35 if items_out else 0.0),
            supplier_name=supplier_hint,
            items=items_out,
            missing_fields=sorted(set(uniq_missing + (["enable_ocr"] if not items_out else []))),
            requires_user_confirmation=True,
            auto_save_allowed=False,
            note="OCR/cloud vision is off — parsing may be incomplete; confirm before saving.",
        )

    return ScanPurchaseResponse(
        text=text[:5000],
        confidence=conf if conf > 0 else (0.5 if items_out else 0.25),
        supplier_name=supplier_hint,
        items=items_out,
        missing_fields=uniq_missing,
        requires_user_confirmation=True,
        auto_save_allowed=False,
        note="Review and edit extracted fields — no purchase is saved from this endpoint.",
    )
