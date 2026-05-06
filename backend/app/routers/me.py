import uuid
from datetime import date
from difflib import get_close_matches
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Body, Depends, File, HTTPException, Query, UploadFile, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings, get_settings
from app.database import get_db
from app.deps import get_current_user, require_membership, require_owner_membership
from app.models import Business, Membership, User
from app.models.contacts import Broker, Supplier
from app.services.feature_flags import is_ocr_enabled
from app.services.default_workspace import bootstrap_user_workspace
from app.services.scanner_v2.types import ScanResult

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
    name: str | None = Field(None, max_length=255)
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
    if "name" in data:
        n = data["name"]
        if n is None or (isinstance(n, str) and not n.strip()):
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                detail="Business name cannot be empty",
            )
        if isinstance(n, str):
            b.name = n.strip()
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
    purchase_rate: float
    selling_rate: float | None = None
    weight_per_unit_kg: float | None = None


class ScanPurchaseChargesOut(BaseModel):
    delivered_rate: float | None = None
    billty_rate: float | None = None
    freight_amount: float | None = None
    freight_type: str | None = None


class ScanPurchaseMetaOut(BaseModel):
    provider_used: str | None = None
    failover: list[dict] = Field(default_factory=list)
    parse_warnings: list[str] = Field(default_factory=list)


class ScanPurchaseResponse(BaseModel):
    text: str = ""
    confidence: float = 0.0
    supplier_name: str | None = None
    supplier_id: uuid.UUID | None = None
    broker_name: str | None = None
    broker_id: uuid.UUID | None = None
    charges: ScanPurchaseChargesOut = Field(default_factory=ScanPurchaseChargesOut)
    items: list[ScanPurchaseLineOut] = Field(default_factory=list)
    missing_fields: list[str] = Field(default_factory=list)
    requires_user_confirmation: bool = True
    auto_save_allowed: bool = False
    note: str = ""
    meta: ScanPurchaseMetaOut = Field(default_factory=ScanPurchaseMetaOut)


class ScanPurchaseV2CorrectRequest(BaseModel):
    scan_token: str = Field(..., min_length=8)
    alias_type: str = Field(..., pattern="^(item|supplier|broker)$")
    ref_id: uuid.UUID
    raw_text: str = Field(..., min_length=1, max_length=255)


class ScanPurchaseV2ConfirmRequest(BaseModel):
    scan_token: str = Field(..., min_length=8)
    purchase_date: date = Field(default_factory=date.today)
    invoice_number: str | None = Field(None, max_length=64)
    force_duplicate: bool = False
    status: str = Field(default="confirmed", pattern="^(draft|saved|confirmed)$")


class ScanPurchaseV2UpdateRequest(BaseModel):
    scan_token: str = Field(..., min_length=8)
    scan: ScanResult


def _norm_dir_name(s: str) -> str:
    t = (s or "").strip().lower()
    out: list[str] = []
    for ch in t:
        if ch.isalnum() or ch.isspace():
            out.append(ch)
        else:
            out.append(" ")
    return " ".join("".join(out).split())


def _fuzzy_duplicate_hint(name: str, candidates: list[tuple[str, uuid.UUID]], *, cutoff: float) -> uuid.UUID | None:
    """If name is close to an existing directory entry (but not exact), return that id."""
    q = _norm_dir_name(name)
    if len(q) < 3:
        return None
    pool = [( _norm_dir_name(n), i) for (n, i) in candidates if n.strip()]
    norm_names = [n for (n, _) in pool if n]
    if not norm_names:
        return None
    if q in norm_names:
        return None
    matches = get_close_matches(q, norm_names, n=1, cutoff=cutoff)
    if not matches:
        return None
    m0 = matches[0]
    for n, i in pool:
        if n == m0:
            return i
    return None


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
    from app.services import purchase_scan_ai as psai

    text, conf = await pss.image_bytes_to_text(settings, raw)
    if not text.strip():
        # BUGFIX (C2): never treat raw image bytes as text.
        text = ""

    line_strs = [ln.strip() for ln in text.splitlines() if ln.strip()]
    supplier_hint = op.extract_supplier_candidate(line_strs)
    items_raw, missing = op.extract_item_rows(text)
    items_out = [
        ScanPurchaseLineOut(
            name=e["name"],
            qty=float(e["qty"]),
            unit=e["unit"],
            purchase_rate=float(e["rate"]),
        )
        for e in items_raw
    ]
    charges = ScanPurchaseChargesOut()
    broker_hint: str | None = None
    meta_out = ScanPurchaseMetaOut()
    supplier_id: uuid.UUID | None = None
    broker_id: uuid.UUID | None = None

    sup_rows = (
        await db.execute(select(Supplier.id, Supplier.name).where(Supplier.business_id == business_id))
    ).all()
    bro_rows = (
        await db.execute(select(Broker.id, Broker.name).where(Broker.business_id == business_id))
    ).all()
    supplier_candidates: list[tuple[str, uuid.UUID]] = [(str(n), i) for (i, n) in sup_rows]
    broker_candidates: list[tuple[str, uuid.UUID]] = [(str(n), i) for (i, n) in bro_rows]

    # AI parse: best-effort enrich (supplier/broker/items/charges). Never blocks.
    try:
        ai, meta = await psai.parse_scan_text_with_ai(text=text, settings=settings, db=db)
        if ai and isinstance(ai.get("payload"), dict):
            payload = ai["payload"]
            meta_out = ScanPurchaseMetaOut(
                provider_used=meta.get("provider_used"),
                failover=meta.get("failover") or [],
                parse_warnings=ai.get("parse_warnings") or [],
            )
            if isinstance(payload.get("supplier_name"), str) and payload.get("supplier_name").strip():
                supplier_hint = payload.get("supplier_name").strip()
            if isinstance(payload.get("broker_name"), str) and payload.get("broker_name").strip():
                broker_hint = payload.get("broker_name").strip()
            if isinstance(payload.get("charges"), dict):
                ch = payload.get("charges") or {}
                charges = ScanPurchaseChargesOut(
                    delivered_rate=ch.get("delivered_rate"),
                    billty_rate=ch.get("billty_rate"),
                    freight_amount=ch.get("freight_amount"),
                    freight_type=ch.get("freight_type"),
                )
            if isinstance(payload.get("items"), list) and payload.get("items"):
                next_items: list[ScanPurchaseLineOut] = []
                for it in payload.get("items"):
                    if not isinstance(it, dict):
                        continue
                    nm = (it.get("name") or "").strip() or "Unknown item"
                    qty = float(it.get("qty") or 0)
                    unit = (it.get("unit") or "kg").strip().lower() or "kg"
                    pr = float(it.get("purchase_rate") or 0)
                    sr = it.get("selling_rate")
                    wpu = it.get("weight_per_unit_kg")
                    next_items.append(
                        ScanPurchaseLineOut(
                            name=nm,
                            qty=qty,
                            unit=unit,
                            purchase_rate=pr,
                            selling_rate=(float(sr) if sr is not None else None),
                            weight_per_unit_kg=(float(wpu) if wpu is not None else None),
                        )
                    )
                if next_items:
                    items_out = next_items
                ai_missing = ai.get("missing_fields") or []
                if isinstance(ai_missing, list):
                    missing.extend([str(x) for x in ai_missing if x is not None])
    except Exception:
        # AI is best-effort; fallback remains heuristic parser.
        pass

    # Regex header charges (fills gaps when LLM misses shorthand like delhead/billty)
    rx_ch = op.extract_header_charges(text)
    if charges.delivered_rate is None and isinstance(rx_ch.get("delivered_rate"), (int, float)):
        charges.delivered_rate = float(rx_ch["delivered_rate"])
    if charges.billty_rate is None and isinstance(rx_ch.get("billty_rate"), (int, float)):
        charges.billty_rate = float(rx_ch["billty_rate"])
    if charges.freight_amount is None and isinstance(rx_ch.get("freight_amount"), (int, float)):
        charges.freight_amount = float(rx_ch["freight_amount"])
    if charges.freight_type is None and isinstance(rx_ch.get("freight_type"), str):
        charges.freight_type = rx_ch["freight_type"]

    if not supplier_hint:
        missing.append("supplier_name")
    else:
        qn = _norm_dir_name(str(supplier_hint))
        for nm, sid in supplier_candidates:
            if _norm_dir_name(nm) == qn:
                supplier_id = sid
                break
        if supplier_id is None:
            dup = _fuzzy_duplicate_hint(str(supplier_hint), supplier_candidates, cutoff=0.86)
            if dup is not None:
                dup_name = next((nm for nm, i in supplier_candidates if i == dup), None)
                warn = (
                    "supplier_duplicate_risk: extracted name may match an existing supplier "
                    f"({dup_name or 'directory'}) — confirm before creating a duplicate."
                )
                meta_out.parse_warnings = [*meta_out.parse_warnings, warn]

    if broker_hint:
        qb = _norm_dir_name(str(broker_hint))
        for nm, bid in broker_candidates:
            if _norm_dir_name(nm) == qb:
                broker_id = bid
                break
        if broker_id is None:
            dup_b = _fuzzy_duplicate_hint(str(broker_hint), broker_candidates, cutoff=0.86)
            if dup_b is not None:
                dup_name = next((nm for nm, i in broker_candidates if i == dup_b), None)
                warn = (
                    "broker_duplicate_risk: extracted name may match an existing broker "
                    f"({dup_name or 'directory'}) — confirm before creating a duplicate."
                )
                meta_out.parse_warnings = [*meta_out.parse_warnings, warn]

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
            supplier_id=supplier_id,
            broker_name=broker_hint,
            broker_id=broker_id,
            charges=charges,
            items=items_out,
            missing_fields=sorted(set(uniq_missing + (["enable_ocr"] if not items_out else []))),
            requires_user_confirmation=True,
            auto_save_allowed=False,
            note="OCR/cloud vision is off — parsing may be incomplete; confirm before saving.",
            meta=meta_out,
        )

    return ScanPurchaseResponse(
        text=text[:5000],
        confidence=conf if conf > 0 else (0.5 if items_out else 0.25),
        supplier_name=supplier_hint,
        supplier_id=supplier_id,
        broker_name=broker_hint,
        broker_id=broker_id,
        charges=charges,
        items=items_out,
        missing_fields=uniq_missing,
        requires_user_confirmation=True,
        auto_save_allowed=False,
        note="Review and edit extracted fields — no purchase is saved from this endpoint.",
        meta=meta_out,
    )


@router.post("/scan-purchase-v2", response_model=ScanResult)
async def scan_purchase_bill_v2(
    business_id: Annotated[uuid.UUID, Query(..., description="Primary workspace for membership check")],
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
    _m: Annotated[Membership, Depends(require_membership)],
    image: UploadFile = File(..., description="Bill photo (JPEG/PNG/WebP)"),
):
    """Scanner v2: OCR + LLM + matching → editable preview with scan_token.

    NEVER saves. Caller must use /confirm after user review.
    """
    del user
    raw = await image.read()
    if len(raw) == 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Empty upload")
    if len(raw) > 8_000_000:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Image too large (max ~8MB)")
    from app.services.scanner_v2.pipeline import scan_purchase_v2

    return await scan_purchase_v2(db=db, business_id=business_id, settings=settings, image_bytes=raw)


@router.post("/scan-purchase-v2/correct")
async def scan_purchase_bill_v2_correct(
    business_id: Annotated[uuid.UUID, Query(..., description="Primary workspace for membership check")],
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    body: ScanPurchaseV2CorrectRequest = Body(...),
):
    """Persist a user correction as an alias (workspace-scoped learning)."""
    del user
    from sqlalchemy import select

    from app.models.ai_engine import CatalogAlias
    from app.services.scanner_v2.matcher import normalize as norm

    alias_type = body.alias_type.strip().lower()
    name = body.raw_text.strip()
    normalized = norm(name)
    if not normalized:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Empty alias")

    q = await db.execute(
        select(CatalogAlias).where(
            CatalogAlias.business_id == business_id,
            CatalogAlias.alias_type == alias_type,
            CatalogAlias.normalized_name == normalized,
        )
    )
    row = q.scalar_one_or_none()
    if row is None:
        row = CatalogAlias(
            business_id=business_id,
            alias_type=alias_type,
            ref_id=body.ref_id,
            name=name,
            normalized_name=normalized,
        )
        db.add(row)
    else:
        row.ref_id = body.ref_id
        row.name = name
        row.normalized_name = normalized
    await db.commit()
    return {"ok": True}


@router.post("/scan-purchase-v2/confirm")
async def scan_purchase_bill_v2_confirm(
    business_id: Annotated[uuid.UUID, Query(..., description="Primary workspace for membership check")],
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _m: Annotated[Membership, Depends(require_membership)],
    body: ScanPurchaseV2ConfirmRequest = Body(...),
):
    """Confirm the scanned preview and create a TradePurchase (server validated)."""
    from app.schemas.trade_purchases import TradePurchaseCreateRequest
    from app.services.scanner_v2.pipeline import consume_cached_scan_result, scan_result_to_trade_purchase_create
    from app.services.trade_purchase_service import create_trade_purchase

    scan = consume_cached_scan_result(business_id=business_id, scan_token=body.scan_token)
    if scan is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid or expired scan_token")

    payload = scan_result_to_trade_purchase_create(
        business_id=business_id,
        scan=scan,
        purchase_date=body.purchase_date,
        invoice_number=body.invoice_number,
        status=body.status,
        force_duplicate=body.force_duplicate,
    )
    req = TradePurchaseCreateRequest.model_validate(payload)
    return await create_trade_purchase(db, business_id=business_id, user_id=user.id, body=req)


@router.post("/scan-purchase-v2/update")
async def scan_purchase_bill_v2_update(
    business_id: Annotated[uuid.UUID, Query(..., description="Primary workspace for membership check")],
    user: Annotated[User, Depends(get_current_user)],
    _m: Annotated[Membership, Depends(require_membership)],
    body: ScanPurchaseV2UpdateRequest = Body(...),
):
    """Update cached scan result after user edits (preview UI)."""
    del user
    from app.services.scanner_v2.pipeline import update_cached_scan_result

    ok = update_cached_scan_result(business_id=business_id, scan_token=body.scan_token, scan=body.scan)
    if not ok:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="Invalid or expired scan_token")
    return {"ok": True}
