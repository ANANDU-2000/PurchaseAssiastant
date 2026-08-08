"""Staff task assignment lifecycle."""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.owner_ops import StaffTask


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def task_to_dict(t: StaffTask) -> dict[str, Any]:
    return {
        "id": str(t.id),
        "business_id": str(t.business_id),
        "staff_id": str(t.staff_id),
        "task_type": t.task_type,
        "reference_id": t.reference_id,
        "status": t.status,
        "rejected": t.rejected,
        "correction_note": t.correction_note,
        "assigned_at": t.assigned_at.isoformat() if t.assigned_at else None,
        "accepted_at": t.accepted_at.isoformat() if t.accepted_at else None,
        "completed_at": t.completed_at.isoformat() if t.completed_at else None,
        "created_by": str(t.created_by) if t.created_by else None,
    }


async def list_tasks(
    db: AsyncSession,
    business_id: uuid.UUID,
    *,
    staff_id: uuid.UUID | None = None,
    status: str | None = None,
) -> list[StaffTask]:
    q = select(StaffTask).where(StaffTask.business_id == business_id)
    if staff_id is not None:
        q = q.where(StaffTask.staff_id == staff_id)
    if status:
        q = q.where(StaffTask.status == status)
    q = q.order_by(StaffTask.assigned_at.desc()).limit(500)
    return list((await db.execute(q)).scalars().all())


async def create_task(
    db: AsyncSession,
    *,
    business_id: uuid.UUID,
    staff_id: uuid.UUID,
    task_type: str,
    reference_id: str | None,
    created_by: uuid.UUID | None,
) -> StaffTask:
    t = StaffTask(
        business_id=business_id,
        staff_id=staff_id,
        task_type=(task_type or "general")[:64],
        reference_id=reference_id,
        created_by=created_by,
        status="assigned",
    )
    db.add(t)
    await db.commit()
    await db.refresh(t)
    return t


async def accept_task(
    db: AsyncSession, business_id: uuid.UUID, task_id: uuid.UUID, actor_id: uuid.UUID
) -> StaffTask:
    t = await db.get(StaffTask, task_id)
    if t is None or t.business_id != business_id:
        raise LookupError("task not found")
    if t.staff_id != actor_id:
        raise PermissionError("not your task")
    t.status = "accepted"
    t.accepted_at = _utcnow()
    await db.commit()
    await db.refresh(t)
    return t


async def complete_task(
    db: AsyncSession,
    business_id: uuid.UUID,
    task_id: uuid.UUID,
    actor_id: uuid.UUID,
    *,
    rejected: bool = False,
    correction_note: str | None = None,
) -> StaffTask:
    t = await db.get(StaffTask, task_id)
    if t is None or t.business_id != business_id:
        raise LookupError("task not found")
    if t.staff_id != actor_id:
        raise PermissionError("not your task")
    t.status = "rejected" if rejected else "completed"
    t.rejected = rejected
    t.correction_note = correction_note
    t.completed_at = _utcnow()
    await db.commit()
    await db.refresh(t)
    return t


async def performance_summary(
    db: AsyncSession, business_id: uuid.UUID
) -> list[dict[str, Any]]:
    """Pre-aggregated per staff for owner dashboard (in-process; table stays small)."""
    rows = await list_tasks(db, business_id)
    by_staff: dict[uuid.UUID, dict[str, int]] = {}
    for t in rows:
        bucket = by_staff.setdefault(
            t.staff_id,
            {"total": 0, "completed": 0, "pending": 0, "rejected": 0},
        )
        bucket["total"] += 1
        if t.rejected or t.status == "rejected":
            bucket["rejected"] += 1
        elif t.status == "completed":
            bucket["completed"] += 1
        elif t.status in ("assigned", "accepted"):
            bucket["pending"] += 1
    return [
        {"staff_id": str(sid), **counts} for sid, counts in by_staff.items()
    ]
