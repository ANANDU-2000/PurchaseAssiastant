"""Scheduled/manual JSON backup + dry-run restore helpers."""

from __future__ import annotations

import json
import logging
import os
import time
import uuid
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import CatalogItem, StockAudit, Supplier, TradePurchase, TradePurchaseLine
from app.models.owner_ops import BackupLog
from app.services import trade_query as tq

logger = logging.getLogger(__name__)

SCHEMA_VERSION = "harisree-backup-v1"


def backup_root() -> Path:
    raw = (os.environ.get("BACKUP_DIR") or "").strip()
    if raw:
        return Path(raw)
    # Windows-friendly default beside the process cwd; override with BACKUP_DIR.
    return Path(os.environ.get("LOCALAPPDATA") or ".") / "HarisreeBackups"


async def build_backup_payload(
    db: AsyncSession, business_id: uuid.UUID
) -> tuple[dict[str, Any], dict[str, int]]:
    """Reuse the shape of GET /exports/backup/export (uncapped for scheduled)."""
    today = date.today()
    catalog_rows = (
        await db.execute(
            select(CatalogItem)
            .where(
                CatalogItem.business_id == business_id,
                CatalogItem.deleted_at.is_(None),
            )
            .order_by(CatalogItem.name.asc())
        )
    ).scalars().all()
    supplier_rows = (
        await db.execute(
            select(Supplier)
            .where(Supplier.business_id == business_id)
            .order_by(Supplier.name.asc())
        )
    ).scalars().all()
    pr = await db.execute(
        select(TradePurchase)
        .where(
            TradePurchase.business_id == business_id,
            tq.trade_purchase_status_in_reports(),
        )
        .options(selectinload(TradePurchase.supplier_row))
        .order_by(TradePurchase.purchase_date.desc())
    )
    purchases = list(pr.scalars().all())
    purchase_ids = [p.id for p in purchases]
    lines_by_purchase: dict[uuid.UUID, list[TradePurchaseLine]] = {}
    if purchase_ids:
        lr = await db.execute(
            select(TradePurchaseLine).where(
                TradePurchaseLine.trade_purchase_id.in_(purchase_ids)
            )
        )
        for ln in lr.scalars().all():
            lines_by_purchase.setdefault(ln.trade_purchase_id, []).append(ln)

    audit_rows = (
        await db.execute(
            select(StockAudit)
            .where(StockAudit.business_id == business_id)
            .order_by(StockAudit.created_at.desc())
            .limit(2000)
        )
    ).scalars().all()

    def _purchase_row(p: TradePurchase) -> dict[str, Any]:
        return {
            "id": str(p.id),
            "purchase_date": p.purchase_date.isoformat() if p.purchase_date else None,
            "status": p.status,
            "supplier_id": str(p.supplier_id) if p.supplier_id else None,
            "lines": [
                {
                    "id": str(ln.id),
                    "catalog_item_id": str(ln.catalog_item_id)
                    if ln.catalog_item_id
                    else None,
                    "qty": float(ln.qty or 0),
                }
                for ln in lines_by_purchase.get(p.id, [])
            ],
        }

    payload = {
        "schema_version": SCHEMA_VERSION,
        "business_id": str(business_id),
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "catalog": [
            {
                "id": str(i.id),
                "name": i.name,
                "item_code": i.item_code,
                "barcode": i.barcode,
                "default_unit": i.default_unit,
                "current_stock": float(i.current_stock or 0),
            }
            for i in catalog_rows
        ],
        "suppliers": [
            {"id": str(s.id), "name": s.name} for s in supplier_rows
        ],
        "purchases": [_purchase_row(p) for p in purchases],
        "stock_audits": [
            {"id": str(a.id), "created_at": a.created_at.isoformat() if a.created_at else None}
            for a in audit_rows
        ],
    }
    counts = {
        "catalog": len(payload["catalog"]),
        "suppliers": len(payload["suppliers"]),
        "purchases": len(payload["purchases"]),
        "stock_audits": len(payload["stock_audits"]),
    }
    return payload, counts


async def write_scheduled_backup(
    db: AsyncSession, business_id: uuid.UUID, *, run_type: str = "scheduled"
) -> BackupLog:
    started = time.perf_counter()
    root = backup_root() / str(business_id)
    root.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = root / f"backup_{stamp}.json"
    try:
        payload, counts = await build_backup_payload(db, business_id)
        text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        path.write_text(text, encoding="utf-8")
        log = BackupLog(
            business_id=business_id,
            run_type=run_type,
            status="success",
            file_path=str(path),
            size_bytes=path.stat().st_size,
            row_counts=counts,
            duration_ms=int((time.perf_counter() - started) * 1000),
        )
    except Exception as e:  # noqa: BLE001
        logger.exception("backup failed for %s", business_id)
        log = BackupLog(
            business_id=business_id,
            run_type=run_type,
            status="fail",
            file_path=str(path),
            error_message=str(e)[:2000],
            duration_ms=int((time.perf_counter() - started) * 1000),
        )
    db.add(log)
    await db.commit()
    await db.refresh(log)
    return log


def dry_run_restore(payload: dict[str, Any]) -> dict[str, Any]:
    """Validate backup JSON; never writes."""
    version = payload.get("schema_version")
    if version != SCHEMA_VERSION:
        return {
            "ok": False,
            "error": f"schema_version mismatch: got {version!r}, want {SCHEMA_VERSION!r}",
            "would_add": {},
            "conflicts": [],
        }
    if not payload.get("business_id"):
        return {
            "ok": False,
            "error": "missing business_id",
            "would_add": {},
            "conflicts": [],
        }
    would_add = {
        "catalog": len(payload.get("catalog") or []),
        "suppliers": len(payload.get("suppliers") or []),
        "purchases": len(payload.get("purchases") or []),
        "stock_audits": len(payload.get("stock_audits") or []),
    }
    token = str(uuid.uuid4())
    return {
        "ok": True,
        "error": None,
        "would_add": would_add,
        "conflicts": [],
        "confirm_token": token,
        "note": "Dry-run only. Commit restore is blocked until a dedicated import path is approved for production data.",
        "commit_supported": False,
    }


async def apply_retention(db: AsyncSession, business_id: uuid.UUID) -> int:
    """Keep last 14 successful daily logs' files; delete older files on disk."""
    rows = (
        await db.execute(
            select(BackupLog)
            .where(
                BackupLog.business_id == business_id,
                BackupLog.status == "success",
            )
            .order_by(BackupLog.created_at.desc())
        )
    ).scalars().all()
    keep = set()
    for i, row in enumerate(rows):
        if i < 14 and row.file_path:
            keep.add(row.file_path)
    deleted = 0
    for row in rows[14:]:
        if row.file_path and row.file_path not in keep:
            p = Path(row.file_path)
            if p.is_file():
                try:
                    p.unlink()
                    deleted += 1
                except OSError:
                    pass
    return deleted
