"""Owner-gated credentials, staff tasks, and command-center dashboard."""

from __future__ import annotations

import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user, require_owner_membership, require_membership
from app.models import Membership, User
from app.models.admin_audit_log import AdminAuditLog
from app.services import owner_dashboard as od
from app.services import provider_credentials as pc
from app.services import staff_tasks as st

credentials_router = APIRouter(
    prefix="/v1/businesses/{business_id}/settings/credentials",
    tags=["owner-settings"],
)
staff_router = APIRouter(
    prefix="/v1/businesses/{business_id}/staff",
    tags=["staff-tasks"],
)
owner_router = APIRouter(
    prefix="/v1/businesses/{business_id}/owner",
    tags=["owner-dashboard"],
)


class CredentialPut(BaseModel):
    value: str = Field(min_length=1, max_length=4096)


class StaffTaskCreate(BaseModel):
    staff_id: uuid.UUID
    task_type: str = "general"
    reference_id: str | None = None


class StaffTaskComplete(BaseModel):
    rejected: bool = False
    correction_note: str | None = None


@credentials_router.get("")
async def get_credentials(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    return {"items": await pc.list_credentials(db, business_id)}


@credentials_router.put("/{credential_type}")
async def put_credential(
    business_id: uuid.UUID,
    credential_type: str,
    body: CredentialPut,
    m: Annotated[Membership, Depends(require_owner_membership)],
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    try:
        row = await pc.upsert_credential(
            db,
            business_id=business_id,
            credential_type=credential_type,
            value=body.value,
            updated_by=user.id,
        )
    except ValueError as e:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    db.add(
        AdminAuditLog(
            actor=str(user.id),
            action="provider_credential_upsert",
            resource_type="provider_credential",
            resource_id=credential_type,
            details={
                "business_id": str(business_id),
                "credential_type": credential_type,
                "last_4_chars": row.last_4_chars,
            },
            note="value never logged",
        )
    )
    await db.commit()
    return {
        "credential_type": row.credential_type,
        "last_4_chars": row.last_4_chars,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
    }


@staff_router.get("/tasks")
async def list_all_tasks(
    business_id: uuid.UUID,
    m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    status_filter: str | None = None,
):
    # Owner/manager see all; staff see own only.
    staff_only = m.role not in ("owner", "manager") and not getattr(
        m, "is_super_admin", False
    )
    staff_id = m.user_id if staff_only else None
    rows = await st.list_tasks(
        db, business_id, staff_id=staff_id, status=status_filter
    )
    return {"items": [st.task_to_dict(t) for t in rows]}


@staff_router.get("/{staff_id}/tasks")
async def list_staff_tasks(
    business_id: uuid.UUID,
    staff_id: uuid.UUID,
    m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    if m.role not in ("owner", "manager") and m.user_id != staff_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="Forbidden")
    rows = await st.list_tasks(db, business_id, staff_id=staff_id)
    return {"items": [st.task_to_dict(t) for t in rows]}


@staff_router.post("/tasks")
async def create_staff_task(
    business_id: uuid.UUID,
    body: StaffTaskCreate,
    m: Annotated[Membership, Depends(require_owner_membership)],
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del m
    t = await st.create_task(
        db,
        business_id=business_id,
        staff_id=body.staff_id,
        task_type=body.task_type,
        reference_id=body.reference_id,
        created_by=user.id,
    )
    return st.task_to_dict(t)


@staff_router.post("/tasks/{task_id}/accept")
async def accept_staff_task(
    business_id: uuid.UUID,
    task_id: uuid.UUID,
    m: Annotated[Membership, Depends(require_membership)],
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del m
    try:
        t = await st.accept_task(db, business_id, task_id, user.id)
    except LookupError as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail=str(e)) from e
    except PermissionError as e:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=str(e)) from e
    return st.task_to_dict(t)


@staff_router.post("/tasks/{task_id}/complete")
async def complete_staff_task(
    business_id: uuid.UUID,
    task_id: uuid.UUID,
    body: StaffTaskComplete,
    m: Annotated[Membership, Depends(require_membership)],
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del m
    try:
        t = await st.complete_task(
            db,
            business_id,
            task_id,
            user.id,
            rejected=body.rejected,
            correction_note=body.correction_note,
        )
    except LookupError as e:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail=str(e)) from e
    except PermissionError as e:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail=str(e)) from e
    return st.task_to_dict(t)


@staff_router.get("/performance-summary")
async def staff_performance_summary(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
):
    del _m
    return {"items": await st.performance_summary(db, business_id)}


@owner_router.get("/dashboard")
async def owner_dashboard(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_owner_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, Any]:
    del _m
    return await od.build_owner_dashboard(db, business_id)
