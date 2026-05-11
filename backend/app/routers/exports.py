"""Business data exports (CSV/ZIP) — no third-party storage; returns bytes."""

from __future__ import annotations

import csv
import io
import uuid
import zipfile
from datetime import date
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.responses import Response

from app.database import get_db
from app.deps import require_membership
from app.models import Membership, TradePurchase, TradePurchaseLine
from app.services import trade_query as tq

router = APIRouter(prefix="/v1/businesses/{business_id}/exports", tags=["exports"])


class BackupRequest(BaseModel):
    range_preset: Literal["month", "quarter", "all"] = Field(
        default="month",
        description="month = calendar month to date; quarter = 90d; all = eligible trade purchases",
    )


def _range_dates(preset: str, today: date) -> tuple[date | None, date]:
    """Inclusive end = today; start None means no lower bound."""
    if preset == "month":
        start = date(today.year, today.month, 1)
        return start, today
    if preset == "quarter":
        from datetime import timedelta

        return today - timedelta(days=89), today
    return None, today


@router.post("/backup")
async def post_backup_zip(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    db: Annotated[AsyncSession, Depends(get_db)],
    body: BackupRequest,
):
    del _m
    today = date.today()
    d_from, d_to = _range_dates(body.range_preset, today)

    conds = [
        TradePurchase.business_id == business_id,
        tq.trade_purchase_status_in_reports(),
    ]
    if d_from is not None:
        conds.append(TradePurchase.purchase_date >= d_from)
    conds.append(TradePurchase.purchase_date <= d_to)

    pr = await db.execute(
        select(TradePurchase).where(*conds).order_by(TradePurchase.purchase_date.desc()).limit(5000)
    )
    purchases = list(pr.scalars().all())
    if not purchases:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            detail="No trade purchases in this range to export.",
        )

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        csv_io = io.StringIO()
        w = csv.writer(csv_io)
        w.writerow(
            [
                "human_id",
                "purchase_date",
                "supplier_id",
                "status",
                "total_amount",
                "invoice_number",
                "line_item",
                "qty",
                "unit",
                "line_total",
            ]
        )
        for p in purchases:
            lr = await db.execute(
                select(TradePurchaseLine).where(TradePurchaseLine.trade_purchase_id == p.id)
            )
            lines = list(lr.scalars().all())
            if not lines:
                w.writerow(
                    [
                        p.human_id,
                        p.purchase_date.isoformat() if p.purchase_date else "",
                        str(p.supplier_id) if p.supplier_id else "",
                        p.status,
                        float(p.total_amount or 0),
                        (p.invoice_number or "").strip(),
                        "",
                        "",
                        "",
                        "",
                    ]
                )
            for ln in lines:
                w.writerow(
                    [
                        p.human_id,
                        p.purchase_date.isoformat() if p.purchase_date else "",
                        str(p.supplier_id) if p.supplier_id else "",
                        p.status,
                        float(p.total_amount or 0),
                        (p.invoice_number or "").strip(),
                        (ln.item_name or "").strip(),
                        float(ln.qty or 0),
                        (ln.unit or "").strip(),
                        float(ln.line_total or 0) if ln.line_total is not None else "",
                    ]
                )
        zf.writestr("purchases.csv", csv_io.getvalue())
        readme = (
            "Purchase Assistant backup\n"
            f"Business: {business_id}\n"
            f"Range: {body.range_preset} (through {d_to.isoformat()})\n"
            "Open purchases.csv in Excel or Google Sheets.\n"
        )
        zf.writestr("README.txt", readme)

    buf.seek(0)
    fname = f"purchase_assistant_backup_{business_id}_{d_to.isoformat()}.zip"
    return Response(
        content=buf.getvalue(),
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{fname}"'},
    )
