"""Ensure every user has a workspace and default catalog/suppliers (single-tenant pragmatic mode)."""

from __future__ import annotations

import asyncio
import logging
import os
import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import sessionmaker

from app.config import Settings
from app.models import Business, Membership, User
from app.models.catalog import ItemCategory
from app.models.contacts import Supplier
from app.services.catalog_suppliers_seed import run_catalog_suppliers_seed
from app.services.mandatory_workspace_seed import run_mandatory_workspace_seed

logger = logging.getLogger(__name__)

_DEFAULT_WORKSPACE_NAME = "Harisree workspace"


def sync_database_url_for_seed(settings: Settings) -> str:
    """Sync driver URL for running catalog_suppliers_seed in a worker thread."""
    # Always match the running async engine (pytest env + HEXA_USE_SQLITE + pooler can diverge from raw env).
    try:
        from app.database import engine as _async_engine

        au = str(_async_engine.url)
        if au.startswith("sqlite+aiosqlite:"):
            tail = au.split("sqlite+aiosqlite:///", 1)[-1]
            return "sqlite:///" + tail
        if au.startswith("sqlite+asyncio"):
            tail = au.split("sqlite+asyncio:///", 1)[-1]
            return "sqlite:///" + tail
    except Exception:
        pass
    raw = (os.environ.get("DATABASE_URL") or os.environ.get("SQLALCHEMY_DATABASE_URI") or "").strip()
    if not raw:
        raw = settings.database_url
    if raw.startswith("sqlite+aiosqlite:"):
        return "sqlite:///" + raw.split("sqlite+aiosqlite:///")[-1]
    if raw.startswith("sqlite:"):
        return raw
    if "+asyncpg" in raw:
        raw = raw.replace("postgresql+asyncpg://", "postgresql://").replace("postgres+asyncpg://", "postgres://")
    elif raw.startswith("postgres://"):
        raw = "postgresql://" + raw.removeprefix("postgres://")
    return raw


async def _needs_default_seed(db: AsyncSession, business_id: uuid.UUID) -> bool:
    sc = await db.execute(select(func.count(Supplier.id)).where(Supplier.business_id == business_id))
    cc = await db.execute(select(func.count(ItemCategory.id)).where(ItemCategory.business_id == business_id))
    n_sup = sc.scalar_one()
    n_cat = cc.scalar_one()
    return n_sup == 0 or n_cat == 0


async def ensure_user_has_business(db: AsyncSession, user: User) -> tuple[Business, bool]:
    """
    If the user has no membership, create a default Business + owner Membership.
    Returns (business, created).
    """
    q = await db.execute(
        select(Membership, Business)
        .join(Business, Business.id == Membership.business_id)
        .where(Membership.user_id == user.id)
        .order_by(Membership.created_at.asc())
        .limit(1)
    )
    row = q.first()
    if row:
        return row[1], False
    biz = Business(name=_DEFAULT_WORKSPACE_NAME)
    db.add(biz)
    await db.flush()
    db.add(Membership(user_id=user.id, business_id=biz.id, role="owner"))
    await db.commit()
    await db.refresh(biz)
    return biz, True


def _run_mandatory_only_sync(business_id: uuid.UUID, database_url: str) -> dict[str, int]:
    """When full JSON seed is missing, still insert broker + minimum catalog rows."""
    from sqlalchemy import create_engine

    engine = create_engine(database_url, future=True)
    Session = sessionmaker(bind=engine, future=True, expire_on_commit=False)
    with Session() as s:
        stats = run_mandatory_workspace_seed(s, business_id)
        s.commit()
        return stats


def _run_seed_sync(
    business_id: uuid.UUID,
    database_url: str,
    seed_data_dir: str | None = None,
) -> dict[str, int]:
    from pathlib import Path

    from sqlalchemy import create_engine

    engine = create_engine(database_url, future=True)
    Session = sessionmaker(bind=engine, future=True, expire_on_commit=False)
    override = Path(seed_data_dir).expanduser() if (seed_data_dir and seed_data_dir.strip()) else None
    with Session() as s:
        stats = run_catalog_suppliers_seed(s, business_id, seed_data_dir=override)
        mandatory = run_mandatory_workspace_seed(s, business_id)
        for k, v in mandatory.items():
            stats[f"mandatory_{k}"] = v
        s.commit()
        return stats


async def bootstrap_user_workspace(
    db: AsyncSession,
    user: User,
    settings: Settings,
) -> dict:
    """
    Idempotent: ensure business exists; if catalog/suppliers empty, run JSON seed in a thread.
    Returns a dict suitable for BootstrapWorkspaceOut.
    """
    biz, created_biz = await ensure_user_has_business(db, user)
    bid = biz.id

    if not await _needs_default_seed(db, bid):
        return {
            "business_id": bid,
            "created_business": created_biz,
            "seeded": False,
            "seed_stats": None,
        }

    url = sync_database_url_for_seed(settings)
    sd = (settings.seed_data_dir or "").strip() or None
    try:
        stats = await asyncio.to_thread(_run_seed_sync, bid, url, sd)
    except FileNotFoundError as e:
        logger.warning("bootstrap: full JSON seed missing (%s) — applying mandatory minimum only", e)
        try:
            stats = await asyncio.to_thread(_run_mandatory_only_sync, bid, url)
        except Exception:
            logger.exception("bootstrap: mandatory seed failed for business_id=%s", bid)
            return {
                "business_id": bid,
                "created_business": created_biz,
                "seeded": False,
                "seed_stats": None,
            }
        return {
            "business_id": bid,
            "created_business": created_biz,
            "seeded": True,
            "seed_stats": stats,
        }
    except Exception:
        logger.exception("bootstrap: seed failed for business_id=%s", bid)
        raise

    return {
        "business_id": bid,
        "created_business": created_biz,
        "seeded": True,
        "seed_stats": stats,
    }
