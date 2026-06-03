"""Server-side export bytes: stock inventory XLSX and monthly purchase PDF."""

from __future__ import annotations

import io
import uuid
from datetime import date
from decimal import Decimal

from openpyxl import Workbook
from openpyxl.styles import Font
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import CatalogItem, CategoryType, ItemCategory, Supplier, TradePurchase, TradePurchaseLine
from app.services.stock_inventory import catalog_reorder, catalog_stock_qty, stock_status
from app.services import trade_query as tq


async def fetch_stock_inventory_rows(
    db: AsyncSession, business_id: uuid.UUID
) -> list[dict[str, str | float | None]]:
    stmt = (
        select(CatalogItem, ItemCategory.name, CategoryType.name)
        .join(ItemCategory, CatalogItem.category_id == ItemCategory.id)
        .outerjoin(CategoryType, CatalogItem.type_id == CategoryType.id)
        .where(
            CatalogItem.business_id == business_id,
            CatalogItem.deleted_at.is_(None),
        )
        .order_by(CatalogItem.name.asc())
    )
    rows = (await db.execute(stmt)).all()
    sup_ids = {item.last_supplier_id for item, _, _ in rows if item.last_supplier_id}
    sup_names: dict[uuid.UUID, str] = {}
    if sup_ids:
        sr = await db.execute(select(Supplier.id, Supplier.name).where(Supplier.id.in_(sup_ids)))
        sup_names = {row[0]: (row[1] or "") for row in sr.all()}

    out: list[dict[str, str | float | None]] = []
    for item, cat_name, type_name in rows:
        cur = catalog_stock_qty(item)
        ro = catalog_reorder(item)
        sup = sup_names.get(item.last_supplier_id) if item.last_supplier_id else None
        unit = (item.stock_unit or item.default_unit or "").strip()
        opening = float(item.opening_stock_qty or 0) if getattr(item, "opening_stock_qty", None) is not None else None
        updated = ""
        if item.last_stock_updated_at:
            updated = item.last_stock_updated_at.isoformat(timespec="minutes")
        out.append(
            {
                "item_code": (item.item_code or "").strip(),
                "name": (item.name or "").strip(),
                "category": (cat_name or "").strip(),
                "subcategory": (type_name or "").strip(),
                "supplier": (sup or "").strip(),
                "unit": unit,
                "current_stock": float(cur),
                "opening_stock": opening,
                "reorder_level": float(ro),
                "stock_status": stock_status(cur, ro),
                "rack_location": (item.rack_location or "").strip(),
                "barcode": (getattr(item, "barcode", None) or "").strip(),
                "last_updated": updated,
            }
        )
    return out


def build_stock_inventory_xlsx(rows: list[dict[str, str | float | None]]) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Stock"
    headers = [
        "Item Code",
        "Item Name",
        "Category",
        "Subcategory",
        "Supplier",
        "Unit",
        "Current Qty",
        "Opening Qty",
        "Reorder Level",
        "Status",
        "Rack",
        "Barcode",
        "Last Updated",
    ]
    ws.append(headers)
    for cell in ws[1]:
        cell.font = Font(bold=True)
    for r in rows:
        ws.append(
            [
                r.get("item_code"),
                r.get("name"),
                r.get("category"),
                r.get("subcategory"),
                r.get("supplier"),
                r.get("unit"),
                r.get("current_stock"),
                r.get("opening_stock"),
                r.get("reorder_level"),
                r.get("stock_status"),
                r.get("rack_location"),
                r.get("barcode"),
                r.get("last_updated"),
            ]
        )
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


async def fetch_month_trade_purchases(
    db: AsyncSession, business_id: uuid.UUID, *, month_start: date, month_end: date
) -> list[TradePurchase]:
    conds = [
        TradePurchase.business_id == business_id,
        tq.trade_purchase_status_in_reports(),
        TradePurchase.purchase_date >= month_start,
        TradePurchase.purchase_date <= month_end,
    ]
    pr = await db.execute(
        select(TradePurchase)
        .where(*conds)
        .options(selectinload(TradePurchase.supplier_row))
        .order_by(TradePurchase.purchase_date.desc(), TradePurchase.human_id.desc())
        .limit(2000)
    )
    return list(pr.scalars().all())


def build_purchases_month_pdf(
    *,
    business_label: str,
    month_start: date,
    month_end: date,
    purchases: list[TradePurchase],
) -> bytes:
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=14 * mm, rightMargin=14 * mm)
    styles = getSampleStyleSheet()
    story: list = []
    title = f"Purchase history — {month_start.strftime('%B %Y')}"
    story.append(Paragraph(title, styles["Title"]))
    story.append(
        Paragraph(
            f"{business_label}<br/>{month_start.isoformat()} to {month_end.isoformat()}",
            styles["Normal"],
        )
    )
    story.append(Spacer(1, 8))

    if not purchases:
        story.append(Paragraph("No trade purchases in this month.", styles["Normal"]))
    else:
        data = [["Bill", "Date", "Supplier", "Status", "Total", "Paid", "Balance"]]
        sum_tot = Decimal(0)
        sum_paid = Decimal(0)
        for p in purchases:
            tot = Decimal(p.total_amount or 0)
            paid = Decimal(p.paid_amount or 0)
            bal = tot - paid
            sum_tot += tot
            sum_paid += paid
            sup = ""
            if p.supplier_row is not None:
                sup = (p.supplier_row.name or "").strip()[:40]
            data.append(
                [
                    (p.human_id or "")[:16],
                    p.purchase_date.isoformat() if p.purchase_date else "",
                    sup,
                    (p.status or "")[:12],
                    f"{float(tot):,.2f}",
                    f"{float(paid):,.2f}",
                    f"{float(bal):,.2f}",
                ]
            )
        data.append(
            [
                "TOTAL",
                "",
                "",
                "",
                f"{float(sum_tot):,.2f}",
                f"{float(sum_paid):,.2f}",
                f"{float(sum_tot - sum_paid):,.2f}",
            ]
        )
        table = Table(data, repeatRows=1, colWidths=[22 * mm, 22 * mm, 38 * mm, 18 * mm, 22 * mm, 22 * mm, 22 * mm])
        table.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#17A8A7")),
                    ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                    ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                    ("FONTSIZE", (0, 0), (-1, -1), 8),
                    ("GRID", (0, 0), (-1, -1), 0.25, colors.grey),
                    ("FONTNAME", (0, -1), (-1, -1), "Helvetica-Bold"),
                ]
            )
        )
        story.append(table)

    doc.build(story)
    return buf.getvalue()
